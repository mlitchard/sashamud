{-# LANGUAGE ExplicitNamespaces #-}

module API.Routes
  ( SashaAPI
  , LoginAPI
  , DSLAPI
  , LogoutAPI
  , WebSocketAPI
  ) where

import           API.Types
  ( AuthenticatedUser
  , DSLSource
  , LoginResponse
  , MessageTo
  )
import           Model.Core (SessionId)
import           Model.WireProtocol (MessageFrom)
import           Servant.API
  ( AuthProtect
  , DeleteNoContent
  , JSON
  , Post
  , PostNoContent
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

type DSLAPI =
  "api" :> "game" :> "dsl"
  :> AuthProtect SecWebSocketProtocol
  :> ReqBody '[JSON] DSLSource
  :> PostNoContent

type LogoutAPI =
  "api" :> "game" :> "logout"
  :> ReqBody '[JSON] SessionId
  :> DeleteNoContent

type WebSocketAPI =
  "ws" :> "game"
  :> AuthProtect SecWebSocketProtocol
  :> TypedWebSocket 'Text MessageTo MessageFrom

type SashaAPI =
       LoginAPI
  :<|> LogoutAPI
  :<|> WebSocketAPI
  :<|> DSLAPI
