module Main (main) where

import           SashaPrelude

import           DSL.Builder (WorldBuilderResult (WorldBuilderResult))
import           Model.Core (defaultGameState, initialCounters)
import           Server.Server (startServer)

main :: IO ()
main = startServer (WorldBuilderResult defaultGameState initialCounters [])
