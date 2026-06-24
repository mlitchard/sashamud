{-# LANGUAGE ExplicitNamespaces #-}

module API.Routes
  ( SashaAPI
  , LoginAPI
  , LogoutAPI
  , WebSocketAPI
  ) where

import           SashaPrelude

import           API.Types (AuthenticatedUser, LoginResponse)
import           Model.Core (SessionId)
import           Model.WireProtocol (WireMessage)
import           Servant.API
  ( AuthProtect
  , DeleteNoContent
  , JSON
  , Post
  , ReqBody
  , type (:<|>)
  , type (:>)
  )
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

type LogoutAPI =
  "api" :> "game" :> "logout"
  :> ReqBody '[JSON] SessionId
  :> DeleteNoContent

type WebSocketAPI =
  "ws" :> "game"
  :> AuthProtect SecWebSocketProtocol
  :> TypedWebSocket 'Text Text WireMessage

type SashaAPI =
       LoginAPI
  :<|> LogoutAPI
  :<|> WebSocketAPI
