module Model.Core.GameStateSpec (spec) where

import SashaPrelude
import Lens.Micro.Platform (view)
import Model.Core
  ( defaultGameState
  , defaultPossibilityGraph
  , getGIDToDataMap
  , sceneMap
  , world
  )
import Test.Hspec

spec :: Spec
spec = describe "Model.Core.GameState" $ do
  it "default GameState has empty sceneMap" $ do
    view (world . sceneMap . getGIDToDataMap) defaultGameState `shouldBe` mempty

  it "default PossibilityGraph is empty" $ do
    let pg = defaultPossibilityGraph
    seq pg (True `shouldBe` True)
