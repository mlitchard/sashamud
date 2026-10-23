{-# LANGUAGE TemplateHaskell #-}
module Grammar.Parser.Atomics.Semantics.Adjectives
  ( adjectives
  , red
  ) where

import           Data.HashSet (HashSet, fromList)
import           Grammar.Lexer (Lexeme (RED, SMALL, WHITE))
import           Grammar.Parser.Atomics.Adjectives (Adjective (Adjective))
import           Grammar.Parser.Atomics.AtomicsTH (makeSemanticValues)

makeSemanticValues [| Adjective |] [SMALL, WHITE, RED]

adjectives :: HashSet Adjective
adjectives = fromList [small, white, red]
