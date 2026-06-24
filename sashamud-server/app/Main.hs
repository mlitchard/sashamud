module Main (main) where

import           SashaMudWorld (gameState, possibilityGraph)
import           SashaPrelude
import           Server.Server (startServer)

main :: IO ()
main = startServer gameState possibilityGraph
