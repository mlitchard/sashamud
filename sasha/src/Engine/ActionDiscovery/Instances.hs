module Engine.ActionDiscovery.Instances () where

import           SashaPrelude

import           Control.Monad.Except (throwError)
import           Control.Monad.State (gets)
import           Data.Map.Strict (lookup)
import           Engine.ActionDiscovery.Protocol
  ( ActionProtocol (ActionInput, getActionMap, lookupActionGID, mkEffectKey, runActionProtocol)
  , fetchAction
  , fetchAgentAction
  , fetchSceneAction
  )
import           Engine.Resolution.ActionManagement
  ( lookupDirectionalStimulus
  , lookupImplicitStimulus
  , processWitnesses
  )
import           Error (throwMaybeM)
import           Grammar.Lexer (HasLexeme (toLexeme))
import           Grammar.Parser.Atomics.Verbs
  ( DirectionalStimulusVerb
  , ImplicitStimulusVerb
  )
import           Grammar.Parser.Composites.Nouns
  ( DirectionalStimulusNounPhrase (DirectionalStimulusNounPhrase)
  , NounPhrase (SimpleNounPhrase)
  )
import           Grammar.Parser.GCase
  ( VerbKey (DirectionalStimulusKey, ImplicitStimulusKey)
  )
import           Lens.Micro.Platform (use, view)
import           Model.Core
  ( ActionEffectKey (DirectionalStimulusActionKey, ImplicitStimulusActionKey)
  , DirectionalStimulusF (DirectionalNoStimulusF, DirectionalStimulusF)
  , ImplicitStimulusF (ImplicitNoStimulusF, ImplicitStimulusF)
  , WitnessContext (DirectedWitnessContext, ImplicitWitnessContext)
  , actionMaps
  , directionalStimulusMap
  , getGIDToDataMap
  , globalSemanticMap
  , implicitStimulusMap
  , objectActionManagement
  , objectMap
  , world
  )

-- | Instance for ImplicitStimulusF (actor + scene veto for bare "look")
instance ActionProtocol ImplicitStimulusF where
  type ActionInput ImplicitStimulusF = ImplicitStimulusVerb

  getActionMap = view implicitStimulusMap

  mkEffectKey = ImplicitStimulusActionKey

  lookupActionGID = lookupImplicitStimulus

  runActionProtocol actorGid verb = do
    actionMap <- gets (getActionMap @ImplicitStimulusF . view actionMaps)
    (playerGID, playerAction) <- fetchAgentAction @ImplicitStimulusF verb actionMap actorGid
    (sceneGID, sceneAction) <- fetchSceneAction @ImplicitStimulusF verb actionMap actorGid

    let playerKey = mkEffectKey @ImplicitStimulusF playerGID
        sceneKey = mkEffectKey @ImplicitStimulusF sceneGID

    case (playerAction, sceneAction) of
      (ImplicitNoStimulusF pf, _) ->
        pf actorGid playerKey
      (_, ImplicitNoStimulusF lf) ->
        lf actorGid sceneKey
      (ImplicitStimulusF ps, ImplicitStimulusF ls) ->
        ps actorGid playerKey
          >> ls actorGid sceneKey
          >> processWitnesses actorGid (ImplicitStimulusKey verb) ImplicitWitnessContext

-- | Instance for DirectionalStimulusF (actor + object + scene veto for "look at X")
instance ActionProtocol DirectionalStimulusF where
  type ActionInput DirectionalStimulusF = (DirectionalStimulusVerb, DirectionalStimulusNounPhrase)

  getActionMap = view directionalStimulusMap

  mkEffectKey = DirectionalStimulusActionKey

  lookupActionGID (verb, _) = lookupDirectionalStimulus verb

  runActionProtocol actorGid (verb, nounPhrase) = do
    -- Resolve object from noun phrase via globalSemanticMap
    let nounText = extractDirectionalNoun nounPhrase
    semMap <- use (world . globalSemanticMap)
    objGIDSet <- throwMaybeM ("Nothing called \"" <> nounText <> "\" here.")
                   (lookup nounText semMap)
    objGID <- case toList objGIDSet of
                [gid] -> pure gid
                []    -> throwError ("Nothing called \"" <> nounText <> "\" here.")
                _     -> throwError ("Which " <> nounText <> "?")

    -- Fetch actions from player, object, scene
    actionMap <- gets (getActionMap @DirectionalStimulusF . view actionMaps)
    (playerGID, playerAction) <- fetchAgentAction @DirectionalStimulusF (verb, nounPhrase) actionMap actorGid

    oMap <- use (world . objectMap . getGIDToDataMap)
    obj <- throwMaybeM ("Object not found: " <> pack (show objGID))
             (lookup objGID oMap)
    objectActionGID <- throwMaybeM "Object has no look-at action"
                         (lookupDirectionalStimulus verb (view objectActionManagement obj))
    objectAction <- fetchAction @DirectionalStimulusF actionMap objectActionGID

    (sceneGID, sceneAction) <- fetchSceneAction @DirectionalStimulusF (verb, nounPhrase) actionMap actorGid

    let playerKey = mkEffectKey @DirectionalStimulusF playerGID
        objectKey = mkEffectKey @DirectionalStimulusF objectActionGID
        sceneKey  = mkEffectKey @DirectionalStimulusF sceneGID

    case (playerAction, objectAction, sceneAction) of
      (DirectionalNoStimulusF pf, _, _) ->
        pf actorGid playerKey
      (_, DirectionalNoStimulusF of', _) ->
        of' actorGid objectKey
      (_, _, DirectionalNoStimulusF lf) ->
        lf actorGid sceneKey
      (DirectionalStimulusF ps, DirectionalStimulusF os, DirectionalStimulusF ls) ->
        ps actorGid playerKey
          >> os actorGid objectKey
          >> ls actorGid sceneKey
          >> processWitnesses actorGid (DirectionalStimulusKey verb) (DirectedWitnessContext objGID)

-- | Extract noun text from DirectionalStimulusNounPhrase for globalSemanticMap lookup
extractDirectionalNoun :: DirectionalStimulusNounPhrase -> Text
extractDirectionalNoun (DirectionalStimulusNounPhrase _ (SimpleNounPhrase ds)) =
  pack (show (toLexeme ds))
