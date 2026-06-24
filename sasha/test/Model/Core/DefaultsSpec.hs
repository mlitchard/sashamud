module Model.Core.DefaultsSpec (spec) where

import           Model.Core
  ( Narration (Narration)
  , Scene (_sceneAgents, _title)
  , defaultNarration
  , defaultScene
  )
import           Model.RichText (RichText (RichText))
import           SashaPrelude
import           Test.Hspec

spec :: Spec
spec = describe "Model.Core.Defaults" $ do
  it "defaultScene has empty title" $ do
    _title defaultScene `shouldBe` ""

  it "defaultScene has empty agents" $ do
    _sceneAgents defaultScene `shouldBe` mempty

  it "defaultNarration is mempty" $ do
    defaultNarration `shouldBe` mempty

  it "Narration mempty is identity under (<>)" $ do
    let n = Narration [RichText []] [] []
    n <> mempty `shouldBe` n
    mempty <> n `shouldBe` n
