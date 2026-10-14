module DSL.BuilderSpec (spec) where

import           Control.Monad.Except (runExceptT)
import           Data.Map.Strict (lookup, size)
import           DSL.Builder (WorldBuilderResult (resultGameState))
import           Lens.Micro.Platform (view)
import           Model.Core
  ( actionMaps
  , getGIDToDataMap
  , implicitStimulusMap
  , sceneDescription
  , sceneMap
  , title
  , world
  )
import           Model.GID (GID (GID))
import           Model.RichText (toPlainText)
import           SashaPrelude
  ( Either (Left, Right)
  , Maybe (Just, Nothing)
  , ($)
  , (.)
  )
import           Server.World (loadWorld, worldLoadFailureText)
import           System.Environment (lookupEnv)
import           Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)

spec :: Spec
spec = describe "DSL.Builder" $ do
  it "runWorldBuilder produces GameState with lobby scene" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result -> do
            let scenes = view (world . sceneMap . getGIDToDataMap) (resultGameState result)
            size scenes `shouldBe` 1

  it "lobby scene has correct title" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result -> do
            let scenes = view (world . sceneMap . getGIDToDataMap) (resultGameState result)
            case lookup (GID 0) scenes of
              Just lobby ->
                view title lobby `shouldBe` "the lobby"
              Nothing -> expectationFailure "lobby scene not found at GID 0"

  it "lobby scene has description" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result -> do
            let scenes = view (world . sceneMap . getGIDToDataMap) (resultGameState result)
            case lookup (GID 0) scenes of
              Just lobby ->
                toPlainText (view sceneDescription lobby) `shouldBe` "A spacious lobby with high ceilings."
              Nothing -> expectationFailure "lobby scene not found at GID 0"

  it "implicitStimulusMap has two look actions" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result ->
            size (view (actionMaps . implicitStimulusMap) (resultGameState result)) `shouldBe` 2
