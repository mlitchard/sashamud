module Main (main) where

import           SashaMudWorld (gameState)
import           SashaPrelude
import           Server.Server (startServer)

main :: IO ()
main = startServer gameState
