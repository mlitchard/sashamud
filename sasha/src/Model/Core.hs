{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# OPTIONS_GHC -fconstraint-solver-iterations=10 #-}
{-# HLINT ignore "Use newtype instead of data" #-}

module Model.Core
  ( -- * Entity Types
    Agent (..)
  , AgentKind (Denizen, Fixture)
  , AgentMap (AgentMap)
  , Scene (..)
  , World (..)
  , Narration (..)
  , NarrationMap (NarrationMap)
  , Object (..)
    -- * Spatial
  , EntityKey (EntityObject, EntityAgent, EntityScene)
  , ActorKey (ActorKey)
  , TargetKey (TargetKey)
  , AgentKey (AgentKey)
  , Entity (AgentEntity, ObjectEntity, SceneEntity)
  , SpatialRelationship (ContainedIn, Contains, Supports, SupportedBy, Inventory)
  , SpatialRelationshipMap (SpatialRelationshipMap)
    -- * Session
  , SessionId (SessionId, unSessionId)
    -- * Labels
  , SceneLabel (SceneLabel, unSceneLabel)
  , ObjectLabel (ObjectLabel, unObjectLabel)
    -- * Evaluator
  , Evaluator (Evaluator)
  , runEvaluator
    -- * GameState
  , GameState (..)
  , GameStateT (GameStateT, runGameStateT)
  , PossibilityGraph (..)
    -- * GameComputation
  , GameComputation (GameComputation, runGameComputation)
  , GameError (ActorError, AgentMissing, AgentLocationMissing, SceneMissing, ObjectMissing, WitnessFunctionMissing, SpatialRelationshipsMissing, SupportMissing, ObjectActionMissing, ActionMissing, ActionGIDMissing, NoFloorHere, SharedWitnessMissing, NewUserStartSceneMissing, NewUserTemplateMissing, EvaluatorMissing, SessionMissing, ActorNotAgent, TargetNotAgent, ObjectInScene, ParseFailed)
  , gameErrorText
    -- * Counters
  , PInt
  , succPInt
  , unPInt
  , firstGID
  , BuilderCounters (BuilderCounters)
  , initialCounters
  , nextSceneId
  , nextObjectId
  , nextImplicitStimulusId
  , nextDirectionalStimulusId
  , nextAcquisitionId
  , nextDivestmentId
  , nextWitnessId
    -- * Action Management
  , ActionManagement (DSAManagementKey, ISAManagementKey, DSATargetManagementKey, ISATargetManagementKey, AVTargetManagementKey, AVSupportManagementKey, DVManagementKey, DVSurfaceManagementKey)
  , ActionManagementFunctions (ActionManagementFunctions)
  , actionManagementFunctions
  , ActionManagementOperation (AddDirectionalStimulus, AddImplicitStimulus, AddAcquisitionVerb, AddDivestmentVerb)
  , GIDToDataMap (GIDToDataMap)
  , getGIDToDataMap
    -- * Action Effects
  , ActionEffectKey (DirectionalStimulusActionKey, ImplicitStimulusActionKey, AcquisitionalActionKey, DivestmentActionKey)
  , ActionEffectKeyF (ActionEffectKeyF, unActionEffectKeyF)
  , AcquisitionF (AcquisitionF, AcquisitionCannotF)
  , AcquisitionMap
  , DirectionalStimulusF (DirectionalStimulusF, DirectionalNoStimulusF)
  , DirectionalStimulusMap
  , DivestmentF (DivestmentF, DivestmentCannotF)
  , DivestmentMap
  , ImplicitStimulusF (ImplicitStimulusF, ImplicitNoStimulusF)
  , ImplicitStimulusMap
    -- * Witness
  , WitnessContext (ImplicitWitnessContext, DirectedWitnessContext, AgentWitnessContext, FailedAgentLookContext, AcquisitionWitnessContext, DivestmentWitnessContext)
  , WitnessEffectF (WitnessEffectF, unWitnessEffectF)
  , WitnessF (WitnessF)
  , WitnessMap
    -- * World Outcomes
  , NarrationComputation (LookNarration, LookAtNarration, LookAtAgentNarration, StaticNarration)
  , WorldOutcome (NarrationEffect, SpatialRelationshipEffect)
  , SpatialRelationshipComputation (Acquisition, Divestiture)
  , DivestmentTargetType (DivestToSurface')
    -- * Registries
  , ActionMaps (ActionMaps)
  , acquisitionActionMap
  , directionalStimulusMap
  , divestmentActionMap
  , implicitStimulusMap
  , witnessMap
  , EntityActionRegistry
  , WorldOutcomeRegistry
  , emptyActionMaps
    -- * Defaults
  , defaultObject
  , defaultScene
  , defaultWorld
  , defaultGameState
    -- * Lenses
  , agentShortName
  , agentDescription
  , agentTitle
  , agentActionManagement
  , agentKind
  , shortName
  , description
  , descriptives
  , objectActionManagement
  , title
  , sceneDescription
  , objectSemanticMap
  , agentSemanticMap
  , sceneObjects
  , sceneActionManagement
  , sceneAgents
  , sceneMap
  , agentMap
  , sharedActionManagement
  , actorTargetActionManagement
  , sharedWitnessManagement
  , objectMap
  , globalSemanticMap
  , spatialRelationshipMap
  , declaredSceneGIDs
  , declaredObjectGIDs
  , unSpatialRelationshipMap
  , playerAction
  , actionConsequence
  , presenceListing
  , actionEpilogue
  , unNarrationMap
  , getAgentMap
  , world
  , narrationMap
  , evaluation
  , agentLocationMap
  , agentWitnessMap
  , actionMaps
  , possibilityGraph
  , actorTargetWorldOutcomeEffects
  , targetWorldOutcomeEffects
  , sharedWorldOutcomeEffects
  , actorTargetEntityActionEffects
  , targetEntityActionEffects
  , sharedEntityActionEffects
  , newUserStartScene
  , newUserMkAgent
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData (rnf))
import           Control.Monad.Except (ExceptT, MonadError)
import           Control.Monad.Morph (MFunctor)
import           Control.Monad.State (MonadState, StateT)
import           Control.Monad.Trans (MonadTrans (lift))
import           Data.Aeson (FromJSON, ToJSON)
import           Data.Aeson.TypeScript (derivingTypeScriptDefinition)
import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (Map, unionWith)
import           Data.Set (Set)
import           Grammar.Parser.Atomics.Verbs
  ( AcquisitionVerb
  , DirectionalStimulusVerb
  , DivestmentVerb
  , ImplicitStimulusVerb
  )
import           Grammar.Parser.Composites.Model (Sentence)
import           Grammar.Parser.Composites.Nouns (DirectionalStimulusNounPhrase)
import           Grammar.Parser.GCase (NounKey, VerbKey)
import           Lens.Micro.Platform (makeLenses)
import           Model.GID (GID)
import           Model.RichText (RichText)
#ifdef TESTING
import           ArbitraryOrphans ()
import           Test.QuickCheck (Arbitrary)
import           Test.QuickCheck.Arbitrary.Generic (GenericArbitrary (..))
import           Test.QuickCheck.Instances.Text ()
#endif

-- Action Management

type ActionManagement :: Type
data ActionManagement = DSAManagementKey DirectionalStimulusVerb (GID DirectionalStimulusF)
                      | ISAManagementKey ImplicitStimulusVerb (GID ImplicitStimulusF)
                      | DSATargetManagementKey DirectionalStimulusVerb (GID DirectionalStimulusF)
                      | ISATargetManagementKey ImplicitStimulusVerb (GID ImplicitStimulusF)
                      | AVTargetManagementKey AcquisitionVerb (GID AcquisitionF)
                      | AVSupportManagementKey AcquisitionVerb (GID AcquisitionF)
                      | DVManagementKey DivestmentVerb (GID DivestmentF)
                      | DVSurfaceManagementKey DivestmentVerb (GID DivestmentF)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

type ActionManagementFunctions :: Type
newtype ActionManagementFunctions = ActionManagementFunctions { _actionManagementFunctions :: Set ActionManagement }
  deriving stock (Eq, Ord, Show)
  deriving newtype (FromJSON, NFData, ToJSON)

type GIDToDataMap :: Type -> Type -> Type
newtype GIDToDataMap k v = GIDToDataMap { _getGIDToDataMap :: Map (GID k) v }
  deriving stock (Eq, Ord, Show)
  deriving newtype (NFData)

-- Action Management Operations

type ActionManagementOperation :: Type
data ActionManagementOperation = AddDirectionalStimulus DirectionalStimulusVerb (GID DirectionalStimulusF)
                               | AddImplicitStimulus ImplicitStimulusVerb (GID ImplicitStimulusF)
                               | AddAcquisitionVerb AcquisitionVerb (GID AcquisitionF)
                               | AddDivestmentVerb DivestmentVerb (GID DivestmentF)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

-- Session

newtype SessionId = SessionId { unSessionId :: Text }
  deriving stock (Generic, Show)
  deriving newtype (Eq, FromJSON, NFData, Ord, ToJSON)

newtype SceneLabel = SceneLabel { unSceneLabel :: Text }
  deriving stock (Generic, Show)
  deriving newtype (Eq, NFData, Ord)

newtype ObjectLabel = ObjectLabel { unObjectLabel :: Text }
  deriving stock (Generic, Show)
  deriving newtype (Eq, NFData, Ord)

-- Entity Types

type AgentKind :: Type
data AgentKind
  = Denizen
  | Fixture
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

type Object :: Type
data Object = Object
  { _shortName              :: Text
  , _description            :: RichText
  , _descriptives           :: Set DirectionalStimulusNounPhrase
  , _objectActionManagement :: ActionManagementFunctions
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

type Agent :: Type
data Agent = Agent
  { _agentShortName        :: RichText
  , _agentDescription      :: RichText
  , _agentTitle            :: RichText
  , _agentActionManagement :: ActionManagementFunctions
  , _agentKind             :: AgentKind
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

type AgentMap :: Type
newtype AgentMap = AgentMap { _getAgentMap :: Map (GID Agent) Agent }
  deriving stock (Eq, Ord, Show)
  deriving newtype (NFData)

type Scene :: Type
data Scene = Scene
  { _title                 :: Text
  , _sceneDescription      :: RichText
  , _objectSemanticMap     :: Map NounKey (Set (GID Object))
  , _agentSemanticMap      :: Map NounKey (Set (GID Agent))
  , _sceneObjects          :: Set (GID Object)
  , _sceneActionManagement :: ActionManagementFunctions
  , _sceneAgents           :: Set (GID Agent)
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type SceneMap :: Type
newtype SceneMap = SceneMap { _getSceneMap :: Map (GID Scene) Scene }
  deriving stock (Eq, Ord, Show)
  deriving newtype (NFData)

type EntityKey :: Type
data EntityKey = EntityObject (GID Object)
               | EntityAgent (GID Agent)
               | EntityScene (GID Scene)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type ActorKey :: Type
newtype ActorKey = ActorKey EntityKey
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type TargetKey :: Type
newtype TargetKey = TargetKey EntityKey
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type AgentKey :: Type
newtype AgentKey = AgentKey (GID Agent)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type Entity :: Type
data Entity
  = AgentEntity
  | ObjectEntity
  | SceneEntity
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type SpatialRelationship :: Type
data SpatialRelationship = ContainedIn EntityKey
                         | Contains (Set EntityKey)
                         | Supports (Set EntityKey)
                         | SupportedBy EntityKey
                         | Inventory (GID Agent)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type SpatialRelationshipMap :: Type
newtype SpatialRelationshipMap = SpatialRelationshipMap { _unSpatialRelationshipMap :: Map EntityKey (Set SpatialRelationship) }
  deriving stock (Eq, Ord, Show)
  deriving newtype (NFData)

type World :: Type
data World = World
  { _objectMap :: GIDToDataMap Object Object
  , _sceneMap :: GIDToDataMap Scene Scene
  , _globalSemanticMap :: Map NounKey (Set (GID Object))
  , _agentMap :: AgentMap
  , _sharedActionManagement :: Map VerbKey (Map Entity ActionManagementFunctions)
  , _actorTargetActionManagement :: Map ActorKey (Map TargetKey ActionManagementFunctions)
  , _sharedWitnessManagement :: Map Entity (GID WitnessF)
  , _spatialRelationshipMap :: SpatialRelationshipMap
  , _declaredSceneGIDs :: Map SceneLabel (GID Scene)
  , _declaredObjectGIDs :: Map ObjectLabel (GID Object)
  }
  deriving stock (Eq, Ord, Show)

instance NFData World where
  rnf (World om sm gs am sam atam swm srm dsg dog) = rnf om `seq` rnf sm `seq` rnf gs `seq` rnf am `seq` rnf sam `seq` rnf atam `seq` rnf swm `seq` rnf srm `seq` rnf dsg `seq` rnf dog

type Narrative :: Type
data Narrative
  = PlayerAction
  | ActionConsequence
  | PresenceListing
  | ActionEpilogue
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type Narration :: Type
data Narration = Narration
  { _playerAction      :: [RichText]
  , _actionConsequence :: [RichText]
  , _presenceListing   :: [RichText]
  , _actionEpilogue    :: [RichText]
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)
  deriving (Monoid, Semigroup)
    via (Generically Narration)

type NarrationMap :: Type
newtype NarrationMap = NarrationMap { _unNarrationMap :: Map AgentKey Narration }
  deriving stock (Eq, Ord, Show)
  deriving newtype (NFData)

instance Semigroup NarrationMap where
  NarrationMap m1 <> NarrationMap m2 = NarrationMap (unionWith (<>) m1 m2)

instance Monoid NarrationMap where
  mempty = NarrationMap mempty

-- World Outcomes

type NarrationComputation :: Type
data NarrationComputation = LookAtNarration (GID Object)
                          | LookAtAgentNarration
                          | LookNarration
                          | StaticNarration Text
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type DivestmentTargetType :: Type
data DivestmentTargetType
  = DivestToSurface'
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type SpatialRelationshipComputation :: Type
data SpatialRelationshipComputation = Acquisition EntityKey EntityKey
                                    | Divestiture (GID Object) (GID Object) DivestmentTargetType
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type WorldOutcome :: Type
data WorldOutcome = NarrationEffect NarrationComputation
                  | SpatialRelationshipEffect SpatialRelationshipComputation
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

-- Action Effect Types

type ActionEffectKey :: Type
data ActionEffectKey = DirectionalStimulusActionKey (GID DirectionalStimulusF)
                     | ImplicitStimulusActionKey (GID ImplicitStimulusF)
                     | AcquisitionalActionKey (GID AcquisitionF)
                     | DivestmentActionKey (GID DivestmentF)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type ActionEffectKeyF :: Type
newtype ActionEffectKeyF = ActionEffectKeyF { unActionEffectKeyF :: ActorKey -> TargetKey -> ActionEffectKey -> GameComputation Identity () }

type DirectionalStimulusF :: Type
data DirectionalStimulusF = DirectionalStimulusF ActionEffectKeyF
                          | DirectionalNoStimulusF ActionEffectKeyF

type DirectionalStimulusMap :: Type
type DirectionalStimulusMap = Map (GID DirectionalStimulusF) DirectionalStimulusF

type ImplicitStimulusF :: Type
data ImplicitStimulusF = ImplicitStimulusF ActionEffectKeyF
                       | ImplicitNoStimulusF ActionEffectKeyF

type ImplicitStimulusMap :: Type
type ImplicitStimulusMap = Map (GID ImplicitStimulusF) ImplicitStimulusF

type AcquisitionF :: Type
data AcquisitionF = AcquisitionF ActionEffectKeyF
                  | AcquisitionCannotF ActionEffectKeyF

type AcquisitionMap :: Type
type AcquisitionMap = Map (GID AcquisitionF) AcquisitionF

type DivestmentF :: Type
data DivestmentF = DivestmentF ActionEffectKeyF
                 | DivestmentCannotF ActionEffectKeyF

type DivestmentMap :: Type
type DivestmentMap = Map (GID DivestmentF) DivestmentF

type WitnessContext :: Type
data WitnessContext = ImplicitWitnessContext
                    | DirectedWitnessContext (GID Object)
                    | AgentWitnessContext (GID Agent)
                    | FailedAgentLookContext
                    | AcquisitionWitnessContext (GID Object)
                    | DivestmentWitnessContext (GID Object)

type WitnessEffectF :: Type
newtype WitnessEffectF = WitnessEffectF { unWitnessEffectF :: AgentKey -> ActorKey -> WitnessContext -> GameComputation Identity () }

type WitnessF :: Type
data WitnessF = WitnessF WitnessEffectF

type WitnessMap :: Type
type WitnessMap = Map (GID WitnessF) WitnessF

-- Registries

type ActionMaps :: Type
data ActionMaps = ActionMaps
  { _directionalStimulusMap :: DirectionalStimulusMap
  , _implicitStimulusMap    :: ImplicitStimulusMap
  , _acquisitionActionMap   :: AcquisitionMap
  , _divestmentActionMap    :: DivestmentMap
  }

emptyActionMaps :: ActionMaps
emptyActionMaps = ActionMaps
  { _directionalStimulusMap = mempty
  , _implicitStimulusMap    = mempty
  , _acquisitionActionMap   = mempty
  , _divestmentActionMap    = mempty
  }

type EntityActionRegistry :: Type
type EntityActionRegistry = Map ActionEffectKey (Map EntityKey (Set ActionManagementOperation))

type WorldOutcomeRegistry :: Type
type WorldOutcomeRegistry = Map ActionEffectKey (Set WorldOutcome)

-- Evaluator

type Evaluator :: Type
newtype Evaluator = Evaluator { _runEvaluator :: GID Agent -> Sentence -> GameComputation Identity () }

type GameState :: Type
data GameState = GameState
  { _world            :: World
  , _narrationMap     :: NarrationMap
  , _evaluation       :: Map (GID Agent) Evaluator
  , _agentLocationMap :: Map (GID Agent) (GID Scene)
  , _agentWitnessMap  :: Map AgentKey (Map EntityKey (GID WitnessF))
  , _actionMaps       :: ActionMaps
  , _possibilityGraph :: PossibilityGraph
  }

type GameStateT :: (Type -> Type) -> Type -> Type
newtype GameStateT m a = GameStateT { runGameStateT :: StateT GameState m a }
  deriving newtype
    ( Applicative
    , Functor
    , MFunctor
    , Monad
    , MonadIO
    , MonadState GameState
    )

instance MonadTrans GameStateT where
  lift = GameStateT . lift

-- GameComputation

type GameComputation :: (Type -> Type) -> Type -> Type
newtype GameComputation m a = GameComputation { runGameComputation :: ExceptT GameError (GameStateT m) a }
  deriving newtype
    ( Applicative
    , Functor
    , Monad
    , MonadError GameError
    , MonadState GameState
    )

instance MonadTrans GameComputation where
  lift = GameComputation . lift . lift

type GameError :: Type
data GameError = ActorError (GID Agent) GameError
               | AgentMissing (GID Agent)
               | AgentLocationMissing (GID Agent)
               | SceneMissing (GID Scene)
               | ObjectMissing (GID Object)
               | WitnessFunctionMissing (GID WitnessF)
               | SpatialRelationshipsMissing (GID Object)
               | SupportMissing (GID Object)
               | ObjectActionMissing (GID Object)
               | ActionMissing Text
               | ActionGIDMissing Text
               | NoFloorHere (GID Scene)
               | SharedWitnessMissing
               | NewUserStartSceneMissing
               | NewUserTemplateMissing
               | EvaluatorMissing (GID Agent)
               | SessionMissing SessionId
               | ActorNotAgent ActorKey
               | TargetNotAgent TargetKey
               | ObjectInScene (GID Scene)
               | ParseFailed Text
  deriving stock (Eq, Generic, Show)

gameErrorText :: GameError -> Text
gameErrorText = \case
  ActorError _ err                -> gameErrorText err
  AgentMissing gid                -> "Agent not found: " <> pack (show gid)
  AgentLocationMissing gid        -> "Agent location not found: " <> pack (show gid)
  SceneMissing gid                -> "Scene not found: " <> pack (show gid)
  ObjectMissing gid               -> "Object not found: " <> pack (show gid)
  WitnessFunctionMissing gid      -> "Witness function not found: " <> pack (show gid)
  SpatialRelationshipsMissing gid -> "Object not found in spatial relationships: " <> pack (show gid)
  SupportMissing gid              -> "Object has no support: " <> pack (show gid)
  ObjectActionMissing gid         -> "Object has no action: " <> pack (show gid)
  ActionMissing t                 -> t
  ActionGIDMissing t              -> t
  NoFloorHere _                   -> "There's nowhere to drop that here."
  SharedWitnessMissing            -> "Programmer Error: world declared no shared AgentEntity witness"
  NewUserStartSceneMissing        -> "Programmer Error: world declared no newUser start scene"
  NewUserTemplateMissing          -> "Programmer Error: world declared no newUser agent template"
  EvaluatorMissing gid            -> "Programmer Error: no evaluator for " <> pack (show gid)
  SessionMissing sid              -> "Programmer Error: no InGame session for " <> pack (show sid)
  ActorNotAgent key               -> "Programmer Error: non-agent actor: " <> pack (show key)
  TargetNotAgent key              -> "Programmer Error: LookAtAgentNarration target is not an agent: " <> pack (show key)
  ObjectInScene gid               -> "Programmer Error: object in a scene: " <> pack (show gid)
  ParseFailed t                   -> t

-- PossibilityGraph

type PossibilityGraph :: Type
data PossibilityGraph = PossibilityGraph
  { _actorTargetWorldOutcomeEffects :: Map ActorKey (Map TargetKey WorldOutcomeRegistry)
  , _targetWorldOutcomeEffects :: Map TargetKey WorldOutcomeRegistry
  , _sharedWorldOutcomeEffects :: Map Entity WorldOutcomeRegistry
  , _actorTargetEntityActionEffects :: Map ActorKey (Map TargetKey EntityActionRegistry)
  , _targetEntityActionEffects :: Map TargetKey EntityActionRegistry
  , _sharedEntityActionEffects :: Map Entity EntityActionRegistry
  , _witnessMap :: WitnessMap
  , _newUserStartScene :: Maybe (GID Scene)
  , _newUserMkAgent :: Maybe (Text -> Agent)
  }

-- Defaults

defaultScene :: Scene
defaultScene = Scene
  { _title                 = mempty
  , _sceneDescription      = mempty
  , _objectSemanticMap     = mempty
  , _agentSemanticMap      = mempty
  , _sceneObjects          = mempty
  , _sceneActionManagement = ActionManagementFunctions mempty
  , _sceneAgents           = mempty
  }

defaultObject :: Object
defaultObject = Object
  { _shortName              = mempty
  , _description            = mempty
  , _descriptives           = mempty
  , _objectActionManagement = ActionManagementFunctions mempty
  }

defaultWorld :: World
defaultWorld = World
  { _objectMap              = GIDToDataMap mempty
  , _sceneMap               = GIDToDataMap mempty
  , _globalSemanticMap      = mempty
  , _agentMap               = AgentMap mempty
  , _sharedActionManagement  = mempty
  , _actorTargetActionManagement = mempty
  , _sharedWitnessManagement = mempty
  , _spatialRelationshipMap = SpatialRelationshipMap mempty
  , _declaredSceneGIDs      = mempty
  , _declaredObjectGIDs     = mempty
  }

defaultGameState :: GameState
defaultGameState = GameState
  { _world            = defaultWorld
  , _narrationMap     = NarrationMap mempty
  , _evaluation       = mempty
  , _agentLocationMap = mempty
  , _agentWitnessMap  = mempty
  , _actionMaps      = emptyActionMaps
  , _possibilityGraph = PossibilityGraph
      { _actorTargetWorldOutcomeEffects = mempty
      , _targetWorldOutcomeEffects      = mempty
      , _sharedWorldOutcomeEffects      = mempty
      , _actorTargetEntityActionEffects = mempty
      , _targetEntityActionEffects      = mempty
      , _sharedEntityActionEffects      = mempty
      , _witnessMap          = mempty
      , _newUserStartScene   = Nothing
      , _newUserMkAgent      = Nothing
      }
  }

newtype PInt = PInt Int
  deriving stock (Eq, Ord, Show)

succPInt :: PInt -> PInt
succPInt (PInt n) = PInt (n + 1)

unPInt :: PInt -> Int
unPInt (PInt n) = n

firstGID :: PInt
firstGID = PInt 0

data BuilderCounters = BuilderCounters
  { _nextSceneId               :: PInt
  , _nextObjectId              :: PInt
  , _nextImplicitStimulusId    :: PInt
  , _nextDirectionalStimulusId :: PInt
  , _nextAcquisitionId         :: PInt
  , _nextDivestmentId          :: PInt
  , _nextWitnessId             :: PInt
  }

initialCounters :: BuilderCounters
initialCounters = BuilderCounters
  { _nextSceneId               = firstGID
  , _nextObjectId              = firstGID
  , _nextImplicitStimulusId    = firstGID
  , _nextDirectionalStimulusId = firstGID
  , _nextAcquisitionId         = firstGID
  , _nextDivestmentId          = firstGID
  , _nextWitnessId             = firstGID
  }

-- Template Haskell (single stage — all types visible)

derivingTypeScriptDefinition ''SessionId
derivingTypeScriptDefinition ''Narration
makeLenses ''ActionManagementFunctions
makeLenses ''GIDToDataMap
makeLenses ''Agent
makeLenses ''AgentMap
makeLenses ''Object
makeLenses ''Scene
makeLenses ''SpatialRelationshipMap
makeLenses ''World
makeLenses ''Narration
makeLenses ''NarrationMap
makeLenses ''Evaluator
makeLenses ''GameState
makeLenses ''ActionMaps
makeLenses ''PossibilityGraph
makeLenses ''BuilderCounters

#ifdef TESTING
deriving newtype instance Arbitrary SessionId
deriving via (GenericArbitrary Narration) instance Arbitrary Narration
deriving via (GenericArbitrary ActionManagement) instance Arbitrary ActionManagement
deriving newtype instance Arbitrary ActionManagementFunctions
deriving via (GenericArbitrary AgentKind) instance Arbitrary AgentKind
deriving via (GenericArbitrary Object) instance Arbitrary Object
deriving via (GenericArbitrary Agent) instance Arbitrary Agent
#endif
