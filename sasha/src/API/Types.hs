module API.Types
  ( PlayerName (..)
  , LoginResponse (..)
  , MessageFrom (..)
  , MessageTo (..)
  ) where

import SashaPrelude

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Aeson.TypeScript (derivingTypeScriptDefinition)
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
