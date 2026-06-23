{-# OPTIONS_GHC -fsimpl-tick-factor=200 #-}

module Engine.Simulation.EffectNetwork
  ( RhineM
  , gameLoop
  ) where

import SashaPrelude

import API.Types (MessageFrom, MessageTo (MessageTo))
import Control.Concurrent.STM (TChan, atomically, readTVarIO, tryReadTChan, tryReadTMVar, writeTChan)
import Control.Monad.Trans.Accum (AccumT, runAccumT)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Reader (ReaderT (runReaderT), ask)
import Data.Map.Strict (keys)
import Data.Monoid (Last (Last))
import Engine.Simulation.Clocks (HeartbeatTick, PlayerTick)
import FRP.Rhine (ClSF, IOClock, ParallelClock, Rhine, constMCl, flow, ioClock, waitClock, (@@), (|@|))
import Model.Core (GameState, PossibilityGraph)
import Model.WireProtocol (WireMessage (SystemMessage))
import Server.App (AppCtx (acInbound, acOutbound, acPlayerMap, acRegistry))
import Server.Session
  ( GameSession (gsSendMsgs)
  , GameSessionRegistry
  , lookupGameSession
  )

-- RhineM: the reactive monad stack.
-- Follows IX.Reactive.EventNetwork: pure game functions lifted into
-- a reactive dataflow graph, with IO at the edges.
--
-- Each tick builds the next GameState and sends update messages
-- (like IX: eGameState <@ eTick, reactimate $ writeOut <$> eGameState).
--
-- Last GameState in AccumT (look to read, add to update).
-- PossibilityGraph in ReaderT (immutable after DSL construction).
-- AppCtx in ReaderT (server concerns: channels, sessions, registry).
-- IO at the base.

type RhineM :: Type -> Type
type RhineM =
  AccumT (Last GameState)
    (ReaderT PossibilityGraph
      (ReaderT AppCtx IO))

-- The DSL produces the initial GameState. The game loop seeds
-- the AccumT accumulator with it (like IX seeds accumB with InitMaps).
-- flow runs the Rhine event network forever.
gameLoop :: AppCtx -> GameState -> PossibilityGraph -> IO ()
gameLoop ctx gs pg =
  void (runReaderT
    (runReaderT
      (runAccumT (flow rhinePipeline) (Last (Just gs)))
      pg)
    ctx)

rhinePipeline :: Rhine RhineM (ParallelClock (IOClock RhineM HeartbeatTick) (IOClock RhineM PlayerTick)) () ()
rhinePipeline =
      heartbeatSF @@ ioClock (waitClock :: HeartbeatTick)
  |@| playerTickSF @@ ioClock (waitClock :: PlayerTick)

heartbeatSF :: ClSF RhineM (IOClock RhineM HeartbeatTick) () ()
heartbeatSF = constMCl $ do
  appCtx <- lift (lift ask)
  liftIO $ do
    pMap <- readTVarIO (acPlayerMap appCtx)
    let msg = SystemMessage "*** heartbeat"
    atomically $
      mapM_ (\sid -> writeTChan (acOutbound appCtx) (MessageTo sid msg))
        (keys pMap)

playerTickSF :: ClSF RhineM (IOClock RhineM PlayerTick) () ()
playerTickSF = constMCl $ do
  appCtx <- lift (lift ask)
  liftIO $ do
    drainInbound (acInbound appCtx)
    drainOutbound (acOutbound appCtx) (acRegistry appCtx)

drainInbound :: TChan MessageFrom -> IO ()
drainInbound chan = do
  mMsg <- atomically (tryReadTChan chan)
  case mMsg of
    Nothing  -> pure ()
    Just msg -> seq msg (drainInbound chan)

drainOutbound :: TChan MessageTo -> GameSessionRegistry -> IO ()
drainOutbound chan registry = do
  mMsg <- atomically (tryReadTChan chan)
  case mMsg of
    Nothing -> pure ()
    Just (MessageTo sid wireMsg) -> do
      mSession <- lookupGameSession registry sid
      case mSession of
        Nothing -> pure ()
        Just session -> do
          mSend <- atomically (tryReadTMVar (gsSendMsgs session))
          case mSend of
            Nothing -> pure ()
            Just sendMsgs -> sendMsgs [wireMsg]
      drainOutbound chan registry
