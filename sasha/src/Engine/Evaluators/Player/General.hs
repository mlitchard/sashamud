module Engine.Evaluators.Player.General
  ( eval
  ) where

import           Data.Functor.Identity (Identity)
import           Engine.ActionDiscovery.Divestment.Drop
  ( manageDivestmentProcess
  )
import           Engine.ActionDiscovery.Get.Acquisition.Get
  ( manageAcquisitionProcess
  )
import           Engine.ActionDiscovery.Percieve.Look
  ( manageAgentStimulusProcess
  , manageDirectionalStimulusProcess
  , manageImplicitStimulusProcess
  )
import           Grammar.Parser.Composites.Model
  ( AcquisitionVerbPhrase
  , DivestmentVerbPhrase
  , Imperative (AcquisitionVerbPhrase', DivestmentVerbPhrase', StimulusVerbPhrase)
  , Sentence (Imperative)
  , StimulusVerbPhrase (AgentStimulusVerbPhrase, DirectStimulusVerbPhrase, ImplicitStimulusVerb)
  )
import           Model.Core (Agent, GameComputation)
import           Model.GID (GID)

eval :: GID Agent -> Sentence -> GameComputation Identity ()
eval actorGid (Imperative imperative) = evalImperative actorGid imperative

evalImperative :: GID Agent -> Imperative -> GameComputation Identity ()
evalImperative actorGid (StimulusVerbPhrase stimulusVerbPhrase) =
  evalStimulusVerbPhrase actorGid stimulusVerbPhrase
evalImperative actorGid (AcquisitionVerbPhrase' acquisitionVerbPhrase) =
  evalAcquisitionVerbPhrase actorGid acquisitionVerbPhrase
evalImperative actorGid (DivestmentVerbPhrase' divestmentVerbPhrase) =
  evalDivestmentVerbPhrase actorGid divestmentVerbPhrase

evalAcquisitionVerbPhrase :: GID Agent -> AcquisitionVerbPhrase -> GameComputation Identity ()
evalAcquisitionVerbPhrase = manageAcquisitionProcess

evalDivestmentVerbPhrase :: GID Agent -> DivestmentVerbPhrase -> GameComputation Identity ()
evalDivestmentVerbPhrase = manageDivestmentProcess

evalStimulusVerbPhrase :: GID Agent -> StimulusVerbPhrase -> GameComputation Identity ()
evalStimulusVerbPhrase actorGid (ImplicitStimulusVerb verb) =
  manageImplicitStimulusProcess actorGid verb
evalStimulusVerbPhrase actorGid (DirectStimulusVerbPhrase verb nounPhrase) =
  manageDirectionalStimulusProcess actorGid verb nounPhrase
evalStimulusVerbPhrase actorGid (AgentStimulusVerbPhrase verb playerName) =
  manageAgentStimulusProcess actorGid verb playerName
