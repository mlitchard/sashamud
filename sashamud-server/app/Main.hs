module Main (main) where

import           Control.Monad.Except (runExceptT)
import           Lobby (buildResult, worldLoadFailureText)
import           SashaPrelude
import           Server.Server (startServer)
import           System.Exit (exitFailure)

main :: IO ()
main = do
  loaded <- runExceptT buildResult
  result <- case loaded of
    Left err -> do
      hPutStrLn stderr (worldLoadFailureText err)
      exitFailure
    Right loadedResult -> pure loadedResult
  startServer result
