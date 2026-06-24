module Model.WireProtocol
  ( WireMessage (..)
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, ToJSON)
import           Data.Aeson.TypeScript (derivingTypeScriptDefinition)
import           Data.Map.Strict (Map)
import           Model.Core (SessionId)
import           Model.RichText (RichText)

-- | All constructors exist from commit 1. Only SystemMessage carries
-- content in commit 1 (heartbeats). SessionAck sent on WebSocket connect.
data WireMessage = SessionAck SessionId
                 | GameNarration [RichText]
                 | CommandResponse [RichText]
                 | ChatMessage Text
                 | SystemMessage Text
                 | AnalysisData (Map Text [RichText])
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

derivingTypeScriptDefinition ''WireMessage
