{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Monoid law, right identity" #-}
{-# HLINT ignore "Monoid law, left identity" #-}

module Model.Core.DefaultsSpec (spec) where

import           Lens.Micro.Platform (view)
import           Model.Core
  ( Narration (Narration)
  , defaultNarration
  , defaultScene
  , sceneAgents
  , title
  )
import           Model.RichText (RichText (RichText))
import           SashaPrelude (mempty, ($), (<>))
import           Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "Model.Core.Defaults" $ do
  it "defaultScene has empty title" $ do
    view title defaultScene `shouldBe` ""

  it "defaultScene has empty agents" $ do
    view sceneAgents defaultScene `shouldBe` mempty

  it "defaultNarration is mempty" $ do
    defaultNarration `shouldBe` mempty

  it "Narration mempty is identity under (<>)" $ do
    let n = Narration [RichText []] [] []
    n <> mempty `shouldBe` n
    mempty <> n `shouldBe` n
