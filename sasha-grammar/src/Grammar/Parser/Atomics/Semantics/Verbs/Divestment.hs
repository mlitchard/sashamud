{-# LANGUAGE TemplateHaskell #-}
module Grammar.Parser.Atomics.Semantics.Verbs.Divestment
  ( dropDV
  , divestmentVerbs
  ) where

import           Data.HashSet (HashSet, fromList)
import           Grammar.Lexer (Lexeme (DROP))
import           Grammar.Parser.Atomics.AtomicsTH (makeSemanticValues)
import           Grammar.Parser.Atomics.Verbs (DivestmentVerb (DivestmentVerb))

makeSemanticValues [| DivestmentVerb |] [DROP]

dropDV :: DivestmentVerb
dropDV = drop

divestmentVerbs :: HashSet DivestmentVerb
divestmentVerbs = fromList [drop]
