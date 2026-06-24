module Server.Authentication
  ( AuthenticatedUser (..)
  , SashaContext
  , sashaContext
  , authProxy
  ) where

import           SashaPrelude

import           API.Types
  ( AuthenticatedUser (AuthenticatedUser)
  , SessionId (SessionId)
  )
import           Data.List (lookup)
import           Data.Text.Encoding (decodeUtf8')
import           Network.Wai (Request, requestHeaders)
import           Servant
  ( Context (EmptyContext, (:.))
  , Handler
  , Proxy (Proxy)
  , err401
  , throwError
  )
import           Servant.Server.Experimental.Auth (AuthHandler, mkAuthHandler)

type SashaContext :: Type
type SashaContext = Context '[AuthHandler Request AuthenticatedUser]

authProxy :: Proxy '[AuthHandler Request AuthenticatedUser]
authProxy = Proxy

sashaContext :: SashaContext
sashaContext = mkAuthHandler authHandler :. EmptyContext
  where
    authHandler :: Request -> Handler AuthenticatedUser
    authHandler req =
      case lookup "Sec-WebSocket-Protocol" (requestHeaders req) of
        Nothing -> throwError err401
        Just rawSessionId -> case decodeUtf8' rawSessionId of
          Left _  -> throwError err401
          Right t -> pure (AuthenticatedUser (SessionId t))
