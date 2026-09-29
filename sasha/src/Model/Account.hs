module Model.Account
  ( AccessToken (AccessToken)
  , AccountStatus (Active, Inactive)
  , AuthCode (AuthCode)
  , AuthentikUserId (AuthentikUserId)
  , ClientId (ClientId)
  , ClientSecret (ClientSecret)
  , CodeVerifier (CodeVerifier)
  , OidcBaseUrl (OidcBaseUrl)
  , OidcState (OidcState)
  , RedirectUri (RedirectUri)
  , TokenResponse (TokenResponse)
  , UserInfo (UserInfo)
  , UserPermissions (PermissionsDisabled, Permissions)
  , unAccessToken
  , unAuthCode
  , unAuthentikUserId
  , unClientId
  , unClientSecret
  , unCodeVerifier
  , unOidcBaseUrl
  , unOidcState
  , unRedirectUri
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, ToJSON)
import           Data.ByteString.Builder (byteString)
import qualified Data.ByteString.Char8 (unpack)
import           Data.Set (Set)
import           Data.UUID (UUID)
import           Database.PostgreSQL.Simple
  ( ResultError (ConversionFailed, errHaskellType, errMessage, errSQLField, errSQLTableOid, errSQLType)
  )
import           Database.PostgreSQL.Simple.FromField
  ( FromField (fromField)
  , conversionError
  , typename
  )
import           Database.PostgreSQL.Simple.ToField
  ( Action (Plain)
  , ToField (toField)
  , inQuotes
  )
import           Model.Authorization (AllowedAction)
import           Servant (FromHttpApiData, ToHttpApiData)
import           Server.Validator (PlayerNameUNV)
#ifdef TESTING
import           Test.QuickCheck (Arbitrary)
import           Test.QuickCheck.Arbitrary.Generic
  ( GenericArbitrary (GenericArbitrary)
  )
import           Test.QuickCheck.Instances.Containers ()
import           Test.QuickCheck.Instances.Text ()
import           Test.QuickCheck.Instances.UUID ()
#endif

data AccountStatus
  = Active
  | Inactive
  deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

instance FromField AccountStatus where
  fromField field mbs = do
    typeName <- Data.ByteString.Char8.unpack <$> typename field
    if typeName /= "account_status"
      then conversionError ConversionFailed
        { errSQLType = typeName
        , errSQLTableOid = Nothing
        , errSQLField = ""
        , errHaskellType = "AccountStatus"
        , errMessage = "looking for an 'account_status' value but got a '" <> typeName <> "' value instead"
        }
      else case mbs of
        Just "active"   -> pure Active
        Just "inactive" -> pure Inactive
        _ -> conversionError ConversionFailed
          { errSQLType = typeName
          , errSQLTableOid = Nothing
          , errSQLField = ""
          , errHaskellType = "AccountStatus"
          , errMessage = "A value other than of type 'AccountStatus' was somehow used. The type 'account_status' must have been changed. The value in the table is '" <> show mbs <> "'."
          }

instance ToField AccountStatus where
  toField Active   = Plain ((inQuotes . byteString) "active")
  toField Inactive = Plain ((inQuotes . byteString) "inactive")

newtype AuthentikUserId = AuthentikUserId { unAuthentikUserId :: UUID }
  deriving stock (Generic)
  deriving newtype (Eq, FromField, FromJSON, NFData, Ord, Show, ToField, ToJSON)

newtype ClientSecret = ClientSecret { unClientSecret :: Text }
  deriving newtype (Eq)

instance Show ClientSecret where
  show _ = "ClientSecret <hidden>"

data UserPermissions = PermissionsDisabled
                     | Permissions (Set AllowedAction)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

newtype OidcBaseUrl = OidcBaseUrl { unOidcBaseUrl :: Text }
  deriving newtype (Eq, Show)

newtype ClientId = ClientId { unClientId :: Text }
  deriving newtype (Eq, Show)

newtype RedirectUri = RedirectUri { unRedirectUri :: Text }
  deriving newtype (Eq, Show)

newtype OidcState = OidcState { unOidcState :: Text }
  deriving newtype (Eq, FromHttpApiData, Ord, Show, ToHttpApiData)

newtype AuthCode = AuthCode { unAuthCode :: Text }
  deriving newtype (Eq, FromHttpApiData, Ord, Show, ToHttpApiData)

newtype CodeVerifier = CodeVerifier { unCodeVerifier :: Text }
  deriving newtype (Eq, FromHttpApiData, Show, ToHttpApiData)

newtype AccessToken = AccessToken { unAccessToken :: Text }
  deriving newtype (Eq, FromJSON, Show, ToJSON)

newtype TokenResponse = TokenResponse { access_token :: AccessToken }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (FromJSON, ToJSON)

data UserInfo = UserInfo
  { sub                :: AuthentikUserId
  , preferred_username :: PlayerNameUNV
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (FromJSON, ToJSON)

#ifdef TESTING
deriving via (GenericArbitrary AccountStatus) instance Arbitrary AccountStatus
deriving newtype instance Arbitrary AccessToken
deriving newtype instance Arbitrary AuthentikUserId
deriving via (GenericArbitrary UserPermissions) instance Arbitrary UserPermissions
#endif
