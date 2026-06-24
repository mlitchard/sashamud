module DSL.Vocabulary
  ( andThen
  ) where

import           SashaPrelude

import           DSL.Model.EDSL.SashaLambdaDSL (SashaLambdaDSL)

andThen :: (a -> SashaLambdaDSL a) -> (a -> SashaLambdaDSL a) -> a -> SashaLambdaDSL a
andThen f g x = f x >>= g
