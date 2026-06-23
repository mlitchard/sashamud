module API.Types
  ( SessionId (..)
  , PlayerName (..)
  , GameCommand (..)
  , LoginResponse (..)
  , AuthenticatedUser (..)
  , PlayerJoined (..)
  , MessageFrom (..)
  , MessageTo (..)
  ) where

import SashaPrelude

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Aeson.TypeScript (derivingTypeScriptDefinition)
import Model.Core (SessionId (SessionId))
import Model.WireProtocol (WireMessage)

newtype PlayerName = PlayerName { pnText :: Text }
  deriving stock (Generic, Show)
  deriving newtype (Eq, FromJSON, Ord, ToJSON)
  deriving anyclass (NFData)

newtype GameCommand = GameCommand { unGameCommand :: Text }
  deriving stock (Generic, Show)
  deriving newtype (Eq, FromJSON, Ord, ToJSON)
  deriving anyclass (NFData)

newtype LoginResponse = LoginResponse { lrSessionId :: SessionId }
  deriving stock (Generic, Show)
  deriving newtype (Eq, FromJSON, ToJSON)
  deriving anyclass (NFData)

derivingTypeScriptDefinition ''PlayerName
derivingTypeScriptDefinition ''GameCommand
derivingTypeScriptDefinition ''LoginResponse

data AuthenticatedUser = AuthenticatedUser
  { auSessionId :: SessionId
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

data PlayerJoined = PlayerJoined
  { pjSessionId  :: SessionId
  , pjPlayerName :: PlayerName
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

data MessageFrom = MessageFrom
  { mfSessionId :: SessionId
  , mfCommand   :: GameCommand
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

data MessageTo = MessageTo
  { mtSessionId :: SessionId
  , mtMessage   :: WireMessage
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)
