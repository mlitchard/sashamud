module Model.GID
  ( GID (..)
  ) where

import SashaPrelude

import Control.DeepSeq (NFData (..))
import Data.Aeson (FromJSON, ToJSON)
import Data.Hashable (Hashable)

type role GID phantom
type GID :: Type -> Type
newtype GID a = GID { unGID :: Int }
  deriving newtype (Eq, Ord, Show, FromJSON, ToJSON, Hashable)

instance NFData (GID a) where
  rnf (GID i) = rnf i
