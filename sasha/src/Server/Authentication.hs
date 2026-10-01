{-# LANGUAGE QuasiQuotes       #-}

{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE FlexibleInstances #-}

module Server.Authentication
  ( AuthenticatedUser (..)
  , CanDo
  , SashaContext
  , authAvailable
  , authCallback
  , authProxy
  , authStart
  , sashaContext
  ) where

import           SashaPrelude

import           API.Types
  ( AuthenticatedUser (AuthenticatedUser, auUserId)
  , SessionId (SessionId)
  )
import           Control.Concurrent (modifyMVar, modifyMVar_)
import           Control.Exception (throwIO, try)
import           Control.Monad.Reader (ask)
import           Crypto.Hash (SHA256 (SHA256), hashWith)
import           Crypto.Random (getRandomBytes)
import           Data.Aeson (eitherDecode)
import           Data.ByteArray.Encoding
  ( Base (Base64URLUnpadded)
  , convertToBase
  )
import           Data.ByteString (ByteString)
import           Data.ByteString.Lazy (fromStrict)
import           Data.List (lookup)
import qualified Data.Map.Strict (delete, filter, insert, lookup)
import           Data.Pool (withResource)
import qualified Data.Set (fromList, member)
import           Data.String (fromString)
import           Data.Text.Encoding (decodeUtf8', encodeUtf8)
import           Data.Time.Clock (diffUTCTime, getCurrentTime)
import           Data.Type.Equality (type (~))
import           Database.PostgreSQL.Simple
  ( Only (Only)
  , SqlError (sqlState)
  , execute
  , query
  , query_
  , withTransaction
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
  ( AllowedAction
  , Permission (DemotedPermission, demotePermission)
  , RoleId
  )
import           Model.Core (Agent)
import           Model.GID (GID (GID))
import           Model.Jwt
  ( Credentials (Credentials)
  , Jwt (Jwt, unJwt)
  , SashaClaims (SashaClaims)
  , getJwtData
  , hashToken
  , makeJwt
  , tryAddHashAndJwt
  )
import           Model.Mid (Mid, unMid)
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
  , HasContextEntry (getContextEntry)
  , HasServer (ServerT, hoistServerWithContext, route)
  , Header
  , Headers
  , NoContent (NoContent)
  , Proxy (Proxy)
  , ServerError (errBody)
  , addHeader
  , err400
  , err401
  , err403
  , err409
  , err500
  , noHeader
  , throwError
  , type (:>)
  )
import           Servant.Server.Experimental.Auth
  ( AuthHandler (unAuthHandler)
  , mkAuthHandler
  )
import           Servant.Server.Internal.Delayed (addAuthCheck)
import           Servant.Server.Internal.DelayedIO
  ( DelayedIO
  , delayedFailFatal
  , withRequest
  )
import           Servant.Server.Internal.Handler (runHandler)
import           Server.App
  ( AppCtx (acDbPool, acGameLog, acHttpManager, acOidcConfig, acOidcStates, acSessions)
  , AppM
  , OidcConfig (OidcConfig)
  , SessionPhase (SessionPhase)
  , SessionState (AwaitingSocket)
  )
import           Server.Log (LogEntry (PlayerLogin), writeLog)
import           Server.Validator
  ( PlayerNameUNV
  , PlayerNameVAL (PlayerNameVAL)
  , Validate (validate)
  )

type SashaContext :: Type
type SashaContext = Context '[AuthHandler Request AuthenticatedUser]

authProxy :: Proxy '[AuthHandler Request AuthenticatedUser]
authProxy = Proxy

sashaContext :: AppCtx -> SashaContext
sashaContext ctx = mkAuthHandler (authHandler ctx) :. EmptyContext

type CanDo :: AllowedAction -> Type
data CanDo action

instance forall a xs context.
  ( HasServer xs context
  , HasContextEntry context (AuthHandler Request AuthenticatedUser)
  , Permission a
  , DemotedPermission a ~ AllowedAction
  ) =>
  HasServer (CanDo a :> xs) context
  where
  type ServerT (CanDo a :> xs) m = AuthenticatedUser -> ServerT xs m
  hoistServerWithContext _ pc nt server =
    hoistServerWithContext (Proxy @xs) pc nt . server
  route _ context subserver =
    route (Proxy @xs) context (subserver `addAuthCheck` withRequest authCheck)
    where
      action = demotePermission (Proxy @a)
      authCheck :: Request -> DelayedIO AuthenticatedUser
      authCheck req = do
        result <- liftIO (runHandler (unAuthHandler (getContextEntry context) req))
        case result of
          Left err -> delayedFailFatal err
          Right user
            | canDo action user -> pure user
            | otherwise -> delayedFailFatal err403
                { errBody = fromString
                    ("User " <> show (auUserId user) <> " may not perform " <> show action)
                }

canDo :: AllowedAction -> AuthenticatedUser -> Bool
canDo action (AuthenticatedUser _ _ permissions) =
  case permissions of
    PermissionsDisabled -> False
    Permissions granted -> Data.Set.member action granted

authHandler :: AppCtx -> Request -> Handler AuthenticatedUser
authHandler ctx req =
  case lookup "BEARER" (requestHeaders req) of
    Just rawToken -> processToken rawToken
    Nothing -> case lookup "Sec-WebSocket-Protocol" (requestHeaders req) of
      Nothing       -> throwError err401
      Just rawToken -> processToken rawToken
  where
    processToken :: ByteString -> Handler AuthenticatedUser
    processToken rawToken = case decodeUtf8' rawToken of
      Left _ -> throwError err401
      Right t -> do
        rows :: [(Mid AuthenticatedUser, RoleId, ByteString)] <-
          liftIO . withResource (acDbPool ctx) $ \conn ->
            query conn userQuery (Only rawToken)
        case rows of
          [(userId, roleId, hash)] -> do
            SashaClaims _ expiration <- case getJwtData (Jwt rawToken) hash of
              Left _       -> throwError err401
              Right claims -> pure claims
            now <- liftIO getCurrentTime
            when (expiration < now) (throwError err401)
            permissions <- loadPermissions ctx roleId
            pure (AuthenticatedUser (SessionId t) userId permissions)
          _ -> throwError err401
    userQuery =
      [sql|
        SELECT users.user_id, users.role_id, tokens.hash FROM tokens
          JOIN users ON users.user_id = tokens.user_id
          WHERE tokens.token = ?
            AND users.status = 'active'
      |]

loadPermissions :: AppCtx -> RoleId -> Handler UserPermissions
loadPermissions ctx roleId = do
  rows :: [Only (Maybe (PGArray AllowedAction))] <-
    liftIO . withResource (acDbPool ctx) $ \conn ->
      query conn permissionsQuery (Only roleId)
  pure (Permissions (Data.Set.fromList
    [ action | Only (Just actions) <- rows, action <- fromPGArray actions ]))
  where
    permissionsQuery =
      [sql| SELECT role_permissions FROM roles WHERE role_id = ? |]

authAvailable :: PlayerNameUNV -> AppM NoContent
authAvailable unv = do
  ctx <- ask
  PlayerNameVAL name <- case validate unv :: Either Text PlayerNameVAL of
    Left reason -> throwError err400 { errBody = fromStrict (encodeUtf8 reason) }
    Right val   -> pure val
  rows :: [Only Int] <-
    liftIO . withResource (acDbPool ctx) $ \conn ->
      query conn [sql| SELECT 1 FROM credentials WHERE player_name = ? |] (Only name)
  case rows of
    [] -> pure NoContent
    _  -> throwError err409 { errBody = fromStrict (encodeUtf8 (name <> " is taken")) }

authStart :: Maybe PlayerNameUNV -> AppM (Headers '[Header "Location" Text] NoContent)
authStart requestedName = do
  ctx <- ask
  let OidcConfig (OidcBaseUrl base) (ClientId clientId) _ (RedirectUri redirectUri) = acOidcConfig ctx
  chosenName <- case requestedName of
    Nothing  -> pure Nothing
    Just unv -> case validate unv :: Either Text PlayerNameVAL of
      Left reason -> throwError err400 { errBody = fromStrict (encodeUtf8 reason) }
      Right val   -> pure (Just val)
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
        pure (Data.Map.Strict.insert (OidcState stateText) (now, CodeVerifier verifierText, chosenName)
                (Data.Map.Strict.filter (\(created, _, _) -> diffUTCTime now created <= 600) states))
      pure (addHeader locationText NoContent)
    _ -> throwError err500

authCallback :: AuthCode -> OidcState -> AppM (Headers '[Header "Set-Cookie" Text, Header "Location" Text] NoContent)
authCallback (AuthCode code) state = do
  ctx <- ask
  let OidcConfig (OidcBaseUrl base) (ClientId clientId) (ClientSecret secret) (RedirectUri redirectUri) = acOidcConfig ctx
  now <- liftIO getCurrentTime
  entry <- liftIO . modifyMVar (acOidcStates ctx) $ \states ->
    pure (Data.Map.Strict.delete state states, Data.Map.Strict.lookup state states)
  (CodeVerifier verifier, chosenName) <- case entry of
    Just (created, v, n) | diffUTCTime now created <= 600 -> pure (v, n)
    _                                                     -> throwError err401
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
  TokenResponse access@(AccessToken accessToken) <- case eitherDecode (responseBody tokenResp) of
    Left _  -> throwError err401
    Right r -> pure r
  infoReq <- liftIO (parseRequest (unpack base <> "/application/o/userinfo/"))
  infoResp <- liftIO $ httpLbs
    (setRequestCheckStatus (applyBearerAuth (encodeUtf8 accessToken) infoReq))
    (acHttpManager ctx)
  UserInfo authentikUserId _ <- case eitherDecode (responseBody infoResp) of
    Left _  -> throwError err401
    Right r -> pure r
  rows :: [(Mid AuthenticatedUser, Text)] <-
    liftIO . withResource (acDbPool ctx) $ \conn ->
      query conn credentialsQuery (Only authentikUserId)
  existing <- case rows of
    [(uid, name)] -> pure (Just (uid, PlayerNameVAL name, GID (unMid uid)))
    []            -> pure Nothing
    _             -> throwError err500
  outcome <- case (existing, chosenName) of
    (Just account, _)      -> pure (Right account)
    (Nothing, Nothing)     -> pure (Left "/#new")
    (Nothing, Just (PlayerNameVAL name)) -> do
      created :: Either SqlError (Maybe (Mid AuthenticatedUser, PlayerNameVAL, GID Agent)) <-
        liftIO . try . withResource (acDbPool ctx) $ \conn ->
          withTransaction conn $ do
            userRows :: [Only (Mid AuthenticatedUser)] <- query_ conn insertUser
            case userRows of
              [Only uid] -> do
                _ <- execute conn insertCredentials (uid, name, authentikUserId)
                pure (Just (uid, PlayerNameVAL name, GID (unMid uid)))
              _ -> pure Nothing
      case created of
        Left err
          | sqlState err == "23505" -> pure (Left ("/#taken=" <> name))
          | otherwise               -> liftIO (throwIO err)
        Right Nothing        -> throwError err500
        Right (Just account) -> pure (Right account)
  case outcome of
    Left location -> pure (noHeader (addHeader location NoContent))
    Right (userId, playerName, agentGid) -> do
      hash <- liftIO (hashToken access)
      minted <- liftIO (makeJwt (Credentials authentikUserId) hash)
      jwt <- case minted of
        Left err -> throwError err500 { errBody = fromString ("token mint failed: " <> show err) }
        Right j  -> pure j
      tokenText <- case decodeUtf8' (unJwt jwt) of
        Left _  -> throwError err500
        Right t -> pure t
      tryAddHashAndJwt userId hash jwt
      let sessionId = SessionId tokenText
          hasActiveSession (SessionPhase _ _ AwaitingSocket) = False
          hasActiveSession (SessionPhase n _ _)              = n == playerName
          keepEntry (SessionPhase n _ AwaitingSocket) = n /= playerName
          keepEntry _                                 = True
      alreadyActive <- liftIO . modifyMVar (acSessions ctx) $ \sessions ->
        if any hasActiveSession sessions
          then pure (sessions, True)
          else pure (Data.Map.Strict.insert sessionId (SessionPhase playerName agentGid AwaitingSocket)
                       (Data.Map.Strict.filter keepEntry sessions), False)
      when alreadyActive (throwError err409)
      liftIO $ writeLog (acGameLog ctx) (PlayerLogin playerName)
      pure (addHeader ("sashamud_token=" <> tokenText <> "; Path=/; Secure; SameSite=Strict")
             (addHeader "/" NoContent))
  where
    credentialsQuery =
      [sql|
        SELECT credentials.user_id, credentials.player_name FROM credentials
          JOIN users ON users.user_id = credentials.user_id
          WHERE credentials.authentik_user_id = ?
            AND users.status = 'active'
      |]
    insertUser =
      [sql|
        INSERT INTO users (status, role_id, activated_on)
          SELECT 'active', role_id, now() FROM roles WHERE name = 'wizard'
          RETURNING user_id
      |]
    insertCredentials =
      [sql| INSERT INTO credentials (user_id, player_name, authentik_user_id) VALUES (?, ?, ?) |]
