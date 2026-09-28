module Model.Account
  ( AccountStatus (Active, Inactive)
  , ClientSecret (ClientSecret)
  , Subject (Subject)
  , UserPermissions (PermissionsDisabled, Permissions)
  , unClientSecret
  , unSubject
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, ToJSON)
import           Data.ByteString.Builder (byteString)
import qualified Data.ByteString.Char8 (unpack)
import           Data.Map.Strict (Map)
import           Data.Set (Set)
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
import           Model.Authorization (Resource, ResourceAction)
#ifdef TESTING
import           Test.QuickCheck (Arbitrary)
import           Test.QuickCheck.Arbitrary.Generic
  ( GenericArbitrary (GenericArbitrary)
  )
import           Test.QuickCheck.Instances.Containers ()
import           Test.QuickCheck.Instances.Text ()
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

newtype Subject = Subject { unSubject :: Text }
  deriving stock (Generic)
  deriving newtype (Eq, FromField, FromJSON, NFData, Ord, Show, ToField, ToJSON)

newtype ClientSecret = ClientSecret { unClientSecret :: Text }
  deriving newtype (Eq)

instance Show ClientSecret where
  show _ = "ClientSecret <hidden>"

data UserPermissions = PermissionsDisabled
                     | Permissions (Map Resource (Set ResourceAction))
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

#ifdef TESTING
deriving via (GenericArbitrary AccountStatus) instance Arbitrary AccountStatus
deriving newtype instance Arbitrary Subject
deriving via (GenericArbitrary UserPermissions) instance Arbitrary UserPermissions
#endif
