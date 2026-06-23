module Server.Log
  ( LogEntry (..)
  , writeLog
  ) where

import SashaPrelude

import API.Types (PlayerName)
import Network.Wai.Handler.Warp (Port)
import Server.App (GameLog (..))

data LogEntry
  = Heartbeat
  | PlayerLogin PlayerName
  | PlayerDisconnect PlayerName
  | ServerStart Port
  deriving stock (Show)

writeLog :: GameLog -> LogEntry -> IO ()
writeLog gl entry =
  hPutStrLn (logHandle gl) (show entry)
