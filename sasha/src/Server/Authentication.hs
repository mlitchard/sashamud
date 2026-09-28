{-# LANGUAGE QuasiQuotes #-}

module Server.Authentication
  ( AuthenticatedUser (..)
  , SashaContext
  , authCallback
  , authProxy
  , authStart
  , sashaContext
  , tokenDigest
  ) where

import           SashaPrelude

import           API.Types
  ( AuthenticatedUser (AuthenticatedUser)
  , SessionId (SessionId)
  )
import           Control.Concurrent (modifyMVar, modifyMVar_)
import           Control.Monad.Reader (ask)
import           Crypto.Hash (SHA256 (SHA256), hashWith)
import           Crypto.Random (getRandomBytes)
import           Data.Aeson (eitherDecode)
import           Data.ByteArray (convert)
import           Data.ByteArray.Encoding
  ( Base (Base64URLUnpadded)
  , convertToBase
  )
import           Data.ByteString (ByteString)
import           Data.List (lookup)
import qualified Data.Map.Strict (delete, filter, fromList, insert, lookup)
import           Data.Maybe (catMaybes)
import           Data.Pool (withResource)
import qualified Data.Set (fromList)
import           Data.Text.Encoding (decodeUtf8', encodeUtf8)
import           Data.Time.Clock (diffUTCTime, getCurrentTime)
import           Database.PostgreSQL.Simple
  ( Binary (Binary)
  , Only (Only)
  , execute
  , query
  )
import           Database.PostgreSQL.Simple.SqlQQ (sql)
import           Database.PostgreSQL.Simple.Types (PGArray (fromPGArray))
import           Model.Account
  ( AccessToken (AccessToken)
  , AuthCode (AuthCode)
  , ClientId (ClientId)
  , ClientSecret (ClientSecret)
  , CodeVerifier (CodeVerifier)
  , OidcBaseUrl (OidcBaseUrl)
  , OidcState (OidcState)
  , RedirectUri (RedirectUri)
  , TokenResponse (TokenResponse)
  , UserInfo (UserInfo)
  , UserPermissions (Permissions, PermissionsDisabled)
  )
import           Model.Authorization
  ( Resource
  , ResourceAction
  , RoleId
  , RoleStatus (RoleActive, RoleInactive)
  )
import           Model.Mid (Mid)
import           Network.HTTP.Client
  ( Response (responseBody)
  , applyBearerAuth
  , httpLbs
  , parseRequest
  , setRequestCheckStatus
  , urlEncodedBody
  )
import           Network.HTTP.Types (renderQuery)
import           Network.Wai (Request, requestHeaders)
import           Servant
  ( Context (EmptyContext, (:.))
  , Handler
  , Header
  , Headers
  , NoContent (NoContent)
  , Proxy (Proxy)
  , addHeader
  , err401
  , err409
  , err500
  , throwError
  )
import           Servant.Server.Experimental.Auth (AuthHandler, mkAuthHandler)
import           Server.App
  ( AppCtx (acDbPool, acGameLog, acHttpManager, acOidcConfig, acOidcStates, acSessions)
  , AppM
  , OidcConfig (OidcConfig)
  , SessionPhase (SessionPhase)
  , SessionState (AwaitingSocket)
  )
import           Server.Log (LogEntry (PlayerLogin), writeLog)
import           Server.Validator (PlayerNameVAL (PlayerNameVAL))

type SashaContext :: Type
type SashaContext = Context '[AuthHandler Request AuthenticatedUser]

authProxy :: Proxy '[AuthHandler Request AuthenticatedUser]
authProxy = Proxy

sashaContext :: AppCtx -> SashaContext
sashaContext ctx = mkAuthHandler (authHandler ctx) :. EmptyContext

tokenDigest :: ByteString -> Binary ByteString
tokenDigest bytes = Binary (convert (hashWith SHA256 bytes))

authHandler :: AppCtx -> Request -> Handler AuthenticatedUser
authHandler ctx req =
  case lookup "Sec-WebSocket-Protocol" (requestHeaders req) of
    Nothing -> throwError err401
    Just rawToken -> case decodeUtf8' rawToken of
      Left _ -> throwError err401
      Right t -> do
        rows :: [(Mid AuthenticatedUser, RoleId)] <-
          liftIO . withResource (acDbPool ctx) $ \conn ->
            query conn userQuery (Only (tokenDigest rawToken))
        case rows of
          [(userId, roleId)] -> do
            permissions <- loadPermissions ctx roleId
            pure (AuthenticatedUser (SessionId t) userId permissions)
          _ -> throwError err401
  where
    userQuery =
      [sql|
        SELECT users.user_id, users.role_id FROM tokens
          JOIN users ON users.user_id = tokens.user_id
          WHERE tokens.token_digest = ?
            AND tokens.expires_at > now()
            AND users.status = 'active'
      |]

loadPermissions :: AppCtx -> RoleId -> Handler UserPermissions
loadPermissions ctx roleId = do
  statuses :: [Only RoleStatus] <-
    liftIO . withResource (acDbPool ctx) $ \conn ->
      query conn [sql| SELECT status FROM roles WHERE role_id = ? |] (Only roleId)
  case statuses of
    [Only RoleActive] -> do
      rows :: [Maybe (Resource, PGArray ResourceAction)] <-
        liftIO . withResource (acDbPool ctx) $ \conn ->
          query conn permissionsQuery (Only roleId)
      pure (Permissions (Data.Map.Strict.fromList
        [ (resource, Data.Set.fromList (fromPGArray actions))
        | (resource, actions) <- catMaybes rows
        ]))
    [Only RoleInactive] -> pure PermissionsDisabled
    _ -> throwError err500
  where
    permissionsQuery =
      [sql| SELECT resource, allowed_actions FROM role_permissions WHERE role_id = ? |]

authStart :: AppM (Headers '[Header "Location" Text] NoContent)
authStart = do
  ctx <- ask
  let OidcConfig (OidcBaseUrl base) (ClientId clientId) _ (RedirectUri redirectUri) = acOidcConfig ctx
  stateBytes :: ByteString <- liftIO (getRandomBytes 32)
  verifierBytes :: ByteString <- liftIO (getRandomBytes 32)
  now <- liftIO getCurrentTime
  let state = convertToBase Base64URLUnpadded stateBytes :: ByteString
      verifier = convertToBase Base64URLUnpadded verifierBytes :: ByteString
      challenge = convertToBase Base64URLUnpadded (hashWith SHA256 verifier) :: ByteString
      location = encodeUtf8 base <> "/application/o/authorize/" <> renderQuery True
        [ ("response_type", Just "code")
        , ("client_id", Just (encodeUtf8 clientId))
        , ("redirect_uri", Just (encodeUtf8 redirectUri))
        , ("scope", Just "openid profile")
        , ("state", Just state)
        , ("code_challenge", Just challenge)
        , ("code_challenge_method", Just "S256")
        ]
  case (decodeUtf8' state, decodeUtf8' verifier, decodeUtf8' location) of
    (Right stateText, Right verifierText, Right locationText) -> do
      liftIO . modifyMVar_ (acOidcStates ctx) $ \states ->
        pure (Data.Map.Strict.insert (OidcState stateText) (now, CodeVerifier verifierText)
                (Data.Map.Strict.filter (\(created, _) -> diffUTCTime now created <= 600) states))
      pure (addHeader locationText NoContent)
    _ -> throwError err500

authCallback :: AuthCode -> OidcState -> AppM (Headers '[Header "Location" Text] NoContent)
authCallback (AuthCode code) state = do
  ctx <- ask
  let OidcConfig (OidcBaseUrl base) (ClientId clientId) (ClientSecret secret) (RedirectUri redirectUri) = acOidcConfig ctx
  now <- liftIO getCurrentTime
  entry <- liftIO . modifyMVar (acOidcStates ctx) $ \states ->
    pure (Data.Map.Strict.delete state states, Data.Map.Strict.lookup state states)
  CodeVerifier verifier <- case entry of
    Just (created, v) | diffUTCTime now created <= 600 -> pure v
    _                                                  -> throwError err401
  tokenReq <- liftIO (parseRequest (unpack base <> "/application/o/token/"))
  tokenResp <- liftIO $ httpLbs
    (setRequestCheckStatus (urlEncodedBody
      [ ("grant_type", "authorization_code")
      , ("code", encodeUtf8 code)
      , ("redirect_uri", encodeUtf8 redirectUri)
      , ("client_id", encodeUtf8 clientId)
      , ("client_secret", encodeUtf8 secret)
      , ("code_verifier", encodeUtf8 verifier)
      ] tokenReq))
    (acHttpManager ctx)
  TokenResponse (AccessToken accessToken) <- case eitherDecode (responseBody tokenResp) of
    Left _  -> throwError err401
    Right r -> pure r
  infoReq <- liftIO (parseRequest (unpack base <> "/application/o/userinfo/"))
  infoResp <- liftIO $ httpLbs
    (setRequestCheckStatus (applyBearerAuth (encodeUtf8 accessToken) infoReq))
    (acHttpManager ctx)
  UserInfo subject _ <- case eitherDecode (responseBody infoResp) of
    Left _  -> throwError err401
    Right r -> pure r
  rows :: [(Mid AuthenticatedUser, Text)] <-
    liftIO . withResource (acDbPool ctx) $ \conn ->
      query conn credentialsQuery (Only subject)
  (userId, playerName) <- case rows of
    [(uid, name)] -> pure (uid, PlayerNameVAL name)
    _             -> throwError err401
  tokenBytes :: ByteString <- liftIO (getRandomBytes 32)
  let token = convertToBase Base64URLUnpadded tokenBytes :: ByteString
  tokenText <- case decodeUtf8' token of
    Left _  -> throwError err500
    Right t -> pure t
  _ <- liftIO . withResource (acDbPool ctx) $ \conn ->
    execute conn insertToken (tokenDigest token, userId, userId, userId)
  let sessionId = SessionId tokenText
      hasActiveSession (SessionPhase _ AwaitingSocket) = False
      hasActiveSession (SessionPhase n _)              = n == playerName
      keepEntry (SessionPhase n AwaitingSocket) = n /= playerName
      keepEntry _                               = True
  alreadyActive <- liftIO . modifyMVar (acSessions ctx) $ \sessions ->
    if any hasActiveSession sessions
      then pure (sessions, True)
      else pure (Data.Map.Strict.insert sessionId (SessionPhase playerName AwaitingSocket)
                   (Data.Map.Strict.filter keepEntry sessions), False)
  when alreadyActive (throwError err409)
  liftIO $ writeLog (acGameLog ctx) (PlayerLogin playerName)
  pure (addHeader ("/#token=" <> tokenText) NoContent)
  where
    credentialsQuery =
      [sql|
        SELECT credentials.user_id, credentials.player_name FROM credentials
          JOIN users ON users.user_id = credentials.user_id
          WHERE credentials.subject = ?
            AND users.status = 'active'
      |]
    insertToken =
      [sql|
        INSERT INTO tokens (token_digest, user_id, created, expires_at)
          VALUES (?, ?, now(), now() + interval '1 day');
        DELETE FROM tokens WHERE user_id = ? AND token_digest
          NOT IN (SELECT token_digest FROM tokens WHERE user_id = ?
                    ORDER BY created DESC LIMIT 30);
      |]
