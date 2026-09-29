module Model.Authorization
  ( AllowedAction (Dsl)
  , Permission (DemotedPermission, ShowPermission, demotePermission)
  , RoleId (RoleId)
  , RoleName (Admin, Player, Wizard)
  , unRoleId
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, ToJSON)
import           Data.ByteString.Builder (byteString)
import qualified Data.ByteString.Char8 (unpack)
import           Data.Proxy (Proxy)
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
import           GHC.TypeLits (Symbol)
#ifdef TESTING
import           Test.QuickCheck (Arbitrary)
import           Test.QuickCheck.Arbitrary.Generic
  ( GenericArbitrary (GenericArbitrary)
  )
#endif

data AllowedAction
  = Dsl
  deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

instance FromField AllowedAction where
  fromField field mbs = do
    typeName <- Data.ByteString.Char8.unpack <$> typename field
    if typeName /= "allowed_action"
      then conversionError ConversionFailed
        { errSQLType = typeName
        , errSQLTableOid = Nothing
        , errSQLField = ""
        , errHaskellType = "AllowedAction"
        , errMessage = "looking for an 'allowed_action' value but got a '" <> typeName <> "' value instead"
        }
      else case mbs of
        Just "dsl" -> pure Dsl
        _ -> conversionError ConversionFailed
          { errSQLType = typeName
          , errSQLTableOid = Nothing
          , errSQLField = ""
          , errHaskellType = "AllowedAction"
          , errMessage = "A value other than of type 'AllowedAction' was somehow used. The type 'allowed_action' must have been changed. The value in the table is '" <> show mbs <> "'."
          }

instance ToField AllowedAction where
  toField Dsl = Plain ((inQuotes . byteString) "dsl")

newtype RoleId = RoleId { unRoleId :: Int }
  deriving stock (Generic)
  deriving newtype (Eq, FromField, NFData, Ord, Show, ToField)

data RoleName
  = Player
  | Wizard
  | Admin
  deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

instance FromField RoleName where
  fromField field mbs = do
    typeName <- Data.ByteString.Char8.unpack <$> typename field
    if typeName /= "role_name"
      then conversionError ConversionFailed
        { errSQLType = typeName
        , errSQLTableOid = Nothing
        , errSQLField = ""
        , errHaskellType = "RoleName"
        , errMessage = "looking for a 'role_name' value but got a '" <> typeName <> "' value instead"
        }
      else case mbs of
        Just "player" -> pure Player
        Just "wizard" -> pure Wizard
        Just "admin"  -> pure Admin
        _ -> conversionError ConversionFailed
          { errSQLType = typeName
          , errSQLTableOid = Nothing
          , errSQLField = ""
          , errHaskellType = "RoleName"
          , errMessage = "A value other than of type 'RoleName' was somehow used. The type 'role_name' must have been changed. The value in the table is '" <> show mbs <> "'."
          }

instance ToField RoleName where
  toField Player = Plain ((inQuotes . byteString) "player")
  toField Wizard = Plain ((inQuotes . byteString) "wizard")
  toField Admin  = Plain ((inQuotes . byteString) "admin")

type Permission :: k -> Constraint
class Permission a where
  type DemotedPermission a :: Type
  type ShowPermission a :: Symbol
  demotePermission :: Proxy a -> DemotedPermission a

instance Permission 'Dsl where
  type DemotedPermission 'Dsl = AllowedAction
  type ShowPermission 'Dsl = "Dsl"
  demotePermission _ = Dsl

#ifdef TESTING
deriving via (GenericArbitrary AllowedAction) instance Arbitrary AllowedAction
deriving via (GenericArbitrary RoleName) instance Arbitrary RoleName
#endif
