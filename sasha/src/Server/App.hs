{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use newtype instead of data" #-}

module Server.App
  ( AppCtx (..)
  , AppM (..)
  , BuilderCounters (BuilderCounters)
  , GameLog (..)
  , PInt
  , SessionPhase (SessionPhase)
  , SessionState (AwaitingSocket, AwaitingJoin, InGame)
  , firstPlayerId
  , initialCounters
  , newAppCtx
  , nextDirectionalStimulusId
  , nextImplicitStimulusId
  , nextObjectId
  , nextSceneId
  , nextWitnessId
  , sessionGid
  , sessionPlayerName
  , sessionSend
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
import           DSL.Model.EDSL.SashaLambdaDSL (SashaLambdaDSL)
import           Lens.Micro.Platform (makeLenses)
import           Model.Core (Agent, GameState)
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
firstPlayerId = PInt 0

data BuilderCounters = BuilderCounters
  { _nextSceneId               :: PInt
  , _nextObjectId              :: PInt
  , _nextImplicitStimulusId    :: PInt
  , _nextDirectionalStimulusId :: PInt
  , _nextWitnessId             :: PInt
  }

initialCounters :: BuilderCounters
initialCounters = BuilderCounters
  { _nextSceneId               = firstPlayerId
  , _nextObjectId              = firstPlayerId
  , _nextImplicitStimulusId    = firstPlayerId
  , _nextDirectionalStimulusId = firstPlayerId
  , _nextWitnessId             = firstPlayerId
  }

data SessionPhase = SessionPhase PlayerNameVAL SessionState

data SessionState = AwaitingSocket
                  | AwaitingJoin ([MessageFrom] -> IO ())
                  | InGame ([MessageFrom] -> IO ()) (GID Agent)

sessionPlayerName :: SessionPhase -> PlayerNameVAL
sessionPlayerName (SessionPhase name _) = name

sessionGid :: SessionPhase -> Maybe (GID Agent)
sessionGid (SessionPhase _ AwaitingSocket)   = Nothing
sessionGid (SessionPhase _ (AwaitingJoin _)) = Nothing
sessionGid (SessionPhase _ (InGame _ gid))   = Just gid

sessionSend :: SessionPhase -> Maybe ([MessageFrom] -> IO ())
sessionSend (SessionPhase _ AwaitingSocket)      = Nothing
sessionSend (SessionPhase _ (AwaitingJoin send)) = Just send
sessionSend (SessionPhase _ (InGame send _))     = Just send

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
  { acInbound         :: TChan (Routed MessageTo)
  , acOutbound        :: TChan (Routed MessageFrom)
  , acJoinChan        :: TChan PlayerJoined
  , acDSLChan         :: TChan (SashaLambdaDSL GameState)
  , acSessions        :: MVar (Map SessionId SessionPhase)
  , acKnownPlayers    :: MVar (Map PlayerNameVAL (GID Agent))
  , acNextAgentId     :: IORef PInt
  , acBuilderCounters :: IORef BuilderCounters
  , acGameLog         :: GameLog
  }

newAppCtx :: GameLog -> BuilderCounters -> IO AppCtx
newAppCtx logCfg counters = do
  inChan   <- newTChanIO
  outChan  <- newTChanIO
  joinChan <- newTChanIO
  dslChan  <- newTChanIO
  sessions <- newMVar mempty
  known    <- newMVar mempty
  nextId   <- newIORef firstPlayerId
  builderCounters <- newIORef counters
  pure AppCtx
    { acInbound      = inChan
    , acOutbound     = outChan
    , acJoinChan     = joinChan
    , acDSLChan      = dslChan
    , acSessions     = sessions
    , acKnownPlayers = known
    , acNextAgentId  = nextId
    , acBuilderCounters = builderCounters
    , acGameLog      = logCfg
    }

makeLenses ''BuilderCounters
