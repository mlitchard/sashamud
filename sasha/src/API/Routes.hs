{-# LANGUAGE ExplicitNamespaces #-}

module API.Routes
  ( SashaAPI
  , AuthAPI
  , StartAPI
  , CallbackAPI
  , DSLAPI
  , LogoutAPI
  , WebSocketAPI
  ) where

import           API.Types (AuthenticatedUser, DSLSource, MessageTo)
import           Model.Account (AuthCode, OidcState)
import           Model.Core (SessionId)
import           Model.WireProtocol (MessageFrom)
import           Network.HTTP.Types.Method (StdMethod (GET))
import           SashaPrelude (Text)
import           Servant.API
  ( AuthProtect
  , DeleteNoContent
  , Header
  , Headers
  , JSON
  , NoContent
  , PostNoContent
  , QueryParam'
  , ReqBody
  , Verb
  , type (:<|>)
  , type (:>)
  )
import           Servant.API.Modifiers (Required, Strict)
import           Servant.API.WebSocket
  ( MsgType (Text)
  , SecWebSocketProtocol
  , TypedWebSocket
  )
import           Servant.Server.Experimental.Auth (AuthServerData)

type instance AuthServerData (AuthProtect SecWebSocketProtocol) = AuthenticatedUser

type StartAPI =
  "api" :> "auth" :> "start"
  :> Verb 'GET 302 '[JSON] (Headers '[Header "Location" Text] NoContent)

type CallbackAPI =
  "api" :> "auth" :> "callback"
  :> QueryParam' '[Required, Strict] "code" AuthCode
  :> QueryParam' '[Required, Strict] "state" OidcState
  :> Verb 'GET 302 '[JSON] (Headers '[Header "Location" Text] NoContent)

type AuthAPI =
       StartAPI
  :<|> CallbackAPI

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
       LogoutAPI
  :<|> WebSocketAPI
  :<|> DSLAPI
