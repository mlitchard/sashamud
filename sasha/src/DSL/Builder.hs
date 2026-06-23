module DSL.Builder
  ( interpretDSL
  , runWorldBuilder
  , initialBuilderState
  , WorldBuilder
  , WorldBuilderResult (WorldBuilderResult, resultGameState, resultPossibilityGraph)
  ) where

import SashaPrelude

import Control.Monad.State (State, get, put, runState)
import Data.Map.Strict (insert)
import DSL.Model.EDSL.SashaLambdaDSL (SashaLambdaDSL (..))
import Lens.Micro.Platform (Lens', (^.))
import Model.Core
  ( ActionMaps
  , EntityActionRegistry
  , GIDToDataMap (GIDToDataMap, _getGIDToDataMap)
  , GameState (_world)
  , PossibilityGraph (PossibilityGraph, _actionMaps, _entityActionEffects, _worldOutcomeEffects)
  , Scene (_title, _sceneDescription)
  , World (_sceneMap)
  , WorldOutcomeRegistry
  , emptyActionMaps
  , sceneMap
  )
import Model.GID (GID (GID))

data BuilderState = BuilderState
  { bsGameState            :: GameState
  , bsNextSceneGID         :: Int
  , bsActionMaps           :: ActionMaps
  , bsEntityActionRegistry :: EntityActionRegistry
  , bsWorldOutcomeRegistry :: WorldOutcomeRegistry
  }

type WorldBuilder = State BuilderState

type WorldBuilderResult :: Type
data WorldBuilderResult = WorldBuilderResult
  { resultGameState        :: GameState
  , resultPossibilityGraph :: PossibilityGraph
  }

initialBuilderState :: GameState -> BuilderState
initialBuilderState gs = BuilderState
  { bsGameState            = gs
  , bsNextSceneGID         = 0
  , bsActionMaps           = emptyActionMaps
  , bsEntityActionRegistry = mempty
  , bsWorldOutcomeRegistry = mempty
  }

interpretDSL :: SashaLambdaDSL a -> WorldBuilder a
interpretDSL (Pure a) = pure a
interpretDSL (Bind m f) = interpretDSL m >>= (interpretDSL . f)

interpretDSL (DeclareSceneGID _name) = do
  st <- get
  let gid = GID (bsNextSceneGID st)
  put st { bsNextSceneGID = bsNextSceneGID st + 1 }
  pure gid

interpretDSL (RegisterScene gid sceneBuilder) = do
  scene <- interpretDSL sceneBuilder
  st <- get
  let gs = bsGameState st
      sm = gs ^. world . sceneMap
      sm' = GIDToDataMap (insert gid scene (_getGIDToDataMap sm))
      gs' = gs { _world = (_world gs) { _sceneMap = sm' } }
  put st { bsGameState = gs' }

interpretDSL (Title t scene) = pure scene { _title = t }

interpretDSL (SceneDescription rt scene) = pure scene { _sceneDescription = rt }

interpretDSL FinalizeGameState = do
  st <- get
  pure (bsGameState st)

-- Internal accessor
world :: Lens' GameState World
world f gs = (\w -> gs { _world = w }) <$> f (_world gs)

runWorldBuilder :: WorldBuilder GameState -> BuilderState -> WorldBuilderResult
runWorldBuilder builder initState =
  let (gs, finalState) = runState builder initState
      possibilityGraph = PossibilityGraph
        { _actionMaps          = bsActionMaps finalState
        , _entityActionEffects = bsEntityActionRegistry finalState
        , _worldOutcomeEffects = bsWorldOutcomeRegistry finalState
        }
  in WorldBuilderResult
       { resultGameState        = gs
       , resultPossibilityGraph = possibilityGraph
       }
