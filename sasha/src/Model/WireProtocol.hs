{-# OPTIONS_GHC -fconstraint-solver-iterations=10 #-}

module Model.WireProtocol
  ( AnalysisViewport (..)
  , MessageFrom (..)
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, FromJSONKey, ToJSON, ToJSONKey)
import           Data.Aeson.TypeScript (derivingTypeScriptDefinition)
import           Data.Map.Strict (Map)
import           Model.Core (Narration, SessionId)
import           Model.RichText (RichText)
import           Network.WebSockets (WebSocketsData)
import           Servant.API.WebSocket (Aeson (Aeson))
#ifdef TESTING
import           Test.QuickCheck (Arbitrary)
import           Test.QuickCheck.Arbitrary.Generic (GenericArbitrary (..))
import           Test.QuickCheck.Instances.Text ()
#endif

data AnalysisViewport
  = Parser
  | State
  | Meta
  | Graphics
  | GameMap
  deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, FromJSONKey, NFData, ToJSON, ToJSONKey)

-- | All constructors exist from commit 1. Only SystemMessage carries
-- content in commit 1 (heartbeats). SessionAck sent on WebSocket connect.
data MessageFrom = SessionAck SessionId
                 | GameNarration Narration
                 | CommandResponse [RichText]
                 | ChatMessage Text
                 | SystemMessage Text
                 | Pong
                 | AnalysisData (Map AnalysisViewport [RichText])
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)
  deriving (WebSocketsData)
    via Aeson MessageFrom

derivingTypeScriptDefinition ''AnalysisViewport
derivingTypeScriptDefinition ''MessageFrom

#ifdef TESTING
deriving via (GenericArbitrary AnalysisViewport) instance Arbitrary AnalysisViewport
deriving via (GenericArbitrary MessageFrom) instance Arbitrary MessageFrom
#endif
