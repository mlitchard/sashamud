module Main (main) where

import SashaPrelude
import Server.Server (startServer)
import SashaMudWorld (gameState, possibilityGraph)

main :: IO ()
main = startServer gameState possibilityGraph
