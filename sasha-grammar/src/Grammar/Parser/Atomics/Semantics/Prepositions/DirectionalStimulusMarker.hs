{-# LANGUAGE TemplateHaskell #-}
module Grammar.Parser.Atomics.Semantics.Prepositions.DirectionalStimulusMarker
  ( atDS
  , directionalStimulusMarkers
  ) where

import           Data.HashSet (HashSet, fromList)
import           Grammar.Lexer (Lexeme (AT))
import           Grammar.Parser.Atomics.AtomicsTH (makeSemanticValues)
import           Grammar.Parser.Atomics.Prepositions
  ( DirectionalStimulusMarker (DirectionalStimulusMarker)
  )

makeSemanticValues [| DirectionalStimulusMarker |] [AT]

atDS :: DirectionalStimulusMarker
atDS = at

directionalStimulusMarkers :: HashSet DirectionalStimulusMarker
directionalStimulusMarkers = fromList [at]
