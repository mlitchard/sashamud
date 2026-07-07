module Engine.Resolution.Perception
  ( youSeeM
  , modifyAgentNarration
  ) where

import           SashaPrelude

import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (lookup)
import           Data.Text (intercalate)
import           Error (throwMaybeM)
import           Lens.Micro.Platform (at, non, over, use, view, (%=))
import           Model.Core
  ( Agent
  , AgentKind (PlayerAgent)
  , GameComputation
  , Narration
  , actionConsequence
  , agentCurrentScene
  , agentKind
  , agentMap
  , agentShortName
  , getAgentMap
  , getGIDToDataMap
  , narrationMap
  , playerAction
  , presenceListing
  , sceneAgents
  , sceneDescription
  , sceneMap
  , unNarrationMap
  , world
  )
import           Model.GID (GID)
import           Model.RichText (TextColor (White), colored)

modifyAgentNarration :: GID Agent -> (Narration -> Narration) -> GameComputation Identity ()
modifyAgentNarration agentGid f =
  narrationMap . unNarrationMap . at agentGid . non mempty %= f

youSeeM :: GID Agent -> GameComputation Identity ()
youSeeM actorGid = do
  aMap <- use (world . agentMap . getAgentMap)
  actor <- throwMaybeM ("Actor not found: " <> pack (show actorGid))
             (lookup actorGid aMap)
  let sceneGid = view agentCurrentScene actor
  sMap <- use (world . sceneMap . getGIDToDataMap)
  scene <- throwMaybeM ("Scene not found: " <> pack (show sceneGid))
             (lookup sceneGid sMap)
  modifyAgentNarration actorGid (over playerAction (colored White "You look around." :))
  let desc = view sceneDescription scene
  modifyAgentNarration actorGid (over actionConsequence (desc :))
  let otherAgentGids = filter (/= actorGid) (toList (view sceneAgents scene))
      otherPlayerNames =
        [ view agentShortName agent
        | gid <- otherAgentGids
        , Just agent <- [lookup gid aMap]
        , view agentKind agent == PlayerAgent
        ]
  when (not (null otherPlayerNames)) $
    modifyAgentNarration actorGid
      (over presenceListing (colored White ("Also here: " <> intercalate ", " otherPlayerNames) :))
