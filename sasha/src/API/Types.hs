module API.Types
  ( PlayerName (..)
  , LoginResponse (..)
  , PlayerJoined (..)
  , MessageFrom (..)
  , MessageTo (..)
  ) where

import SashaPrelude

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Aeson.TypeScript (derivingTypeScriptDefinition)
import Model.Core (Agent)
import Model.GID (GID)
import Model.WireProtocol (WireMessage)

newtype PlayerName = PlayerName { pnText :: Text }
  deriving stock (Generic, Show)
  deriving newtype (Eq, FromJSON, ToJSON)
  deriving anyclass (NFData)

newtype LoginResponse = LoginResponse { lrSessionId :: Text }
  deriving stock (Generic, Show)
  deriving newtype (Eq, FromJSON, ToJSON)
  deriving anyclass (NFData)

derivingTypeScriptDefinition ''PlayerName
derivingTypeScriptDefinition ''LoginResponse

data PlayerJoined = PlayerJoined
  { pjSessionId  :: Text
  , pjAgentGid   :: GID Agent
  , pjPlayerName :: Text
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

data MessageFrom = MessageFrom
  { mfSessionId :: Text
  , mfCommand   :: Text
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

data MessageTo = MessageTo
  { mtSessionId :: Text
  , mtMessage   :: WireMessage
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)
