module Server.Authentication
  ( SashaContext
  , sashaContext
  ) where

import SashaPrelude

import Data.List (lookup)
import Data.Text.Encoding (decodeUtf8)
import Network.Wai (Request, requestHeaders)
import Servant (Context (EmptyContext, (:.)), Handler)
import Servant.Server.Experimental.Auth (AuthHandler, mkAuthHandler)

type SashaContext :: Type
type SashaContext = Context '[AuthHandler Request Text]

sashaContext :: SashaContext
sashaContext = mkAuthHandler authHandler :. EmptyContext
  where
    authHandler :: Request -> Handler Text
    authHandler req =
      case lookup "Sec-WebSocket-Protocol" (requestHeaders req) of
        Nothing -> pure ""
        Just token -> pure (decodeUtf8 token)
