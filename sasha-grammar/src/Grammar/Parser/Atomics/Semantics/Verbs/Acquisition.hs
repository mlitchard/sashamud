{-# LANGUAGE TemplateHaskell #-}
module Grammar.Parser.Atomics.Semantics.Verbs.Acquisition
  ( getAV
  , acquisitionVerbs
  ) where

import           Data.HashSet (HashSet, fromList)
import           Grammar.Lexer (Lexeme (GET))
import           Grammar.Parser.Atomics.AtomicsTH (makeSemanticValues)
import           Grammar.Parser.Atomics.Verbs
  ( AcquisitionVerb (AcquisitionVerb)
  )

makeSemanticValues [| AcquisitionVerb |] [GET]

getAV :: AcquisitionVerb
getAV = get

acquisitionVerbs :: HashSet AcquisitionVerb
acquisitionVerbs = fromList [get]
