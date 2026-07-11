module Engine.Evaluators.Player.General
  ( eval
  ) where

import           Data.Functor.Identity (Identity)
import           Engine.ActionDiscovery.Percieve.Look
  ( manageImplicitStimulusProcess
  )
import           Grammar.Parser.Composites.Model
  ( Imperative (StimulusVerbPhrase)
  , Sentence (Imperative)
  , StimulusVerbPhrase (ImplicitStimulusVerb)
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
  sendMessage actorGid dummyMessage
  pure ()
 --  manageImplicitStimulusProcess actorGid verb

sendMessage :: GID Agent -> RichText -> GameComputation Identity ()
sendMessage actorGid message = do
  recipients <- getRecipients actorGid
  pure ()

getRecipients :: GID Agent -> GameComputation Identity (Set (Gid Agent))
getRecipients = sceneAgents <$> getScene

getWorld :: GameComputation Identity World
getWorld = 

