{-# LANGUAGE DataKinds #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module API.TSClient (client) where

import           SashaPrelude

import           API.Routes (SashaAPI)
import           API.Types (GameCommand, LoginResponse, PlayerName, SessionId)
import           GHC.TypeLits (KnownSymbol)
import           Model.RichText (RichText, StyledSpan, TextColor, TextStyle)
import           Model.WireProtocol (WireMessage)
import           Servant (AuthProtect, Header', JSON, type (:>))
import           Servant.Client.TypeScript (Fletch (..), TSDef, tsClient)

instance (Fletch xs, KnownSymbol s) => Fletch (AuthProtect s :> xs) where
  argBits = argBits @(Header' '[JSON] s Text :> xs)
  returnType = returnType @(Header' '[JSON] s Text :> xs)
  protocol = protocol @(Header' '[JSON] s Text :> xs)

client :: Text
client = tsClient
  @'[ TSDef TextColor
    , TSDef TextStyle
    , TSDef StyledSpan
    , TSDef RichText
    , TSDef WireMessage
    , TSDef SessionId
    , TSDef GameCommand
    , TSDef PlayerName
    , TSDef LoginResponse
    ] @SashaAPI
