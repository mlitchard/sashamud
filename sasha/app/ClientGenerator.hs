module Main (main) where

import           API.TSClient (client)
import qualified Data.Text.IO as TIO
import           SashaPrelude
import           System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [outPath] -> TIO.writeFile outPath client
    _         -> hPutStrLn stderr "Usage: sasha-client-generator <output-path>"
