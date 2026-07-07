{-# OPTIONS_GHC -fconstraint-solver-iterations=10 #-}

module Model.WireProtocol
  ( MessageFrom (..)
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, ToJSON)
import           Data.Aeson.TypeScript (derivingTypeScriptDefinition)
import           Data.Map.Strict (Map)
import           Model.Core (SessionId)
import           Model.RichText (RichText)
import           Network.WebSockets (WebSocketsData)
import           Servant.API.WebSocket (Aeson (Aeson))
#ifdef TESTING
import           Test.QuickCheck (Arbitrary)
import           Test.QuickCheck.Arbitrary.Generic (GenericArbitrary (..))
import           Test.QuickCheck.Instances.Text ()
#endif

-- | All constructors exist from commit 1. Only SystemMessage carries
-- content in commit 1 (heartbeats). SessionAck sent on WebSocket connect.
data MessageFrom = SessionAck SessionId
                 | GameNarration [RichText]
                 | CommandResponse [RichText]
                 | ChatMessage Text
                 | SystemMessage Text
                 | Pong
                 | AnalysisData (Map Text [RichText])
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)
  deriving (WebSocketsData)
    via Aeson MessageFrom

derivingTypeScriptDefinition ''MessageFrom

#ifdef TESTING
deriving via (GenericArbitrary MessageFrom) instance Arbitrary MessageFrom
#endif
