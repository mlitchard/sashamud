module DSL.BuilderSpec (spec) where

import           Data.Map.Strict (lookup, size)
import           Data.Set (member)
import           Grammar.Parser.Atomics.Semantics.Verbs.ImplicitStimulus
  ( isaLook
  )
import           Lens.Micro.Platform (view)
import           Model.Core
  ( ActionEffectKey (ImplicitStimulusActionKey)
  , ActionManagement (ISAManagementKey)
  , AgentKind (Denizen)
  , NarrationComputation (LookNarration)
  , WorldOutcome (NarrationEffect)
  , actionManagementFunctions
  , actionMaps
  , agentActionManagement
  , agentKind
  , agentShortName
  , getGIDToDataMap
  , implicitStimulusMap
  , newUserMkAgent
  , newUserStartScene
  , sceneActionManagement
  , sceneDescription
  , sceneMap
  , title
  , world
  , worldOutcomeEffects
  )
import           Model.GID (GID (GID))
import           Model.RichText (toPlainText)
import           SashaMudWorld (defaultDenizen, gameState, possibilityGraph)
import           SashaPrelude (Bool (True), Maybe (Just, Nothing), ($), (.))
import           Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)

spec :: Spec
spec = describe "DSL.Builder" $ do
  it "runWorldBuilder produces GameState with lobby scene" $ do
    let scenes = view (world . sceneMap . getGIDToDataMap) gameState
    size scenes `shouldBe` 1

  it "lobby scene has correct title" $ do
    let scenes = view (world . sceneMap . getGIDToDataMap) gameState
    case lookup (GID 0) scenes of
      Just lobby ->
        view title lobby `shouldBe` "the lobby"
      Nothing -> expectationFailure "lobby scene not found at GID 0"

  it "lobby scene has description" $ do
    let scenes = view (world . sceneMap . getGIDToDataMap) gameState
    case lookup (GID 0) scenes of
      Just lobby ->
        toPlainText (view sceneDescription lobby) `shouldBe` "A spacious lobby with high ceilings."
      Nothing -> expectationFailure "lobby scene not found at GID 0"

  it "lobby scene carries the look action management key" $ do
    let scenes = view (world . sceneMap . getGIDToDataMap) gameState
    case lookup (GID 0) scenes of
      Just lobby ->
        member (ISAManagementKey isaLook (GID 0))
          (view (sceneActionManagement . actionManagementFunctions) lobby)
          `shouldBe` True
      Nothing -> expectationFailure "lobby scene not found at GID 0"

  it "worldOutcomeEffects links the scene look key to LookNarration" $ do
    case lookup (ImplicitStimulusActionKey (GID 0)) (view worldOutcomeEffects possibilityGraph) of
      Just outcomes ->
        member (NarrationEffect LookNarration) outcomes `shouldBe` True
      Nothing -> expectationFailure "no world outcomes registered for scene look key"

  it "implicitStimulusMap has two look actions" $ do
    size (view (actionMaps . implicitStimulusMap) gameState) `shouldBe` 2

  describe "newUser template" $ do
    it "start scene is the lobby" $ do
      view newUserStartScene possibilityGraph `shouldBe` GID 0

    it "agent template produces agent with look action management" $ do
      let mkAgent = view newUserMkAgent possibilityGraph
          agent = mkAgent "alice"
      member (ISAManagementKey isaLook (GID 1))
        (view (agentActionManagement . actionManagementFunctions) agent)
        `shouldBe` True

  describe "defaultDenizen" $ do
    it "creates agent with correct name" $ do
      let agent = defaultDenizen "TestPlayer"
      toPlainText (view agentShortName agent) `shouldBe` "TestPlayer"

    it "creates Denizen kind" $ do
      let agent = defaultDenizen "TestPlayer"
      view agentKind agent `shouldBe` Denizen
