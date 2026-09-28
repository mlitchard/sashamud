{-# LANGUAGE ExplicitNamespaces #-}

module API.Routes
  ( SashaAPI
  , AuthAPI
  , StartAPI
  , CallbackAPI
  , AvailableAPI
  , DSLAPI
  , LogoutAPI
  , WebSocketAPI
  ) where

import           API.Types (AuthenticatedUser, DSLSource, MessageTo)
import           Model.Account (AuthCode, OidcState)
import           Model.Authorization (Resource (Dsl), ResourceAction (Create))
import           Model.Core (SessionId)
import           Model.WireProtocol (MessageFrom)
import           Network.HTTP.Types.Method (StdMethod (GET))
import           SashaPrelude (Text)
import           Servant.API
  ( AuthProtect
  , DeleteNoContent
  , GetNoContent
  , Header
  , Headers
  , JSON
  , NoContent
  , PostNoContent
  , QueryParam
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
import           Server.Authentication (CanDo)
import           Server.Validator (PlayerNameUNV)

type instance AuthServerData (AuthProtect SecWebSocketProtocol) = AuthenticatedUser

type StartAPI =
  "api" :> "auth" :> "start"
  :> QueryParam "name" PlayerNameUNV
  :> Verb 'GET 302 '[JSON] (Headers '[Header "Location" Text] NoContent)

type CallbackAPI =
  "api" :> "auth" :> "callback"
  :> QueryParam' '[Required, Strict] "code" AuthCode
  :> QueryParam' '[Required, Strict] "state" OidcState
  :> Verb 'GET 302 '[JSON] (Headers '[Header "Location" Text] NoContent)

type AvailableAPI =
  "api" :> "auth" :> "available"
  :> QueryParam' '[Required, Strict] "name" PlayerNameUNV
  :> GetNoContent

type AuthAPI =
       StartAPI
  :<|> CallbackAPI
  :<|> AvailableAPI

type DSLAPI =
  "api" :> "game" :> "dsl"
  :> CanDo 'Dsl 'Create
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
