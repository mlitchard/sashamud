{-# LANGUAGE TemplateHaskell #-}
module Grammar.Parser.Atomics.Semantics.Nouns.DirectionalStimulus
  ( ballDS
  , cupDS
  , floorDS
  , tableDS
  , directionalStimuli
  ) where

import           Data.HashSet (HashSet, fromList)
import           Grammar.Lexer (Lexeme (BALL, CUP, FLOOR, TABLE))
import           Grammar.Parser.Atomics.AtomicsTH (makeSemanticValues)
import           Grammar.Parser.Atomics.Nouns
  ( DirectionalStimulus (DirectionalStimulus)
  )

makeSemanticValues [| DirectionalStimulus |] [BALL, CUP, FLOOR, TABLE]

ballDS :: DirectionalStimulus
ballDS = ball

cupDS :: DirectionalStimulus
cupDS = cup

floorDS :: DirectionalStimulus
floorDS = floor

tableDS :: DirectionalStimulus
tableDS = table

directionalStimuli :: HashSet DirectionalStimulus
directionalStimuli = fromList [ball, cup, floor, table]
