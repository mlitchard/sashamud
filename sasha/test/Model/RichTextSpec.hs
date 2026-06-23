module Model.RichTextSpec (spec) where

import SashaPrelude
import Data.Aeson (decode, encode)
import Model.RichText (RichText (RichText), StyledSpan (StyledSpan), TextColor (Red, White), TextStyle (TextStyle, tsBold, tsItalic), colored, boldColored, toPlainText)
import Test.Hspec

spec :: Spec
spec = describe "Model.RichText" $ do
  describe "smart constructors" $ do
    it "colored creates span with given color" $ do
      let rt = colored White "hello"
      toPlainText rt `shouldBe` "hello"

    it "boldColored creates bold span" $ do
      case boldColored Red "test" of
        RichText (StyledSpan style txt : rest) -> do
          tsBold style `shouldBe` True
          tsItalic style `shouldBe` False
          txt `shouldBe` "test"
          rest `shouldBe` []
        RichText [] -> expectationFailure "boldColored produced empty RichText"

    it "toPlainText strips styling" $ do
      let rt = colored White "one" <> boldColored Red "two"
      toPlainText rt `shouldBe` "onetwo"

  describe "Monoid" $ do
    it "mempty is identity" $ do
      let rt = colored White "hello"
      rt <> mempty `shouldBe` rt
      mempty <> rt `shouldBe` rt

  describe "JSON roundtrip" $ do
    it "RichText roundtrips" $ do
      let rt = colored White "hello world"
      decode (encode rt) `shouldBe` Just rt

    it "StyledSpan roundtrips" $ do
      let span' = StyledSpan (TextStyle (Just White) False False) "test"
      decode (encode span') `shouldBe` Just span'
