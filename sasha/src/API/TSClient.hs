{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module API.TSClient (client) where

import           SashaPrelude

import           API.Routes (SashaAPI)
import           API.Types (LoginResponse, MessageTo, SessionId)
import           GHC.TypeLits (KnownSymbol)
import           Model.RichText (RichText, StyledSpan, TextColor, TextStyle)
import           Model.WireProtocol (MessageFrom)
import           Servant (AuthProtect, Header', JSON, ReqBody, type (:>))
import           Servant.Client.TypeScript (Fletch (..), TSDef, tsClient)
import           Server.Validator (PlayerNameUNV, PlayerNameVAL, ValidatedBody)

instance (Fletch xs, KnownSymbol s) => Fletch (AuthProtect s :> xs) where
  argBits = argBits @(Header' '[JSON] s Text :> xs)
  returnType = returnType @(Header' '[JSON] s Text :> xs)
  protocol = protocol @(Header' '[JSON] s Text :> xs)

instance (Fletch (ReqBody list unv :> xs)) => Fletch (ValidatedBody list unv val :> xs) where
  argBits = argBits @(ReqBody list unv :> xs)
  returnType = returnType @(ReqBody list unv :> xs)
  protocol = protocol @(ReqBody list unv :> xs)

client :: Text
client = tsClient
  @'[ TSDef SessionId
    , TSDef MessageTo
    , TSDef PlayerNameUNV
    , TSDef PlayerNameVAL
    , TSDef LoginResponse
    , TSDef TextColor
    , TSDef TextStyle
    , TSDef StyledSpan
    , TSDef RichText
    , TSDef MessageFrom
    ] @SashaAPI
