module Model.Authorization
  ( Resource (Dsl)
  , ResourceAction (Create)
  , RoleId (RoleId)
  , RoleStatus (RoleActive, RoleInactive)
  , unRoleId
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData)
import           Data.Aeson
  ( FromJSON
  , FromJSONKey (fromJSONKey)
  , FromJSONKeyFunction (FromJSONKeyTextParser)
  , ToJSON
  , ToJSONKey (toJSONKey)
  )
import           Data.Aeson.Types (toJSONKeyText)
import           Data.ByteString.Builder (byteString)
import qualified Data.ByteString.Char8 (unpack)
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
#ifdef TESTING
import           Test.QuickCheck (Arbitrary)
import           Test.QuickCheck.Arbitrary.Generic
  ( GenericArbitrary (GenericArbitrary)
  )
#endif

data Resource
  = Dsl
  deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

instance ToJSONKey Resource where
  toJSONKey = toJSONKeyText (pack . show)

instance FromJSONKey Resource where
  fromJSONKey = FromJSONKeyTextParser $ \case
    "Dsl" -> pure Dsl
    other -> fail ("unknown Resource " <> unpack other)

instance FromField Resource where
  fromField field mbs = do
    typeName <- Data.ByteString.Char8.unpack <$> typename field
    if typeName /= "resource"
      then conversionError ConversionFailed
        { errSQLType = typeName
        , errSQLTableOid = Nothing
        , errSQLField = ""
        , errHaskellType = "Resource"
        , errMessage = "looking for a 'resource' value but got a '" <> typeName <> "' value instead"
        }
      else case mbs of
        Just "dsl" -> pure Dsl
        _ -> conversionError ConversionFailed
          { errSQLType = typeName
          , errSQLTableOid = Nothing
          , errSQLField = ""
          , errHaskellType = "Resource"
          , errMessage = "A value other than of type 'Resource' was somehow used. The type 'resource' must have been changed. The value in the table is '" <> show mbs <> "'."
          }

instance ToField Resource where
  toField Dsl = Plain ((inQuotes . byteString) "dsl")

data ResourceAction
  = Create
  deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

instance FromField ResourceAction where
  fromField field mbs = do
    typeName <- Data.ByteString.Char8.unpack <$> typename field
    if typeName /= "action"
      then conversionError ConversionFailed
        { errSQLType = typeName
        , errSQLTableOid = Nothing
        , errSQLField = ""
        , errHaskellType = "ResourceAction"
        , errMessage = "looking for an 'action' value but got a '" <> typeName <> "' value instead"
        }
      else case mbs of
        Just "create" -> pure Create
        _ -> conversionError ConversionFailed
          { errSQLType = typeName
          , errSQLTableOid = Nothing
          , errSQLField = ""
          , errHaskellType = "ResourceAction"
          , errMessage = "A value other than of type 'ResourceAction' was somehow used. The type 'action' must have been changed. The value in the table is '" <> show mbs <> "'."
          }

instance ToField ResourceAction where
  toField Create = Plain ((inQuotes . byteString) "create")

data RoleStatus
  = RoleActive
  | RoleInactive
  deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

instance FromField RoleStatus where
  fromField field mbs = do
    typeName <- Data.ByteString.Char8.unpack <$> typename field
    if typeName /= "role_status"
      then conversionError ConversionFailed
        { errSQLType = typeName
        , errSQLTableOid = Nothing
        , errSQLField = ""
        , errHaskellType = "RoleStatus"
        , errMessage = "looking for a 'role_status' value but got a '" <> typeName <> "' value instead"
        }
      else case mbs of
        Just "role_active"   -> pure RoleActive
        Just "role_inactive" -> pure RoleInactive
        _ -> conversionError ConversionFailed
          { errSQLType = typeName
          , errSQLTableOid = Nothing
          , errSQLField = ""
          , errHaskellType = "RoleStatus"
          , errMessage = "A value other than of type 'RoleStatus' was somehow used. The type 'role_status' must have been changed. The value in the table is '" <> show mbs <> "'."
          }

instance ToField RoleStatus where
  toField RoleActive   = Plain ((inQuotes . byteString) "role_active")
  toField RoleInactive = Plain ((inQuotes . byteString) "role_inactive")

newtype RoleId = RoleId { unRoleId :: Int }
  deriving stock (Generic)
  deriving newtype (Eq, FromField, NFData, Ord, Show, ToField)

#ifdef TESTING
deriving via (GenericArbitrary Resource) instance Arbitrary Resource
deriving via (GenericArbitrary ResourceAction) instance Arbitrary ResourceAction
deriving via (GenericArbitrary RoleStatus) instance Arbitrary RoleStatus
#endif
