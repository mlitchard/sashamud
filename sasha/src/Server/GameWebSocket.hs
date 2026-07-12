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
  ( AppCtx (acInbound, acJoinChan, acPlayerMap, acSessions)
  , SessionPhase (AwaitingJoin, AwaitingSocket, InGame)
  )

gameWebSocket :: AppCtx -> AuthenticatedUser -> ([MessageFrom] -> IO ()) -> IO (Handler MessageTo)
gameWebSocket ctx (AuthenticatedUser sessionId) sendMsgs = do
  modifyMVar_ (acSessions ctx) $ \sessions ->
    case Map.lookup sessionId sessions of
      Just (AwaitingSocket name) -> do
        atomically $ writeTChan (acJoinChan ctx) (PlayerJoined sessionId name)
        pure (Map.insert sessionId (AwaitingJoin name sendMsgs) sessions)
      Just (AwaitingJoin name _) ->
        pure (Map.insert sessionId (AwaitingJoin name sendMsgs) sessions)
      Just (InGame _ gid) ->
        pure (Map.insert sessionId (InGame sendMsgs gid) sessions)
      Nothing ->
        pure sessions
  pure Handler
    { recieve = atomically . writeTChan (acInbound ctx) . Routed sessionId
    , handle = \_ -> do
        modifyMVar_ (acSessions ctx) (pure . Map.delete sessionId)
        modifyMVar_ (acPlayerMap ctx) (pure . Map.delete sessionId)
    }
