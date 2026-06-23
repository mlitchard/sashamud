module Server.GameWebSocket
  ( gameWebSocket
  ) where

import SashaPrelude

import API.Types (AuthenticatedUser (AuthenticatedUser), GameCommand (GameCommand), MessageFrom (MessageFrom))
import Control.Concurrent (modifyMVar_)
import Control.Concurrent.STM (atomically, writeTChan)
import Data.Map.Strict qualified as Map (delete, insert)
import Model.WireProtocol (WireMessage)
import Servant.API.WebSocket (Handler (Handler, handle, recieve))
import Server.App (AppCtx (acConnections, acInbound))

gameWebSocket :: AppCtx -> AuthenticatedUser -> ([WireMessage] -> IO ()) -> IO (Handler Text)
gameWebSocket ctx (AuthenticatedUser sessionId) sendMsgs = do
  modifyMVar_ (acConnections ctx) (pure . Map.insert sessionId sendMsgs)
  pure Handler
    { recieve = \cmd -> atomically (writeTChan (acInbound ctx) (MessageFrom sessionId (GameCommand cmd)))
    , handle = \_ -> modifyMVar_ (acConnections ctx) (pure . Map.delete sessionId)
    }
