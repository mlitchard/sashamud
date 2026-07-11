module Engine.ActionDiscovery.Protocol
  ( ActionProtocol (getActionMap, mkEffectKey, lookupActionGID, runActionProtocol, noGIDError, noActionError, ActionInput)
  , actionTypeName
  , fetchAction
  , fetchSceneAction
  , fetchAgentAction
  ) where

import           SashaPrelude

import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (Map, lookup)
import           Data.Typeable (Proxy (Proxy), Typeable, typeRep)
import           Error (throwMaybeM)
import           Lens.Micro.Platform (use, view)
import           Model.Core
  ( ActionEffectKey
  , ActionManagementFunctions
  , ActionMaps
  , Agent
  , GameComputation
  , agentActionManagement
  , agentLocationMap
  , agentMap
  , getAgentMap
  , getGIDToDataMap
  , sceneActionManagement
  , sceneMap
  , world
  )
import           Model.GID (GID)

-- | The core protocol that all action types must follow
-- Each instance defines its own coordination pattern
type ActionProtocol :: Type -> Constraint
class (Typeable actionF) => ActionProtocol actionF where
  -- | The input type that triggers this action (verb for simple, verb + nouns for object-based)
  type ActionInput actionF

  -- | Extract the specific action map from ActionMaps
  getActionMap :: ActionMaps -> Map (GID actionF) actionF

  -- | Create the appropriate ActionEffectKey constructor
  mkEffectKey :: GID actionF -> ActionEffectKey

  -- | Look up action GID from input and available actions
  lookupActionGID :: ActionInput actionF
                  -> ActionManagementFunctions
                  -> Maybe (GID actionF)

  -- | The coordination pattern - how to orchestrate actions across entities
  -- This is THE key abstraction - each action type defines how it coordinates
  -- Simple actions: actor + scene veto
  runActionProtocol :: GID Agent -> ActionInput actionF -> GameComputation Identity ()

  -- | Error message when no GID found for input
  noGIDError :: Text
  noGIDError = "Programmer Error: No action GID found for input in " <> actionTypeName @actionF

  -- | Error message when no action found for GID
  noActionError :: GID actionF -> Text
  noActionError gid = "Programmer Error: No action found for GID: " <> pack (show gid) <> " in " <> actionTypeName @actionF

-- | Get the type name for error messages
actionTypeName :: forall actionF. Typeable actionF => Text
actionTypeName = pack (show (typeRep (Proxy :: Proxy actionF)))

-- | Fetch action from map given GID
fetchAction :: forall actionF. ActionProtocol actionF
            => Map (GID actionF) actionF
            -> GID actionF
            -> GameComputation Identity actionF
fetchAction actionMap gid =
  throwMaybeM (noActionError @actionF gid) (lookup gid actionMap)

-- | Fetch agent's action GID and action
fetchAgentAction :: forall actionF. ActionProtocol actionF
                 => ActionInput actionF
                 -> Map (GID actionF) actionF
                 -> GID Agent
                 -> GameComputation Identity (GID actionF, actionF)
fetchAgentAction input actionMap agentGID = do
  aMap <- use (world . agentMap . getAgentMap)
  agent <- throwMaybeM ("Agent not found in agent map: " <> pack (show agentGID)) (lookup agentGID aMap)
  gid <- throwMaybeM ("Agent: " <> noGIDError @actionF)
           (lookupActionGID @actionF input (view agentActionManagement agent))
  action <- fetchAction @actionF actionMap gid
  pure (gid, action)

-- | Fetch scene's action GID and action (scene derived from the actor's current scene)
fetchSceneAction :: forall actionF. ActionProtocol actionF
                 => ActionInput actionF
                 -> Map (GID actionF) actionF
                 -> GID Agent
                 -> GameComputation Identity (GID actionF, actionF)
fetchSceneAction input actionMap agentGID = do
  locMap <- use agentLocationMap
  sceneGID <- throwMaybeM ("Agent location not found: " <> pack (show agentGID)) (lookup agentGID locMap)
  sMap <- use (world . sceneMap . getGIDToDataMap)
  scene <- throwMaybeM ("Scene not found in scene map" <> pack (show sceneGID)) (lookup sceneGID sMap)
  gid <- throwMaybeM ("Scene: " <> noGIDError @actionF)
           (lookupActionGID @actionF input (view sceneActionManagement scene))
  action <- fetchAction @actionF actionMap gid
  pure (gid, action)
