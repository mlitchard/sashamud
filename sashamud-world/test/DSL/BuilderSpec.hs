module DSL.BuilderSpec (spec) where

import SashaPrelude
import Data.Map.Strict (lookup, size)
import Lens.Micro.Platform (view)
import Model.Core
  ( getGIDToDataMap
  , sceneDescription
  , sceneMap
  , world
  )
import Model.Core qualified as Core (title)
import Model.GID (GID (GID))
import Model.RichText (toPlainText)
import SashaMudWorld (gameState)
import Test.Hspec

spec :: Spec
spec = describe "DSL.Builder" $ do
  it "runWorldBuilder produces GameState with lobby scene" $ do
    let scenes = view (world . sceneMap . getGIDToDataMap) gameState
    size scenes `shouldBe` 1

  it "lobby scene has correct title" $ do
    let scenes = view (world . sceneMap . getGIDToDataMap) gameState
    case lookup (GID 0) scenes of
      Just lobby ->
        view Core.title lobby `shouldBe` "the lobby"
      Nothing -> expectationFailure "lobby scene not found at GID 0"

  it "lobby scene has description" $ do
    let scenes = view (world . sceneMap . getGIDToDataMap) gameState
    case lookup (GID 0) scenes of
      Just lobby ->
        toPlainText (view sceneDescription lobby) `shouldBe` "A spacious lobby with high ceilings."
      Nothing -> expectationFailure "lobby scene not found at GID 0"
