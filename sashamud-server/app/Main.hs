module Main (main) where

import           SashaMudWorld (buildResult)
import           SashaPrelude
import           Server.Server (startServer)

main :: IO ()
main = startServer buildResult
