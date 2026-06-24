module Server.Log
  ( LogEntry (..)
  , writeLog
  ) where

import           SashaPrelude

import           Network.Wai.Handler.Warp (Port)
import           Server.App (GameLog (..))
import           Server.Validator (PlayerNameVAL)
import           System.IO (hPrint)

data LogEntry = Heartbeat
              | PlayerLogin PlayerNameVAL
              | PlayerDisconnect PlayerNameVAL
              | ServerStart Port
  deriving stock (Show)

writeLog :: GameLog -> LogEntry -> IO ()
writeLog gl = hPrint (logHandle gl)
