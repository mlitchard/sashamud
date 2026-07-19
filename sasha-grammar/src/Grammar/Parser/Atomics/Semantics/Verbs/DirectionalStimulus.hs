{-# LANGUAGE TemplateHaskell #-}
module Grammar.Parser.Atomics.Semantics.Verbs.DirectionalStimulus
  ( dsaLook
  , directionalStimulusVerbs
  ) where

import           Data.HashSet (HashSet, fromList)
import           Grammar.Lexer (Lexeme (LOOK))
import           Grammar.Parser.Atomics.AtomicsTH (makeSemanticValues)
import           Grammar.Parser.Atomics.Verbs
  ( DirectionalStimulusVerb (DirectionalStimulusVerb)
  )

makeSemanticValues [| DirectionalStimulusVerb |] [LOOK]

dsaLook :: DirectionalStimulusVerb
dsaLook = look

directionalStimulusVerbs :: HashSet DirectionalStimulusVerb
directionalStimulusVerbs = fromList [look]
