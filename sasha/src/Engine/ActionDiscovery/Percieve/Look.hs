module Engine.ActionDiscovery.Percieve.Look
  ( manageImplicitStimulusProcess
  ) where

import           Data.Functor.Identity (Identity)
import           Engine.ActionDiscovery.Instances ()
import           Engine.ActionDiscovery.Protocol
  ( ActionProtocol (runActionProtocol)
  )
import           Grammar.Parser.Atomics.Verbs (ImplicitStimulusVerb)
import           Model.Core (Agent, GameComputation, ImplicitStimulusF)
import           Model.GID (GID)

-- | Manage implicit stimulus (e.g., "look" with no target)
-- Uses the ActionProtocol instance for actor + scene coordination
manageImplicitStimulusProcess :: GID Agent
                              -> ImplicitStimulusVerb
                              -> GameComputation Identity ()
manageImplicitStimulusProcess = runActionProtocol @ImplicitStimulusF
