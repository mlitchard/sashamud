{-# LANGUAGE ExplicitNamespaces #-}

module API.Routes
  ( SashaAPI
  , LoginAPI
  , WebSocketAPI
  ) where

import SashaPrelude

import API.Types (LoginResponse, PlayerName)
import Model.WireProtocol (WireMessage)
import Servant.API
  ( AuthProtect
  , JSON
  , Post
  , ReqBody
  , type (:<|>)
  , type (:>)
  )
import Servant.API.WebSocket (MsgType (Text), SecWebSocketProtocol, TypedWebSocket)
import Servant.Server.Experimental.Auth (AuthServerData)

type instance AuthServerData (AuthProtect SecWebSocketProtocol) = Text

type LoginAPI =
  "api" :> "game" :> "login"
  :> ReqBody '[JSON] PlayerName
  :> Post '[JSON] LoginResponse

type WebSocketAPI =
  "ws" :> "game"
  :> AuthProtect SecWebSocketProtocol
  :> TypedWebSocket 'Text Text WireMessage

type SashaAPI =
       LoginAPI
  :<|> WebSocketAPI
