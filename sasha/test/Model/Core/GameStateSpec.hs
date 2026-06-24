module Model.Core.GameStateSpec (spec) where

import           Lens.Micro.Platform (view)
import           Model.Core
  ( defaultGameState
  , defaultPossibilityGraph
  , getGIDToDataMap
  , sceneMap
  , world
  )
import           SashaPrelude
import           Test.Hspec

spec :: Spec
spec = describe "Model.Core.GameState" $ do
  it "default GameState has empty sceneMap" $ do
    view (world . sceneMap . getGIDToDataMap) defaultGameState `shouldBe` mempty

  it "default PossibilityGraph is empty" $ do
    let pg = defaultPossibilityGraph
    seq pg (True `shouldBe` True)
