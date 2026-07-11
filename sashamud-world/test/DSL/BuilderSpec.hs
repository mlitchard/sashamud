module DSL.BuilderSpec (spec) where

import           Control.Monad.Except (runExceptT)
import           Control.Monad.State (runStateT)
import           Control.Monad.Trans.Reader (ReaderT (runReaderT))
import           Data.Functor.Identity (runIdentity)
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
  , ComputationContext (ComputationContext, _ctxPossibilityGraph, _newUser)
  , GameComputation (runGameComputation)
  , GameStateT (runGameStateT)
  , NarrationComputation (LookNarration)
  , WorldOutcome (NarrationEffect)
  , actionManagementFunctions
  , actionMaps
  , agentActionManagement
  , agentKind
  , agentLocationMap
  , agentMap
  , agentShortName
  , getAgentMap
  , getGIDToDataMap
  , implicitStimulusMap
  , newUserF
  , sceneActionManagement
  , sceneAgents
  , sceneDescription
  , sceneMap
  , title
  , world
  , worldOutcomeEffects
  )
import           Model.GID (GID (GID))
import           Model.RichText (toPlainText)
import           SashaMudWorld (defaultDenizen, gameState, possibilityGraph)
import           SashaPrelude
  ( Bool (True)
  , Either (Left, Right)
  , Maybe (Just, Nothing)
  , flip
  , pure
  , unpack
  , ($)
  , (.)
  , (<>)
  )
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
    size (view (actionMaps . implicitStimulusMap) possibilityGraph) `shouldBe` 2

  describe "newUserF" $ do
    it "creates the agent with look, places it in the lobby" $ do
      let ctx = ComputationContext
            { _ctxPossibilityGraph = possibilityGraph
            , _newUser             = pure ()
            }
          comp = view newUserF possibilityGraph (GID 7) "alice"
          result = runIdentity
                 . flip runStateT gameState
                 . runGameStateT
                 . runExceptT
                 . flip runReaderT ctx
                 . runGameComputation
                 $ comp
      case result of
        (Left err, _) ->
          expectationFailure ("newUser computation failed: " <> unpack err)
        (Right (), gs') -> do
          case lookup (GID 7) (view (world . agentMap . getAgentMap) gs') of
            Just agent ->
              member (ISAManagementKey isaLook (GID 1))
                (view (agentActionManagement . actionManagementFunctions) agent)
                `shouldBe` True
            Nothing -> expectationFailure "agent not created at GID 7"
          lookup (GID 7) (view agentLocationMap gs') `shouldBe` Just (GID 0)
          case lookup (GID 0) (view (world . sceneMap . getGIDToDataMap) gs') of
            Just lobby ->
              member (GID 7) (view sceneAgents lobby) `shouldBe` True
            Nothing -> expectationFailure "lobby scene not found after newUser"

  describe "defaultDenizen" $ do
    it "creates agent with correct name" $ do
      let agent = defaultDenizen "TestPlayer"
      toPlainText (view agentShortName agent) `shouldBe` "TestPlayer"

    it "creates Denizen kind" $ do
      let agent = defaultDenizen "TestPlayer"
      view agentKind agent `shouldBe` Denizen
