module Engine.ActionDiscovery.Instances () where

import           SashaPrelude

import           Control.Monad.State (gets)
import           Engine.ActionDiscovery.Protocol
  ( ActionProtocol (ActionInput, getActionMap, lookupActionGID, mkEffectKey, runActionProtocol)
  , fetchAgentAction
  , fetchSceneAction
  )
import           Engine.Resolution.ActionManagement (lookupImplicitStimulus)
import           Grammar.Parser.Atomics.Verbs (ImplicitStimulusVerb)
import           Lens.Micro.Platform (view)
import           Model.Core
  ( ActionEffectKey (ImplicitStimulusActionKey)
  , ImplicitStimulusF (ImplicitNoStimulusF, ImplicitStimulusF)
  , actionMaps
  , implicitStimulusMap
  )

-- | Instance for ImplicitStimulusF (actor + scene veto for bare "look")
instance ActionProtocol ImplicitStimulusF where
  type ActionInput ImplicitStimulusF = ImplicitStimulusVerb

  getActionMap = view implicitStimulusMap

  mkEffectKey = ImplicitStimulusActionKey

  lookupActionGID = lookupImplicitStimulus

  -- Coordination: Actor + Scene (scene always vetoes)
  runActionProtocol actorGid verb = do
    actionMap <- gets (getActionMap @ImplicitStimulusF . view actionMaps)
    (playerGID, playerAction) <- fetchAgentAction @ImplicitStimulusF verb actionMap actorGid
    (sceneGID, sceneAction) <- fetchSceneAction @ImplicitStimulusF verb actionMap actorGid

    let playerKey = mkEffectKey @ImplicitStimulusF playerGID
        sceneKey = mkEffectKey @ImplicitStimulusF sceneGID

    -- Pattern match - scene veto chain
    case (playerAction, sceneAction) of
      (ImplicitNoStimulusF pf, _) ->
        pf actorGid playerKey
      (_, ImplicitNoStimulusF lf) ->
        lf actorGid sceneKey
      (ImplicitStimulusF ps, ImplicitStimulusF ls) ->
        ps actorGid playerKey >> ls actorGid sceneKey
