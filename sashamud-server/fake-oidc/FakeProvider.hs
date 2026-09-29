{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE QuasiQuotes   #-}
{-# LANGUAGE TypeOperators #-}

module FakeProvider
  ( FakeState
  , fakeApp
  , fakeAuthentikUserId
  , finalLocationThroughFake
  , loginThroughFake
  , newFakeState
  , seedAccount
  ) where

import           SashaPrelude

import           API.Types (SessionId (SessionId))
import           Control.Concurrent (MVar, modifyMVar_, newMVar, readMVar)
import           Crypto.Hash (SHA256 (SHA256), hashWith)
import           Data.ByteArray.Encoding
  ( Base (Base64URLUnpadded)
  , convertToBase
  )
import           Data.ByteString (ByteString)
import qualified Data.ByteString (unpack)
import           Data.List (lookup)
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict (insert, lookup)
import           Data.Pool (Pool, withResource)
import           Data.Text (breakOn, stripPrefix)
import           Data.Text.Encoding (decodeUtf8', encodeUtf8)
import           Data.UUID.V5 (generateNamed, namespaceOID)
import           Database.PostgreSQL.Simple (Connection, execute)
import           Database.PostgreSQL.Simple.SqlQQ (sql)
import           Model.Account
  ( AccessToken (AccessToken)
  , AuthCode (AuthCode)
  , AuthentikUserId (AuthentikUserId)
  , CodeVerifier (CodeVerifier)
  , OidcState
  , TokenResponse (TokenResponse)
  , UserInfo (UserInfo)
  , unAuthCode
  , unOidcState
  )
import           Model.Authorization (RoleName)
import           Network.HTTP.Client
  ( Manager
  , Request (redirectCount)
  , Response (responseHeaders)
  , httpLbs
  , parseRequest
  )
import           Network.HTTP.Types (renderQuery)
import           Network.HTTP.Types.Method (StdMethod (GET))
import           Servant
  ( Application
  , Get
  , Handler
  , Header
  , Header'
  , Headers
  , JSON
  , NoContent (NoContent)
  , Post
  , Proxy (Proxy)
  , QueryParam
  , QueryParam'
  , ReqBody
  , Verb
  , addHeader
  , err401
  , err500
  , serve
  , throwError
  , type (:<|>) ((:<|>))
  , type (:>)
  )
import           Servant.API.ContentTypes (FormUrlEncoded)
import           Servant.API.Modifiers (Required, Strict)
import           Server.Validator
  ( PlayerNameUNV (PlayerNameUNV)
  , PlayerNameVAL (PlayerNameVAL)
  )
import           Web.FormUrlEncoded (FromForm)

data TokenRequest = TokenRequest
  { code          :: AuthCode
  , code_verifier :: CodeVerifier
  }
  deriving stock (Generic, Show)

instance FromForm TokenRequest

type FakeAPI =
       "application" :> "o" :> "authorize"
         :> QueryParam' '[Required, Strict] "redirect_uri" Text
         :> QueryParam' '[Required, Strict] "state" OidcState
         :> QueryParam' '[Required, Strict] "code_challenge" Text
         :> QueryParam "fake_user" Text
         :> Verb 'GET 302 '[JSON] (Headers '[Header "Location" Text] NoContent)
  :<|> "application" :> "o" :> "token"
         :> ReqBody '[FormUrlEncoded] TokenRequest
         :> Post '[JSON] TokenResponse
  :<|> "application" :> "o" :> "userinfo"
         :> Header' '[Required, Strict] "Authorization" Text
         :> Get '[JSON] UserInfo

newtype FakeState = FakeState (MVar (Map AuthCode Text))

newFakeState :: IO FakeState
newFakeState = FakeState <$> newMVar mempty

fakeApp :: FakeState -> Application
fakeApp st = serve (Proxy @FakeAPI) (authorize st :<|> token st :<|> userinfo)

authorize :: FakeState -> Text -> OidcState -> Text -> Maybe Text
          -> Handler (Headers '[Header "Location" Text] NoContent)
authorize (FakeState challenges) redirectUri state challenge fakeUser = do
  let user = fromMaybe "wizard" fakeUser
  liftIO $ modifyMVar_ challenges (pure . Data.Map.Strict.insert (AuthCode user) challenge)
  let location = encodeUtf8 redirectUri <> renderQuery True
        [ ("code", Just (encodeUtf8 user))
        , ("state", Just (encodeUtf8 (unOidcState state)))
        ]
  case decodeUtf8' location of
    Left _  -> throwError err500
    Right l -> pure (addHeader l NoContent)

token :: FakeState -> TokenRequest -> Handler TokenResponse
token (FakeState challenges) (TokenRequest authCode (CodeVerifier verifier)) = do
  stored <- liftIO (Data.Map.Strict.lookup authCode <$> readMVar challenges)
  let expected = convertToBase Base64URLUnpadded (hashWith SHA256 (encodeUtf8 verifier)) :: ByteString
  case stored of
    Just challenge | encodeUtf8 challenge == expected ->
      pure (TokenResponse (AccessToken (unAuthCode authCode)))
    _ -> throwError err401

userinfo :: Text -> Handler UserInfo
userinfo authorization =
  case stripPrefix "Bearer " authorization of
    Nothing   -> throwError err401
    Just user -> pure (UserInfo (fakeAuthentikUserId user) (PlayerNameUNV user))

fakeAuthentikUserId :: Text -> AuthentikUserId
fakeAuthentikUserId user =
  AuthentikUserId (generateNamed namespaceOID (Data.ByteString.unpack (encodeUtf8 user)))

finalLocationThroughFake :: Manager -> Int -> Maybe Text -> Text -> IO Text
finalLocationThroughFake manager port requestedName user = do
  let startPath = case requestedName of
        Nothing   -> "/api/auth/start"
        Just name -> "/api/auth/start?name=" <> unpack name
  startReq <- parseRequest ("http://127.0.0.1:" <> show port <> startPath)
  authorizeUrl <- locationOf =<< httpLbs startReq { redirectCount = 0 } manager
  authorizeReq <- parseRequest (unpack authorizeUrl <> "&fake_user=" <> unpack user)
  callbackUrl <- locationOf =<< httpLbs authorizeReq { redirectCount = 0 } manager
  let (_, callbackQuery) = breakOn "?" callbackUrl
  callbackReq <- parseRequest ("http://127.0.0.1:" <> show port <> "/api/auth/callback" <> unpack callbackQuery)
  locationOf =<< httpLbs callbackReq { redirectCount = 0 } manager
  where
    locationOf resp =
      case lookup "Location" (responseHeaders resp) of
        Nothing -> fail "no Location header"
        Just raw -> case decodeUtf8' raw of
          Left _  -> fail "Location header is not UTF-8"
          Right l -> pure l

loginThroughFake :: Manager -> Int -> Text -> IO SessionId
loginThroughFake manager port user = do
  final <- finalLocationThroughFake manager port Nothing user
  case stripPrefix "/#token=" final of
    Just t  -> pure (SessionId t)
    Nothing -> fail ("unexpected final location " <> unpack final)

seedAccount :: Pool Connection -> RoleName -> PlayerNameVAL -> IO ()
seedAccount pool role (PlayerNameVAL name) = withResource pool $ \conn -> do
  _ <- execute conn seedQuery (role, name, name, fakeAuthentikUserId name)
  pure ()
  where
    seedQuery =
      [sql|
        WITH new_user AS (
          INSERT INTO users (status, role_id, activated_on)
            SELECT 'active', role_id, now() FROM roles
              WHERE name = ?
                AND NOT EXISTS (SELECT 1 FROM credentials WHERE player_name = ?)
            RETURNING user_id)
        INSERT INTO credentials (user_id, player_name, authentik_user_id)
          SELECT user_id, ?, ? FROM new_user
      |]
