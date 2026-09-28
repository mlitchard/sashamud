{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use newtype instead of data" #-}

module API.Types
  ( SessionId (..)
  , MessageTo (..)
  , Routed (..)
  , AuthenticatedUser (..)
  , DSLSource (..)
  , PlayerJoined (..)
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, ToJSON)
import           Data.Aeson.TypeScript (derivingTypeScriptDefinition)
import           Model.Account (UserPermissions)
import           Model.Core (Agent, SessionId (SessionId))
import           Model.GID (GID)
import           Model.Mid (Mid)
import           Network.WebSockets (WebSocketsData)
import           Servant.API.WebSocket (Aeson (Aeson))
import           Server.Validator (PlayerNameVAL)
#ifdef TESTING
import           Test.QuickCheck (Arbitrary)
import           Test.QuickCheck.Arbitrary.Generic (GenericArbitrary (..))
import           Test.QuickCheck.Instances.Text ()
#endif

-- | Client→server wire type.
data MessageTo = Ping
               | GameCommand Text
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, ToJSON)
  deriving (WebSocketsData)
    via Aeson MessageTo

derivingTypeScriptDefinition ''MessageTo

-- | Internal routing wrapper — pairs a SessionId with a message for TChan channels.
data Routed a = Routed SessionId a
  deriving stock (Eq, Generic, Ord, Show)

newtype DSLSource = DSLSource { unDSLSource :: Text }
  deriving stock (Generic, Show)
  deriving newtype (Eq, FromJSON, ToJSON)
  deriving anyclass (NFData)

derivingTypeScriptDefinition ''DSLSource

data AuthenticatedUser = AuthenticatedUser
  { auSessionId   :: SessionId
  , auUserId      :: Mid AuthenticatedUser
  , auPermissions :: UserPermissions
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

data PlayerJoined = PlayerJoined
  { pjSessionId  :: SessionId
  , pjPlayerName :: PlayerNameVAL
  , pjGid        :: GID Agent
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

#ifdef TESTING
deriving via (GenericArbitrary MessageTo) instance Arbitrary MessageTo
#endif
