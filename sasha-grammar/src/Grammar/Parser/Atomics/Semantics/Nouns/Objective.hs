{-# LANGUAGE TemplateHaskell #-}
module Grammar.Parser.Atomics.Semantics.Nouns.Objective
  ( ballOB
  , cupOB
  , floorOB
  , tableOB
  , objectives
  ) where

import           Data.HashSet (HashSet, fromList)
import           Grammar.Lexer (Lexeme (BALL, CUP, FLOOR, TABLE))
import           Grammar.Parser.Atomics.AtomicsTH (makeSemanticValues)
import           Grammar.Parser.Atomics.Nouns (Objective (Objective))

makeSemanticValues [| Objective |] [BALL, CUP, FLOOR, TABLE]

ballOB :: Objective
ballOB = ball

cupOB :: Objective
cupOB = cup

floorOB :: Objective
floorOB = floor

tableOB :: Objective
tableOB = table

objectives :: HashSet Objective
objectives = fromList [ball, cup, floor, table]
