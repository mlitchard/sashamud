module Engine.Evaluators.Player.General
  ( eval
  ) where

import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (filter, keys)
import           Grammar.Parser.Composites.Model
  ( Imperative (StimulusVerbPhrase)
  , Sentence (Imperative)
  , StimulusVerbPhrase (ImplicitStimulusVerb)
  )
import           Lens.Micro.Platform (at, use, view, (.=))
import           Model.Core
  ( Agent
  , AgentKind (Denizen)
  , GameComputation
  , Narration (Narration, _actionConsequence, _actionEpilogue, _playerAction, _presenceListing)
  , agentKind
  , agentMap
  , getAgentMap
  , narrationMap
  , unNarrationMap
  , world
  )
import           Model.GID (GID)
import           Model.RichText (TextColor (White), colored)
import           SashaPrelude

eval :: GID Agent -> Sentence -> GameComputation Identity ()
eval actorGid (Imperative imperative) = evalImperative actorGid imperative

evalImperative :: GID Agent -> Imperative -> GameComputation Identity ()
evalImperative actorGid (StimulusVerbPhrase stimulusVerbPhrase) =
  evalStimulusVerbPhrase actorGid stimulusVerbPhrase

evalStimulusVerbPhrase :: GID Agent -> StimulusVerbPhrase -> GameComputation Identity ()
evalStimulusVerbPhrase _actorGid (ImplicitStimulusVerb _verb) = do
  aMap <- use (world . agentMap . getAgentMap)
  let playerGids = keys (Data.Map.Strict.filter (\agent -> view agentKind agent == Denizen) aMap)
      testNarration = Narration
        { _playerAction      = [colored White "the test worked!"]
        , _actionConsequence = []
        , _presenceListing   = []
        , _actionEpilogue    = []
        }
  forM_ playerGids $ \gid ->
    narrationMap . unNarrationMap . at gid .= Just testNarration
