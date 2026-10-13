{-# LANGUAGE TemplateHaskell #-}
module Grammar.Parser.Atomics.Semantics.Adjectives
  ( adjectives
  ) where

import           Data.HashSet (HashSet, fromList)
import           Grammar.Lexer (Lexeme (SMALL, WHITE))
import           Grammar.Parser.Atomics.Adjectives (Adjective (Adjective))
import           Grammar.Parser.Atomics.AtomicsTH (makeSemanticValues)

makeSemanticValues [| Adjective |] [SMALL, WHITE]

adjectives :: HashSet Adjective
adjectives = fromList [small, white]
