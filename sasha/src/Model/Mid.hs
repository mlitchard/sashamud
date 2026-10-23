module Model.Mid
  ( Mid (Mid)
  , unMid
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, FromJSONKey, ToJSON, ToJSONKey)
import           Data.Aeson.TypeScript (derivingTypeScriptDefinition)
import           Database.PostgreSQL.Simple.FromField (FromField)
import           Database.PostgreSQL.Simple.ToField (ToField)
import           Servant (FromHttpApiData, ToHttpApiData)
#ifdef TESTING
import           Test.QuickCheck (Arbitrary)
#endif

type role Mid phantom
type Mid :: a -> Type
newtype Mid a = Mid { unMid :: Int }
  deriving stock (Generic)
  deriving newtype
    ( Enum
    , Eq
    , FromField
    , FromHttpApiData
    , FromJSON
    , FromJSONKey
    , NFData
    , Num
    , Ord
    , Show
    , ToField
    , ToHttpApiData
    , ToJSON
    , ToJSONKey
    )

derivingTypeScriptDefinition ''Mid

#ifdef TESTING
deriving newtype instance Arbitrary (Mid a)
#endif
