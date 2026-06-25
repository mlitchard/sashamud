module Server.GameWebSocket
  ( gameWebSocket
  ) where

import           SashaPrelude

import           API.Types
  ( AuthenticatedUser (AuthenticatedUser)
  , MessageTo
  , Routed (Routed)
  )
import           Control.Concurrent (modifyMVar_)
import           Control.Concurrent.STM (atomically, writeTChan)
import qualified Data.Map.Strict as Map (delete, insert)
import           Model.WireProtocol (MessageFrom)
import           Servant.API.WebSocket (Handler (Handler, handle, recieve))
import           Server.App (AppCtx (acConnections, acInbound, acPlayerMap))

gameWebSocket :: AppCtx -> AuthenticatedUser -> ([MessageFrom] -> IO ()) -> IO (Handler MessageTo)
gameWebSocket ctx (AuthenticatedUser sessionId) sendMsgs = do
  modifyMVar_ (acConnections ctx) (pure . Map.insert sessionId sendMsgs)
  pure Handler
    { recieve = atomically . writeTChan (acInbound ctx) . Routed sessionId
    , handle = \_ -> do
        modifyMVar_ (acConnections ctx) (pure . Map.delete sessionId)
        modifyMVar_ (acPlayerMap ctx) (pure . Map.delete sessionId)
    }
