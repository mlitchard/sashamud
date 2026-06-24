{-# LANGUAGE ExplicitNamespaces #-}

module API.Routes
  ( SashaAPI
  , LoginAPI
  , WebSocketAPI
  ) where

import           SashaPrelude

import           API.Types (AuthenticatedUser, LoginResponse)
import           Model.WireProtocol (WireMessage)
import           Servant.API (AuthProtect, JSON, Post, type (:<|>), type (:>))
import           Servant.API.WebSocket
  ( MsgType (Text)
  , SecWebSocketProtocol
  , TypedWebSocket
  )
import           Servant.Server.Experimental.Auth (AuthServerData)
import           Server.Validator (PlayerNameUNV, PlayerNameVAL, ValidatedBody)

type instance AuthServerData (AuthProtect SecWebSocketProtocol) = AuthenticatedUser

type LoginAPI =
  "api" :> "game" :> "login"
  :> ValidatedBody '[JSON] PlayerNameUNV PlayerNameVAL
  :> Post '[JSON] LoginResponse

type WebSocketAPI =
  "ws" :> "game"
  :> AuthProtect SecWebSocketProtocol
  :> TypedWebSocket 'Text Text WireMessage

type SashaAPI =
       LoginAPI
  :<|> WebSocketAPI
