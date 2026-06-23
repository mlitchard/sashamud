module Server.App
  ( AppCtx (..)
  , GameLog (..)
  , newAppCtx
  ) where

import SashaPrelude

import API.Types (MessageFrom, MessageTo)
import Control.Concurrent.STM (TChan, TVar, newTChanIO, newTVarIO)
import Data.Map.Strict (Map)
import Model.Core (Agent)
import Model.GID (GID)
import Server.Session (GameSessionRegistry, newGameRegistry)

data GameLog = GameLog
  { logHandle :: Handle
  }

data AppCtx = AppCtx
  { acInbound    :: TChan MessageFrom
  , acOutbound   :: TChan MessageTo
  , acPlayerMap  :: TVar (Map Text (GID Agent))
  , acNextAgentId :: TVar Int
  , acRegistry   :: GameSessionRegistry
  , acGameLog    :: GameLog
  }

newAppCtx :: GameLog -> IO AppCtx
newAppCtx logCfg = do
  inChan  <- newTChanIO
  outChan <- newTChanIO
  pMap    <- newTVarIO mempty
  nxtId   <- newTVarIO 1000
  reg     <- newGameRegistry
  pure AppCtx
    { acInbound    = inChan
    , acOutbound   = outChan
    , acPlayerMap  = pMap
    , acNextAgentId = nxtId
    , acRegistry   = reg
    , acGameLog    = logCfg
    }
