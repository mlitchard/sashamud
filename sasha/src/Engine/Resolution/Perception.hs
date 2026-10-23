module Engine.Resolution.Perception
  ( youSeeM
  , modifyAgentNarration
  ) where

import           SashaPrelude

import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (Map, elems, lookup)
import           Data.Set (Set)
import           Data.Text (intercalate)
import           Error (throwMaybeM)
import           Lens.Micro.Platform (at, non, over, use, view, (%=))
import           Model.Core
  ( Agent
  , AgentKey (AgentKey)
  , AgentKind (Denizen)
  , EntityKey (EntityObject)
  , GameComputation
  , GameError (AgentLocationMissing, ObjectMissing, SceneMissing)
  , Narration
  , Object
  , SpatialRelationship (ContainedIn, SupportedBy, Supports)
  , actionConsequence
  , agentKind
  , agentLocationMap
  , agentMap
  , agentShortName
  , getAgentMap
  , getGIDToDataMap
  , globalSemanticMap
  , narrationMap
  , objectMap
  , playerAction
  , presenceListing
  , sceneAgents
  , sceneDescription
  , sceneMap
  , shortName
  , spatialRelationshipMap
  , unNarrationMap
  , unSpatialRelationshipMap
  , world
  )
import           Model.GID (GID)
import           Model.RichText (TextColor (White), colored, toPlainText)

modifyAgentNarration :: AgentKey -> (Narration -> Narration) -> GameComputation Identity ()
modifyAgentNarration agentKey f =
  narrationMap . unNarrationMap . at agentKey . non mempty %= f

youSeeM :: GID Agent -> GameComputation Identity ()
youSeeM actorGid = do
  aMap <- use (world . agentMap . getAgentMap)
  oMap <- use (world . objectMap . getGIDToDataMap)
  locMap <- use agentLocationMap
  sceneGid <- throwMaybeM (AgentLocationMissing actorGid)
                (lookup actorGid locMap)
  sMap <- use (world . sceneMap . getGIDToDataMap)
  scene <- throwMaybeM (SceneMissing sceneGid)
             (lookup sceneGid sMap)
  modifyAgentNarration (AgentKey actorGid) (over playerAction (<> [colored White "You look around."]))
  let desc = view sceneDescription scene
  modifyAgentNarration (AgentKey actorGid) (over actionConsequence (<> [desc]))
  -- List visible objects (old code: Perception.hs:168-195)
  semMap <- use (world . globalSemanticMap)
  spatialMap <- use (world . spatialRelationshipMap . unSpatialRelationshipMap)
  let allSceneObjGids = mconcat (elems semMap)
      anchorObjects = [ oid | oid <- toList allSceneObjGids
                      , let rels = fromMaybe mempty (lookup (EntityObject oid) spatialMap)
                      , not (any isContainedOrSupported (toList rels))
                      ]
      topLevelEntities = concatMap (getDirectlySupported spatialMap) anchorObjects
  let topLevelObjectGids = [oid | EntityObject oid <- topLevelEntities]
  topLevelNames <- forM topLevelObjectGids $ \oid -> do
    obj <- throwMaybeM (ObjectMissing oid)
             (lookup oid oMap)
    pure (view shortName obj)
  when (not (null topLevelNames)) $ do
    let articleNames = fmap ("a " <>) topLevelNames
        seeText = "You see: " <> intercalate ", " articleNames
    modifyAgentNarration (AgentKey actorGid)
      (over actionConsequence (<> [colored White seeText]))
  -- List other Denizen agents
  let otherAgentGids = filter (/= actorGid) (toList (view sceneAgents scene))
      otherPlayerNames =
        [ toPlainText (view agentShortName agent)
        | gid <- otherAgentGids
        , Just agent <- [lookup gid aMap]
        , view agentKind agent == Denizen
        ]
  when (not (null otherPlayerNames)) $
    modifyAgentNarration (AgentKey actorGid)
      (over presenceListing (<> [colored White ("Also here: " <> intercalate ", " otherPlayerNames)]))
  where
    isContainedOrSupported :: SpatialRelationship -> Bool
    isContainedOrSupported (ContainedIn _) = True
    isContainedOrSupported (SupportedBy _) = True
    isContainedOrSupported _               = False

    getDirectlySupported :: Map EntityKey (Set SpatialRelationship) -> GID Object -> [EntityKey]
    getDirectlySupported smap oid =
      case lookup (EntityObject oid) smap of
        Nothing   -> []
        Just rels -> concatMap extractSupported (toList rels)

    extractSupported :: SpatialRelationship -> [EntityKey]
    extractSupported (Supports eidSet) = toList eidSet
    extractSupported _                 = []
