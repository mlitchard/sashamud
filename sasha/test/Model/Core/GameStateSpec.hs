module Model.Core.GameStateSpec (spec) where

import           Data.Map.Strict (empty)
import           Lens.Micro.Platform (view)
import           Model.Core
  ( actionMaps
  , defaultGameState
  , defaultPossibilityGraph
  , emptyActionMaps
  , entityActionEffects
  , getGIDToDataMap
  , sceneMap
  , world
  , worldOutcomeEffects
  )
import           SashaPrelude (mempty, ($), (.))
import           Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "Model.Core.GameState" $ do
  it "default GameState has empty sceneMap" $ do
    view (world . sceneMap . getGIDToDataMap) defaultGameState `shouldBe` mempty

  it "default PossibilityGraph has empty actionMaps" $ do
    view actionMaps defaultPossibilityGraph `shouldBe` emptyActionMaps

  it "default PossibilityGraph has empty entityActionEffects" $ do
    view entityActionEffects defaultPossibilityGraph `shouldBe` empty

  it "default PossibilityGraph has empty worldOutcomeEffects" $ do
    view worldOutcomeEffects defaultPossibilityGraph `shouldBe` empty
