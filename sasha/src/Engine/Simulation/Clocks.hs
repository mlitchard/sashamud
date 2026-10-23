module Engine.Simulation.Clocks
  ( DSLTick
  , HeartbeatTick
  , PlayerTick
  ) where

import           SashaPrelude

import           FRP.Rhine (Millisecond)

-- | Heartbeat every 5 seconds.
type HeartbeatTick :: Type
type HeartbeatTick = Millisecond 5000

-- | Player tick every 1 second.
type PlayerTick :: Type
type PlayerTick = Millisecond 1000

-- | DSL submission tick every 5 seconds.
type DSLTick :: Type
type DSLTick = Millisecond 5000
