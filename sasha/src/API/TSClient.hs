{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module API.TSClient (client) where

import           SashaPrelude

import           API.Routes (SashaAPI)
import           API.Types (DSLSource, MessageTo, SessionId)
import           GHC.TypeLits (KnownSymbol)
import           Model.Core (Narration)
import           Model.RichText (RichText, StyledSpan, TextColor, TextStyle)
import           Model.WireProtocol (AnalysisViewport, MessageFrom)
import           Servant (AuthProtect, Header', JSON, ReqBody, type (:>))
import           Servant.Client.TypeScript (Fletch (..), TSDef, tsClient)
import           Server.Authentication (CanDo)
import           Server.Validator (PlayerNameUNV, PlayerNameVAL, ValidatedBody)

instance (Fletch xs, KnownSymbol s) => Fletch (AuthProtect s :> xs) where
  argBits = argBits @(Header' '[JSON] s Text :> xs)
  returnType = returnType @(Header' '[JSON] s Text :> xs)
  protocol = protocol @(Header' '[JSON] s Text :> xs)

instance (Fletch (AuthProtect "BEARER" :> xs)) => Fletch (CanDo a :> xs) where
  argBits = argBits @(AuthProtect "BEARER" :> xs)
  returnType = returnType @(AuthProtect "BEARER" :> xs)
  protocol = protocol @(AuthProtect "BEARER" :> xs)

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
    , TSDef DSLSource
    , TSDef TextColor
    , TSDef TextStyle
    , TSDef StyledSpan
    , TSDef RichText
    , TSDef Narration
    , TSDef AnalysisViewport
    , TSDef MessageFrom
    ] @SashaAPI
