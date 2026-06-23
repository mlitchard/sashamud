module Server.Log
  ( LogEntry (..)
  , writeLog
  ) where

import SashaPrelude

import Server.App (GameLog (..))

data LogEntry
  = Heartbeat
  | PlayerLogin Text
  | PlayerDisconnect Text
  | ServerStart Int
  deriving stock (Show)

writeLog :: GameLog -> LogEntry -> IO ()
writeLog gl entry =
  hPutStrLn (logHandle gl) (show entry)
