{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use newtype instead of data" #-}

module Server.App
  ( AppCtx (..)
  , AppM (..)
  , GameLog (..)
  , PInt
  , firstPlayerId
  , newAppCtx
  , succPInt
  , unPInt
  ) where

import           SashaPrelude

import           API.Types (MessageTo, PlayerJoined, Routed, SessionId)
import           Control.Concurrent (MVar, newMVar)
import           Control.Concurrent.STM (TChan, newTChanIO)
import           Control.Monad.Except (MonadError)
import           Control.Monad.Reader (MonadReader, ReaderT)
import           Data.IORef (IORef, newIORef)
import           Data.Map.Strict (Map)
import           Model.Core (Agent)
import           Model.GID (GID)
import           Model.WireProtocol (MessageFrom)
import           Servant (Handler)
import           Servant.Server (ServerError)
import           Server.Validator (PlayerNameVAL)

data GameLog = GameLog
  { logHandle :: Handle
  }

newtype PInt = PInt Int
  deriving stock (Eq, Ord, Show)

succPInt :: PInt -> PInt
succPInt (PInt n) = PInt (n + 1)

unPInt :: PInt -> Int
unPInt (PInt n) = n

firstPlayerId :: PInt
firstPlayerId = PInt 1000

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
  { acInbound      :: TChan (Routed MessageTo)
  , acOutbound     :: TChan (Routed MessageFrom)
  , acJoinChan     :: TChan PlayerJoined
  , acConnections  :: MVar (Map SessionId ([MessageFrom] -> IO ()))
  , acPlayerMap    :: MVar (Map SessionId (GID Agent))
  , acKnownPlayers :: MVar (Map PlayerNameVAL (GID Agent))
  , acNextAgentId  :: IORef PInt
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
  nextId   <- newIORef firstPlayerId
  pure AppCtx
    { acInbound      = inChan
    , acOutbound     = outChan
    , acJoinChan     = joinChan
    , acConnections  = conns
    , acPlayerMap    = pMap
    , acKnownPlayers = known
    , acNextAgentId  = nextId
    , acGameLog      = logCfg
    }
