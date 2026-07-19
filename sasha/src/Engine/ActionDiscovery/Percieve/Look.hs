module Engine.ActionDiscovery.Percieve.Look
  ( manageAgentStimulusProcess
  , manageDirectionalStimulusProcess
  , manageImplicitStimulusProcess
  ) where

import           SashaPrelude

import           Control.Monad.State (gets)
import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (lookup)
import           Data.Text (toUpper)
import           Engine.ActionDiscovery.Instances ()
import           Engine.ActionDiscovery.Protocol
  ( ActionProtocol (getActionMap, mkEffectKey, runActionProtocol)
  , fetchAction
  )
import           Engine.Resolution.ActionManagement
  ( lookupDirectionalStimulus
  , processWitnesses
  )
import           Engine.Resolution.Perception (modifyAgentNarration)
import           Error (throwMaybeM)
import           Grammar.Parser.Atomics.Verbs
  ( DirectionalStimulusVerb
  , ImplicitStimulusVerb
  )
import           Grammar.Parser.Composites.Nouns
  ( DirectionalStimulusNounPhrase
  , PlayerName (PlayerName)
  )
import           Grammar.Parser.GCase (VerbKey (DirectionalStimulusKey))
import           Lens.Micro.Platform (over, use, view)
import           Model.Core
  ( Agent
  , DirectionalStimulusF (DirectionalNoStimulusF, DirectionalStimulusF)
  , GameComputation
  , ImplicitStimulusF
  , WitnessContext (AgentWitnessContext, FailedAgentLookContext)
  , actionConsequence
  , actionMaps
  , agentActionManagement
  , agentDescription
  , agentLocationMap
  , agentMap
  , agentShortName
  , getAgentMap
  , getGIDToDataMap
  , sceneActionManagement
  , sceneAgents
  , sceneMap
  , world
  )
import           Model.GID (GID)
import           Model.RichText (TextColor (White), colored, toPlainText)

manageImplicitStimulusProcess :: GID Agent
                              -> ImplicitStimulusVerb
                              -> GameComputation Identity ()
manageImplicitStimulusProcess = runActionProtocol @ImplicitStimulusF

manageDirectionalStimulusProcess :: GID Agent
                                 -> DirectionalStimulusVerb
                                 -> DirectionalStimulusNounPhrase
                                 -> GameComputation Identity ()
manageDirectionalStimulusProcess actorGid verb phrase =
  runActionProtocol @DirectionalStimulusF actorGid (verb, phrase)

manageAgentStimulusProcess :: GID Agent
                           -> DirectionalStimulusVerb
                           -> PlayerName
                           -> GameComputation Identity ()
manageAgentStimulusProcess actorGid verb (PlayerName playerNameText) = do
  -- Resolve target agent by name in current scene
  aMap <- use (world . agentMap . getAgentMap)
  locMap <- use agentLocationMap
  sceneGid <- throwMaybeM ("Agent location not found: " <> pack (show actorGid))
                (lookup actorGid locMap)
  sMap <- use (world . sceneMap . getGIDToDataMap)
  scene <- throwMaybeM ("Scene not found: " <> pack (show sceneGid))
             (lookup sceneGid sMap)

  let otherGids = toList (view sceneAgents scene)
  others <- forM otherGids $ \gid -> do
    agent <- throwMaybeM ("Programmer Error: sceneAgents contains GID not in agentMap: " <> pack (show gid))
               (lookup gid aMap)
    pure (gid, agent)
  let candidates =
        [ gid
        | (gid, agent) <- others
        , toUpper (toPlainText (view agentShortName agent)) == playerNameText
        ]
  case candidates of
    [] -> do
      modifyAgentNarration actorGid
        (over actionConsequence (<> [colored White ("Nobody called \"" <> playerNameText <> "\" here.")]))
      processWitnesses actorGid (DirectionalStimulusKey verb) FailedAgentLookContext
    (_:_:_) -> do
      modifyAgentNarration actorGid
        (over actionConsequence (<> [colored White ("Which " <> playerNameText <> "?")]))
      pure ()
    [targetGid] -> do
      -- Fetch action map
      actionMap <- gets (getActionMap @DirectionalStimulusF . view actionMaps)

      -- Player veto
      actor <- throwMaybeM ("Agent not found: " <> pack (show actorGid))
                 (lookup actorGid aMap)
      playerGID <- throwMaybeM "Agent: no directional stimulus action"
                     (lookupDirectionalStimulus verb (view agentActionManagement actor))
      playerAction <- fetchAction @DirectionalStimulusF actionMap playerGID

      -- Target agent veto
      target <- throwMaybeM ("Agent not found: " <> pack (show targetGid))
                  (lookup targetGid aMap)
      targetActionGID <- throwMaybeM "Target has no look-at action"
                           (lookupDirectionalStimulus verb (view agentActionManagement target))
      targetAction <- fetchAction @DirectionalStimulusF actionMap targetActionGID

      -- Scene veto
      sceneActionGID <- throwMaybeM "Scene: no directional stimulus action"
                          (lookupDirectionalStimulus verb (view sceneActionManagement scene))
      sceneAction <- fetchAction @DirectionalStimulusF actionMap sceneActionGID

      let playerKey = mkEffectKey @DirectionalStimulusF playerGID
          targetKey = mkEffectKey @DirectionalStimulusF targetActionGID
          sceneKey  = mkEffectKey @DirectionalStimulusF sceneActionGID

      case (playerAction, targetAction, sceneAction) of
        (DirectionalNoStimulusF pf, _, _) ->
          pf actorGid playerKey
        (_, DirectionalNoStimulusF tf, _) ->
          tf actorGid targetKey
        (_, _, DirectionalNoStimulusF sf) ->
          sf actorGid sceneKey
        (DirectionalStimulusF ps, DirectionalStimulusF ts, DirectionalStimulusF ls) -> do
          ps actorGid playerKey
          ts actorGid targetKey
          ls actorGid sceneKey
          modifyAgentNarration actorGid
            (over actionConsequence (<> [view agentDescription target]))
          processWitnesses actorGid (DirectionalStimulusKey verb) (AgentWitnessContext targetGid)
