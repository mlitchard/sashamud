{-# OPTIONS_GHC -fconstraint-solver-iterations=10 #-}

module Model.RichText
  ( -- * Core Types
    RichText (RichText)
  , StyledSpan (StyledSpan)
  , TextStyle (TextStyle)
  , TextColor (Red, Green, Blue, Yellow, Cyan, Magenta, White, BrightWhite, BrightRed, BrightGreen, BrightBlue, BrightYellow, BrightCyan, BrightMagenta)
    -- * Lenses
  , ssStyle
  , ssText
  , tsFgColor
  , tsBold
  , tsItalic
    -- * Smart Constructors
  , plain
  , colored
  , bold
  , boldColored
  , styled
    -- * Conversion
  , toPlainText
    -- * Default Style
  , defaultStyle
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, ToJSON)
import           Data.Aeson.TypeScript (derivingTypeScriptDefinition)
import           Lens.Micro.Platform (makeLenses, view)
#ifdef TESTING
import           Test.QuickCheck (Arbitrary (arbitrary), arbitraryBoundedEnum)
import           Test.QuickCheck.Arbitrary.Generic (GenericArbitrary (..))
import           Test.QuickCheck.Instances.Text ()
#endif

type TextColor :: Type
data TextColor
  = Red
  | Green
  | Blue
  | Yellow
  | Cyan
  | Magenta
  | White
  | BrightWhite
  | BrightRed
  | BrightGreen
  | BrightBlue
  | BrightYellow
  | BrightCyan
  | BrightMagenta
  deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

type TextStyle :: Type
data TextStyle = TextStyle
  { _tsFgColor :: Maybe TextColor
  , _tsBold    :: Bool
  , _tsItalic  :: Bool
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

makeLenses ''TextStyle

defaultStyle :: TextStyle
defaultStyle = TextStyle
  { _tsFgColor = Nothing
  , _tsBold    = False
  , _tsItalic  = False
  }

type StyledSpan :: Type
data StyledSpan = StyledSpan
  { _ssStyle :: TextStyle
  , _ssText  :: Text
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

makeLenses ''StyledSpan

type RichText :: Type
newtype RichText = RichText { unRichText :: [StyledSpan] }
  deriving stock (Eq, Generic, Ord, Show)
  deriving newtype (FromJSON, ToJSON)
  deriving anyclass (NFData)

instance Semigroup RichText where
  RichText a <> RichText b = RichText (a <> b)

instance Monoid RichText where
  mempty = RichText []

toPlainText :: RichText -> Text
toPlainText (RichText spans) = mconcat (fmap (view ssText) spans)


plain :: Text -> RichText
plain t = RichText [StyledSpan defaultStyle t]

colored :: TextColor -> Text -> RichText
colored c t = RichText [StyledSpan (defaultStyle { _tsFgColor = Just c }) t]

bold :: Text -> RichText
bold t = RichText [StyledSpan (defaultStyle { _tsBold = True }) t]

boldColored :: TextColor -> Text -> RichText
boldColored c t = RichText [StyledSpan (TextStyle { _tsFgColor = Just c, _tsBold = True, _tsItalic = False }) t]

styled :: TextStyle -> Text -> RichText
styled s t = RichText [StyledSpan s t]

derivingTypeScriptDefinition ''TextColor
derivingTypeScriptDefinition ''TextStyle
derivingTypeScriptDefinition ''StyledSpan
derivingTypeScriptDefinition ''RichText

#ifdef TESTING
instance Arbitrary TextColor where
  arbitrary = arbitraryBoundedEnum
deriving via (GenericArbitrary TextStyle) instance Arbitrary TextStyle
deriving via (GenericArbitrary StyledSpan) instance Arbitrary StyledSpan
deriving newtype instance Arbitrary RichText
#endif
