module Model.Core.Mappings
  ( -- * Action Management
    ActionManagement
  , ActionManagementFunctions (..)
  , actionManagementFunctions
  , GIDToDataMap (..)
  , getGIDToDataMap
    -- * Registries (empty at commit 1)
  , ActionMaps (..)
  , EntityActionRegistry
  , WorldOutcomeRegistry
  , emptyActionMaps
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData (..))
import           Data.Map.Strict (Map)
import           Data.Set (Set)
import           Lens.Micro.Platform (makeLenses)
import           Model.GID (GID)

-- | Action management stubs. Commit 2 adds verb-keyed constructors.
type ActionManagement :: Type
data ActionManagement
  deriving stock (Eq, Ord, Show)

instance NFData ActionManagement where
  rnf _ = ()

type ActionManagementFunctions :: Type
newtype ActionManagementFunctions = ActionManagementFunctions { _actionManagementFunctions :: Set ActionManagement }
  deriving stock (Eq, Ord, Show)
  deriving newtype (NFData)

makeLenses ''ActionManagementFunctions

-- | GID-keyed data maps. Phantom types for type safety.
type GIDToDataMap :: Type -> Type -> Type
newtype GIDToDataMap k v = GIDToDataMap { _getGIDToDataMap :: Map (GID k) v }
  deriving stock (Eq, Ord, Show)
  deriving newtype (NFData)

makeLenses ''GIDToDataMap

-- | Action maps — all empty at commit 1.
-- Commit 2 adds ImplicitStimulusMap etc.
type ActionMaps :: Type
data ActionMaps
  = ActionMaps
  deriving stock (Eq, Ord, Show)

instance NFData ActionMaps where
  rnf ActionMaps = ()

emptyActionMaps :: ActionMaps
emptyActionMaps = ActionMaps

-- | Empty registries at commit 1. Commit 2 populates them via DSL.
type EntityActionRegistry :: Type
type EntityActionRegistry = Map () ()

type WorldOutcomeRegistry :: Type
type WorldOutcomeRegistry = Map () ()
