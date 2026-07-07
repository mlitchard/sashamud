module Model.Core.GameStateSpec (spec) where

import           Lens.Micro.Platform (view)
import           Model.Core (defaultWorld, getGIDToDataMap, sceneMap)
import           SashaPrelude (mempty, ($), (.))
import           Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "Model.Core.GameState" $ do
  it "default World has empty sceneMap" $ do
    view (sceneMap . getGIDToDataMap) defaultWorld `shouldBe` mempty
