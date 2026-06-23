module Main (main) where

import SashaPrelude
import API.TSClient (client)
import Data.Text.IO qualified as TIO
import System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [outPath] -> TIO.writeFile outPath client
    _         -> hPutStrLn stderr "Usage: sasha-client-generator <output-path>"
