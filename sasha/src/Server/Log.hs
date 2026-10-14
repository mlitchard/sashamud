module Server.Log
  ( LogEntry (..)
  , writeLog
  ) where

import           SashaPrelude

import           DSL.Builder (WorldBuilderError, WorldChange)
import           Model.Core (SessionId)
import           Network.Wai.Handler.Warp (Port)
import           Server.App (GameLog (..))
import           Server.Validator (PlayerNameVAL)
import           System.IO (hPrint)

data LogEntry = Heartbeat
              | PlayerLogin PlayerNameVAL
              | PlayerDisconnect PlayerNameVAL
              | SendDropped SessionId
              | SendError SessionId Text
              | SendFailed SessionId
              | ServerStart Port
              | DSLBuildFailed WorldBuilderError
              | DSLBuildSucceeded [WorldChange]
  deriving stock (Show)

writeLog :: GameLog -> LogEntry -> IO ()
writeLog gl = hPrint (logHandle gl)
