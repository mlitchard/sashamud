{-# LANGUAGE QuasiQuotes #-}

module Model.Jwt
  ( Credentials (Credentials)
  , Jwt (Jwt, unJwt)
  , SashaClaims (SashaClaims)
  , getJwtData
  , hashToken
  , makeJwt
  , makeJwtForTesting
  , tryAddHashAndJwt
  ) where

import           SashaPrelude

import           API.Types (AuthenticatedUser)
import           Control.Exception (try)
import           Control.Monad.Reader (ask)
import           Crypto.KDF.BCrypt (hashPassword)
import           Crypto.Random.Types (MonadRandom)
import           Data.Aeson (FromJSON, ToJSON, decode, encode)
import           Data.ByteString (ByteString)
import           Data.ByteString.Lazy (fromStrict, toStrict)
import           Data.Pool (withResource)
import           Data.Text.Encoding (encodeUtf8)
import           Data.Time.Clock
  ( NominalDiffTime
  , UTCTime
  , addUTCTime
  , getCurrentTime
  , secondsToNominalDiffTime
  )
import           Database.PostgreSQL.Simple (SqlError, execute)
import           Database.PostgreSQL.Simple.FromField (FromField)
import           Database.PostgreSQL.Simple.SqlQQ (sql)
import           Database.PostgreSQL.Simple.ToField (ToField)
import           Jose.Jwa (JwsAlg (HS256))
import           Jose.Jws (hmacDecode, hmacEncode)
import           Jose.Jwt (Jwt (Jwt, unJwt), JwtError (BadClaims))
import           Model.Account (AccessToken (AccessToken), AuthentikUserId)
import           Model.Mid (Mid)
import           Servant
  ( FromHttpApiData (parseQueryParam, parseUrlPiece)
  , ToHttpApiData (toHeader, toQueryParam, toUrlPiece)
  , err500
  , throwError
  )
import           Server.App (AppCtx (acDbPool), AppM)
#ifdef TESTING
import           Test.QuickCheck (Arbitrary)
import           Test.QuickCheck.Arbitrary.Generic
  ( GenericArbitrary (GenericArbitrary)
  )
import           Test.QuickCheck.Instances.Time ()
#endif

type Hash :: Type
type Hash = ByteString

data Credentials = Credentials
  { subject     :: AuthentikUserId
  , accessToken :: AccessToken
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (FromJSON, ToJSON)

data SashaClaims = SashaClaims
  { credentials    :: Credentials
  , expirationDate :: UTCTime
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (FromJSON, ToJSON)

hashToken :: MonadRandom m => AccessToken -> m Hash
hashToken (AccessToken t) = hashPassword 9 (encodeUtf8 t)

makeJwt :: Credentials -> Hash -> IO (Either JwtError Jwt)
makeJwt = makeJwtForTesting (secondsToNominalDiffTime 86400)

makeJwtForTesting :: NominalDiffTime -> Credentials -> Hash -> IO (Either JwtError Jwt)
makeJwtForTesting lifetime creds hash = do
  currentTime <- getCurrentTime
  let expiration = addUTCTime lifetime currentTime
      claims = SashaClaims creds expiration
      encoded = toStrict (encode claims)
  pure (hmacEncode HS256 hash encoded)

getJwtData :: Jwt -> Hash -> Either JwtError SashaClaims
getJwtData jwt hash = case snd <$> hmacDecode hash (unJwt jwt) of
  Left e     -> Left e
  Right json -> case decode (fromStrict json) of
    Just claims -> Right claims
    Nothing     -> Left BadClaims

tryAddHashAndJwt :: Mid AuthenticatedUser -> Hash -> Jwt -> AppM ()
tryAddHashAndJwt userId hash jwt = do
  ctx <- ask
  res <- liftIO . try . withResource (acDbPool ctx) $ \conn ->
    execute conn addToken (userId, jwt, hash, userId)
  case res of
    Left (_ :: SqlError) -> throwError err500
    Right _              -> pure ()
  where
    addToken =
      [sql|
        DELETE FROM tokens WHERE user_id = ?;
        INSERT INTO tokens (token, hash, user_id, created) VALUES (?, ?, ?, now());
      |]

instance ToHttpApiData Jwt where
  toUrlPiece _ = "/"
  toQueryParam _ = ""
  toHeader (Jwt bst) = bst

instance FromHttpApiData Jwt where
  parseUrlPiece t = Right (Jwt (encodeUtf8 t))
  parseQueryParam t = Right (Jwt (encodeUtf8 t))

deriving newtype instance ToField Jwt
deriving newtype instance FromField Jwt

#ifdef TESTING
deriving via (GenericArbitrary Credentials) instance Arbitrary Credentials
deriving via (GenericArbitrary SashaClaims) instance Arbitrary SashaClaims
#endif
