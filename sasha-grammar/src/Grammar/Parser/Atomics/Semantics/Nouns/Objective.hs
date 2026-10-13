{-# LANGUAGE TemplateHaskell #-}
module Grammar.Parser.Atomics.Semantics.Nouns.Objective
  ( ballOB
  , floorOB
  , objectives
  ) where

import           Data.HashSet (HashSet, fromList)
import           Grammar.Lexer (Lexeme (BALL, FLOOR))
import           Grammar.Parser.Atomics.AtomicsTH (makeSemanticValues)
import           Grammar.Parser.Atomics.Nouns (Objective (Objective))

makeSemanticValues [| Objective |] [BALL, FLOOR]

ballOB :: Objective
ballOB = ball

floorOB :: Objective
floorOB = floor

objectives :: HashSet Objective
objectives = fromList [ball, floor]
