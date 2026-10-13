{-# LANGUAGE TemplateHaskell #-}
module Grammar.Parser.Atomics.Semantics.Misc
  ( determiners
  ) where

import           Data.HashSet (HashSet, fromList)
import           Grammar.Lexer (Lexeme (A, THE))
import           Grammar.Parser.Atomics.AtomicsTH (makeSemanticValues)
import           Grammar.Parser.Atomics.Misc (Determiner (Determiner))

makeSemanticValues [| Determiner |] [THE, A]

determiners :: HashSet Determiner
determiners = fromList [a, the]
