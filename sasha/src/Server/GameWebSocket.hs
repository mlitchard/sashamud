module Server.GameWebSocket
  ( gameWebSocket
  ) where

import           SashaPrelude

import           API.Types
  ( AuthenticatedUser (AuthenticatedUser)
  , MessageTo
  , PlayerJoined (PlayerJoined)
  , Routed (Routed)
  )
import           Control.Concurrent (modifyMVar_)
import           Control.Concurrent.STM (atomically, writeTChan)
import qualified Data.Map.Strict as Map (delete, insert, lookup)
import           Model.WireProtocol (MessageFrom)
import           Servant.API.WebSocket (Handler (Handler, handle, recieve))
import           Server.App
  ( AppCtx (acInbound, acJoinChan, acSessions)
  , SessionPhase (SessionPhase)
  , SessionState (AwaitingJoin, AwaitingSocket, InGame)
  )

gameWebSocket :: AppCtx -> AuthenticatedUser -> ([MessageFrom] -> IO ()) -> IO (Handler MessageTo)
gameWebSocket ctx (AuthenticatedUser sessionId _ _) sendMsgs = do
  modifyMVar_ (acSessions ctx) $ \sessions ->
    case Map.lookup sessionId sessions of
      Just (SessionPhase name AwaitingSocket) -> do
        atomically $ writeTChan (acJoinChan ctx) (PlayerJoined sessionId name)
        pure (Map.insert sessionId (SessionPhase name (AwaitingJoin sendMsgs)) sessions)
      Just (SessionPhase name (AwaitingJoin _)) ->
        pure (Map.insert sessionId (SessionPhase name (AwaitingJoin sendMsgs)) sessions)
      Just (SessionPhase name (InGame _ gid)) ->
        pure (Map.insert sessionId (SessionPhase name (InGame sendMsgs gid)) sessions)
      Nothing ->
        pure sessions
  pure Handler
    { recieve = atomically . writeTChan (acInbound ctx) . Routed sessionId
    , handle = \_ ->
        modifyMVar_ (acSessions ctx) (pure . Map.delete sessionId)
    }
