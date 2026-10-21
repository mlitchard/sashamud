module Engine.ActionDiscovery.Protocol
  ( ActionProtocol (getActionMap, mkEffectKey, mkVerbKey, lookupActionGID, lookupTargetActionGID, runActionProtocol, noGIDError, noActionError, ActionInput)
  , actionTypeName
  , fetchAction
  , fetchSceneAction
  , fetchAgentAction
  , fetchTargetAction
  ) where

import           SashaPrelude

import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (Map, lookup)
import           Data.Typeable (Proxy (Proxy), Typeable, typeRep)
import           Error (throwMaybeM)
import           Grammar.Parser.GCase (VerbKey)
import           Lens.Micro.Platform (use, view)
import           Model.Core
  ( ActionEffectKey
  , ActionManagementFunctions
  , ActionMaps
  , ActorKey
  , Agent
  , Entity (AgentEntity, ObjectEntity, SceneEntity)
  , EntityKey (EntityAgent, EntityObject, EntityScene)
  , GameComputation
  , GameError (ActionGIDMissing, ActionMissing, AgentLocationMissing, AgentMissing, ObjectMissing, SceneMissing)
  , TargetKey (TargetKey)
  , actorTargetActionManagement
  , agentActionManagement
  , agentLocationMap
  , agentMap
  , getAgentMap
  , getGIDToDataMap
  , objectActionManagement
  , objectMap
  , sceneActionManagement
  , sceneMap
  , sharedActionManagement
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

  mkVerbKey :: ActionInput actionF -> VerbKey

  -- | Look up action GID from input and available actions
  lookupActionGID :: ActionInput actionF
                  -> ActionManagementFunctions
                  -> Maybe (GID actionF)

  lookupTargetActionGID :: ActionInput actionF
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
  throwMaybeM (ActionMissing (noActionError @actionF gid)) (lookup gid actionMap)

-- | Fetch agent's action GID and action
fetchAgentAction :: forall actionF. ActionProtocol actionF
                 => ActionInput actionF
                 -> Map (GID actionF) actionF
                 -> GID Agent
                 -> GameComputation Identity (GID actionF, actionF)
fetchAgentAction input actionMap agentGID = do
  aMap <- use (world . agentMap . getAgentMap)
  agent <- throwMaybeM (AgentMissing agentGID) (lookup agentGID aMap)
  shared <- use (world . sharedActionManagement)
  gid <- throwMaybeM (ActionGIDMissing ("Agent: " <> noGIDError @actionF))
           (lookupActionGID @actionF input (view agentActionManagement agent)
              <|> (lookup (mkVerbKey @actionF input) shared >>= lookup AgentEntity >>= lookupActionGID @actionF input))
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
  sceneGID <- throwMaybeM (AgentLocationMissing agentGID) (lookup agentGID locMap)
  sMap <- use (world . sceneMap . getGIDToDataMap)
  scene <- throwMaybeM (SceneMissing sceneGID) (lookup sceneGID sMap)
  gid <- throwMaybeM (ActionGIDMissing ("Scene: " <> noGIDError @actionF))
           (lookupTargetActionGID @actionF input (view sceneActionManagement scene))
  action <- fetchAction @actionF actionMap gid
  pure (gid, action)

fetchTargetAction :: forall actionF. ActionProtocol actionF
                  => ActionInput actionF
                  -> Map (GID actionF) actionF
                  -> ActorKey
                  -> TargetKey
                  -> GameComputation Identity (GID actionF, actionF)
fetchTargetAction input actionMap actorKey targetKey@(TargetKey targetEntity) = do
  actorTarget <- use (world . actorTargetActionManagement)
  (entity, targetActions) <- case targetEntity of
    EntityAgent agentGID -> do
      aMap <- use (world . agentMap . getAgentMap)
      agent <- throwMaybeM (AgentMissing agentGID) (lookup agentGID aMap)
      pure (AgentEntity, view agentActionManagement agent)
    EntityObject objectGID -> do
      oMap <- use (world . objectMap . getGIDToDataMap)
      obj <- throwMaybeM (ObjectMissing objectGID) (lookup objectGID oMap)
      pure (ObjectEntity, view objectActionManagement obj)
    EntityScene sceneGID -> do
      sMap <- use (world . sceneMap . getGIDToDataMap)
      scene <- throwMaybeM (SceneMissing sceneGID) (lookup sceneGID sMap)
      pure (SceneEntity, view sceneActionManagement scene)
  shared <- use (world . sharedActionManagement)
  gid <- throwMaybeM (ActionGIDMissing ("Target: " <> noGIDError @actionF))
           ((lookup actorKey actorTarget >>= lookup targetKey >>= lookupTargetActionGID @actionF input)
              <|> lookupTargetActionGID @actionF input targetActions
              <|> (lookup (mkVerbKey @actionF input) shared >>= lookup entity >>= lookupTargetActionGID @actionF input))
  action <- fetchAction @actionF actionMap gid
  pure (gid, action)
