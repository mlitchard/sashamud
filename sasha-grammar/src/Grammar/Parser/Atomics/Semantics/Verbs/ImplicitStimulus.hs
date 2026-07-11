{-# LANGUAGE TemplateHaskell #-}
module Grammar.Parser.Atomics.Semantics.Verbs.ImplicitStimulus (isaLook,look,implicitStimulusVerbs) where

import           Data.HashSet (HashSet, fromList)
import           Grammar.Lexer (Lexeme (LOOK))
import           Grammar.Parser.Atomics.AtomicsTH (makeSemanticValues)
import           Grammar.Parser.Atomics.Verbs
  ( ImplicitStimulusVerb (ImplicitStimulusVerb)
  )


makeSemanticValues [| ImplicitStimulusVerb |] [LOOK]

isaLook :: ImplicitStimulusVerb
isaLook = look

implicitStimulusVerbs :: HashSet ImplicitStimulusVerb
implicitStimulusVerbs =
  fromList [look]



