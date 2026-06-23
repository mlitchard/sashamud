module Server.GameWebSocket
  ( gameWebSocket
  ) where

import SashaPrelude

import API.Types (MessageFrom (MessageFrom))
import Control.Concurrent.STM (atomically, putTMVar, writeTChan)
import Model.WireProtocol (WireMessage (SessionId))
import Servant.API.WebSocket (Handler (Handler, handle, recieve))
import Server.App (AppCtx (acInbound))
import Server.Session
  ( GameSession (gsSendMsgs)
  , GameSessionRegistry
  , lookupGameSession
  , removeGameSession
  )

gameWebSocket :: AppCtx -> GameSessionRegistry -> Text -> ([WireMessage] -> IO ()) -> IO (Handler Text)
gameWebSocket ctx registry sessionId sendMsgs = do
  mSession <- lookupGameSession registry sessionId
  case mSession of
    Nothing -> pure Handler
      { recieve = \_ -> pure ()
      , handle = \_ -> pure ()
      }
    Just gs -> do
      atomically (putTMVar (gsSendMsgs gs) sendMsgs)
      sendMsgs [SessionId sessionId]
      pure Handler
        { recieve = \cmd -> atomically (writeTChan (acInbound ctx) (MessageFrom sessionId cmd))
        , handle = \_ -> removeGameSession registry sessionId
        }
