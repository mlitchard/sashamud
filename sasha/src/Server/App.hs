module Server.App
  ( AppCtx (..)
  , AppM (..)
  , GameLog (..)
  , newAppCtx
  ) where

import           SashaPrelude

import           API.Types
  ( MessageFrom
  , MessageTo
  , PlayerJoined
  , PlayerName
  , SessionId
  )
import           Control.Concurrent (MVar, newMVar)
import           Control.Concurrent.STM (TChan, newTChanIO)
import           Control.Monad.Except (MonadError)
import           Control.Monad.Reader (MonadReader, ReaderT)
import           Data.Map.Strict (Map)
import           Model.Core (Agent)
import           Model.GID (GID)
import           Model.WireProtocol (WireMessage)
import           Servant (Handler)
import           Servant.Server (ServerError)

data GameLog = GameLog
  { logHandle :: Handle
  }

newtype AppM a = AppM { unAppM :: ReaderT AppCtx Handler a }
  deriving newtype
    ( Applicative
    , Functor
    , Monad
    , MonadError ServerError
    , MonadIO
    , MonadReader AppCtx
    )

data AppCtx = AppCtx
  { acInbound      :: TChan MessageFrom
  , acOutbound     :: TChan MessageTo
  , acJoinChan     :: TChan PlayerJoined
  , acConnections  :: MVar (Map SessionId ([WireMessage] -> IO ()))
  , acPlayerMap    :: MVar (Map SessionId (GID Agent))
  , acKnownPlayers :: MVar (Map PlayerName (GID Agent))
  , acGameLog      :: GameLog
  }

newAppCtx :: GameLog -> IO AppCtx
newAppCtx logCfg = do
  inChan   <- newTChanIO
  outChan  <- newTChanIO
  joinChan <- newTChanIO
  conns    <- newMVar mempty
  pMap     <- newMVar mempty
  known    <- newMVar mempty
  pure AppCtx
    { acInbound      = inChan
    , acOutbound     = outChan
    , acJoinChan     = joinChan
    , acConnections  = conns
    , acPlayerMap    = pMap
    , acKnownPlayers = known
    , acGameLog      = logCfg
    }
