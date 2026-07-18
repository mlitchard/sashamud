module Engine.ActionDiscovery.Percieve.Look
  ( manageDirectionalStimulusProcess
  , manageImplicitStimulusProcess
  ) where

import           Data.Functor.Identity (Identity)
import           Engine.ActionDiscovery.Instances ()
import           Engine.ActionDiscovery.Protocol
  ( ActionProtocol (runActionProtocol)
  )
import           Grammar.Parser.Atomics.Verbs
  ( DirectionalStimulusVerb
  , ImplicitStimulusVerb
  )
import           Grammar.Parser.Composites.Nouns (DirectionalStimulusNounPhrase)
import           Model.Core
  ( Agent
  , DirectionalStimulusF
  , GameComputation
  , ImplicitStimulusF
  )
import           Model.GID (GID)

manageImplicitStimulusProcess :: GID Agent
                              -> ImplicitStimulusVerb
                              -> GameComputation Identity ()
manageImplicitStimulusProcess = runActionProtocol @ImplicitStimulusF

manageDirectionalStimulusProcess :: GID Agent
                                 -> DirectionalStimulusVerb
                                 -> DirectionalStimulusNounPhrase
                                 -> GameComputation Identity ()
manageDirectionalStimulusProcess actorGid verb phrase =
  runActionProtocol @DirectionalStimulusF actorGid (verb, phrase)
