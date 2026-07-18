module Engine.Evaluators.Player.General
  ( eval
  ) where

import           Data.Functor.Identity (Identity)
import           Engine.ActionDiscovery.Percieve.Look
  ( manageDirectionalStimulusProcess
  , manageImplicitStimulusProcess
  )
import           Grammar.Parser.Composites.Model
  ( Imperative (StimulusVerbPhrase)
  , Sentence (Imperative)
  , StimulusVerbPhrase (DirectStimulusVerbPhrase, ImplicitStimulusVerb)
  )
import           Model.Core (Agent, GameComputation)
import           Model.GID (GID)

eval :: GID Agent -> Sentence -> GameComputation Identity ()
eval actorGid (Imperative imperative) = evalImperative actorGid imperative

evalImperative :: GID Agent -> Imperative -> GameComputation Identity ()
evalImperative actorGid (StimulusVerbPhrase stimulusVerbPhrase) =
  evalStimulusVerbPhrase actorGid stimulusVerbPhrase

evalStimulusVerbPhrase :: GID Agent -> StimulusVerbPhrase -> GameComputation Identity ()
evalStimulusVerbPhrase actorGid (ImplicitStimulusVerb verb) =
  manageImplicitStimulusProcess actorGid verb
evalStimulusVerbPhrase actorGid (DirectStimulusVerbPhrase verb nounPhrase) =
  manageDirectionalStimulusProcess actorGid verb nounPhrase
