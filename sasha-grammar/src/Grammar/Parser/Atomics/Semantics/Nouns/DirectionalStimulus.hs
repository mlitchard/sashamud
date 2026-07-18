{-# LANGUAGE TemplateHaskell #-}
module Grammar.Parser.Atomics.Semantics.Nouns.DirectionalStimulus
  ( ballDS
  , floorDS
  , directionalStimuli
  ) where

import           Data.HashSet (HashSet, fromList)
import           Grammar.Lexer (Lexeme (BALL, FLOOR))
import           Grammar.Parser.Atomics.AtomicsTH (makeSemanticValues)
import           Grammar.Parser.Atomics.Nouns
  ( DirectionalStimulus (DirectionalStimulus)
  )

makeSemanticValues [| DirectionalStimulus |] [BALL, FLOOR]

ballDS :: DirectionalStimulus
ballDS = ball

floorDS :: DirectionalStimulus
floorDS = floor

directionalStimuli :: HashSet DirectionalStimulus
directionalStimuli = fromList [ball, floor]
