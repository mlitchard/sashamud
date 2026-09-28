{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
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
  , EntityID (EntityObject, EntityAgent)
  , SpatialRelationship (ContainedIn, Contains, Supports, SupportedBy)
  , SpatialRelationshipMap (SpatialRelationshipMap)
    -- * Session
  , SessionId (SessionId, unSessionId)
    -- * Evaluator
  , Evaluator (Evaluator)
  , runEvaluator
    -- * GameState
  , GameState (..)
  , GameStateT (GameStateT, runGameStateT)
  , PossibilityGraph (..)
    -- * GameComputation
  , GameComputation (GameComputation, runGameComputation)
    -- * Action Management
  , ActionManagement (DSAManagementKey, ISAManagementKey)
  , ActionManagementFunctions (ActionManagementFunctions)
  , actionManagementFunctions
  , ActionManagementOperation (AddDirectionalStimulus, AddImplicitStimulus)
  , GIDToDataMap (GIDToDataMap)
  , getGIDToDataMap
    -- * Action Effects
  , ActionEffectKey (DirectionalStimulusActionKey, ImplicitStimulusActionKey)
  , ActionEffectKeyF
  , DirectionalStimulusF (DirectionalStimulusF, DirectionalNoStimulusF)
  , DirectionalStimulusMap
  , ImplicitStimulusF (ImplicitStimulusF, ImplicitNoStimulusF)
  , ImplicitStimulusMap
    -- * Witness
  , WitnessContext (ImplicitWitnessContext, DirectedWitnessContext, AgentWitnessContext, FailedAgentLookContext)
  , WitnessEffectF
  , WitnessF (WitnessF)
  , WitnessMap
    -- * World Outcomes
  , NarrationComputation (LookNarration, LookAtNarration, StaticNarration)
  , WorldOutcome (NarrationEffect)
  , EntityKey (SceneKey')
    -- * Registries
  , ActionMaps (ActionMaps)
  , directionalStimulusMap
  , implicitStimulusMap
  , witnessMap
  , EntityActionRegistry
  , WorldOutcomeRegistry
  , emptyActionMaps
    -- * Defaults
  , defaultObject
  , defaultScene
  , defaultWorld
    -- * Lenses
  , agentShortName
  , agentDescription
  , agentTitle
  , agentActionManagement
  , agentWitnessManagement
  , agentKind
  , shortName
  , description
  , objectActionManagement
  , title
  , sceneDescription
  , sceneActionManagement
  , sceneAgents
  , sceneMap
  , agentMap
  , objectMap
  , globalSemanticMap
  , spatialRelationshipMap
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
  , actionMaps
  , possibilityGraph
  , entityActionEffects
  , worldOutcomeEffects
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
  ( DirectionalStimulusVerb
  , ImplicitStimulusVerb
  )
import           Grammar.Parser.Composites.Model (Sentence)
import           Grammar.Parser.GCase (VerbKey)
import           Lens.Micro.Platform (makeLenses)
import           Model.GID (GID)
import           Model.RichText (RichText)
#ifdef TESTING
import           Test.QuickCheck (Arbitrary)
import           Test.QuickCheck.Arbitrary.Generic (GenericArbitrary (..))
import           Test.QuickCheck.Instances.Text ()
#endif

-- Action Management

type ActionManagement :: Type
data ActionManagement = DSAManagementKey DirectionalStimulusVerb (GID DirectionalStimulusF)
                      | ISAManagementKey ImplicitStimulusVerb (GID ImplicitStimulusF)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type ActionManagementFunctions :: Type
newtype ActionManagementFunctions = ActionManagementFunctions { _actionManagementFunctions :: Set ActionManagement }
  deriving stock (Eq, Ord, Show)
  deriving newtype (NFData)

type GIDToDataMap :: Type -> Type -> Type
newtype GIDToDataMap k v = GIDToDataMap { _getGIDToDataMap :: Map (GID k) v }
  deriving stock (Eq, Ord, Show)
  deriving newtype (NFData)

-- Action Management Operations

type ActionManagementOperation :: Type
data ActionManagementOperation = AddDirectionalStimulus DirectionalStimulusVerb (GID DirectionalStimulusF)
                               | AddImplicitStimulus ImplicitStimulusVerb (GID ImplicitStimulusF)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

-- Session

newtype SessionId = SessionId { unSessionId :: Text }
  deriving stock (Generic, Show)
  deriving newtype (Eq, FromJSON, NFData, Ord, ToJSON)

-- Entity Types

type AgentKind :: Type
data AgentKind
  = Denizen
  | Fixture
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type Object :: Type
data Object = Object
  { _shortName              :: Text
  , _description            :: RichText
  , _objectActionManagement :: ActionManagementFunctions
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type Agent :: Type
data Agent = Agent
  { _agentShortName         :: RichText
  , _agentDescription       :: RichText
  , _agentTitle             :: RichText
  , _agentActionManagement  :: ActionManagementFunctions
  , _agentWitnessManagement :: Map VerbKey (GID WitnessF)
  , _agentKind              :: AgentKind
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type AgentMap :: Type
newtype AgentMap = AgentMap { _getAgentMap :: Map (GID Agent) Agent }
  deriving stock (Eq, Ord, Show)
  deriving newtype (NFData)

type Scene :: Type
data Scene = Scene
  { _title                 :: Text
  , _sceneDescription      :: RichText
  , _sceneActionManagement :: ActionManagementFunctions
  , _sceneAgents           :: Set (GID Agent)
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type SceneMap :: Type
newtype SceneMap = SceneMap { _getSceneMap :: Map (GID Scene) Scene }
  deriving stock (Eq, Ord, Show)
  deriving newtype (NFData)

type EntityID :: Type
data EntityID = EntityObject (GID Object)
              | EntityAgent (GID Agent)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type SpatialRelationship :: Type
data SpatialRelationship = ContainedIn EntityID
                         | Contains (Set EntityID)
                         | Supports (Set EntityID)
                         | SupportedBy EntityID
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type SpatialRelationshipMap :: Type
newtype SpatialRelationshipMap = SpatialRelationshipMap { _unSpatialRelationshipMap :: Map EntityID (Set SpatialRelationship) }
  deriving stock (Eq, Ord, Show)
  deriving newtype (NFData)

type World :: Type
data World = World
  { _objectMap              :: GIDToDataMap Object Object
  , _sceneMap               :: GIDToDataMap Scene Scene
  , _globalSemanticMap      :: Map Text (Set (GID Object))
  , _agentMap               :: AgentMap
  , _spatialRelationshipMap :: SpatialRelationshipMap
  }
  deriving stock (Eq, Ord, Show)

instance NFData World where
  rnf (World om sm gs am srm) = rnf om `seq` rnf sm `seq` rnf gs `seq` rnf am `seq` rnf srm

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
newtype NarrationMap = NarrationMap { _unNarrationMap :: Map (GID Agent) Narration }
  deriving stock (Eq, Ord, Show)
  deriving newtype (NFData)

instance Semigroup NarrationMap where
  NarrationMap m1 <> NarrationMap m2 = NarrationMap (unionWith (<>) m1 m2)

instance Monoid NarrationMap where
  mempty = NarrationMap mempty

-- World Outcomes

type NarrationComputation :: Type
data NarrationComputation = LookAtNarration (GID Object)
                          | LookNarration
                          | StaticNarration Text
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type WorldOutcome :: Type
data WorldOutcome = NarrationEffect NarrationComputation
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type EntityKey :: Type
data EntityKey = SceneKey' (GID Scene)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

-- Action Effect Types

type ActionEffectKey :: Type
data ActionEffectKey = DirectionalStimulusActionKey (GID DirectionalStimulusF)
                     | ImplicitStimulusActionKey (GID ImplicitStimulusF)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type ActionEffectKeyF :: Type
type ActionEffectKeyF = GID Agent -> ActionEffectKey -> GameComputation Identity ()

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

type WitnessContext :: Type
data WitnessContext = ImplicitWitnessContext
                    | DirectedWitnessContext (GID Object)
                    | AgentWitnessContext (GID Agent)
                    | FailedAgentLookContext

type WitnessEffectF :: Type
type WitnessEffectF = GID Agent -> GID Agent -> WitnessContext -> GameComputation Identity ()

type WitnessF :: Type
data WitnessF = WitnessF WitnessEffectF

type WitnessMap :: Type
type WitnessMap = Map (GID WitnessF) WitnessF

-- Registries

type ActionMaps :: Type
data ActionMaps = ActionMaps
  { _directionalStimulusMap :: DirectionalStimulusMap
  , _implicitStimulusMap    :: ImplicitStimulusMap
  }

emptyActionMaps :: ActionMaps
emptyActionMaps = ActionMaps
  { _directionalStimulusMap = mempty
  , _implicitStimulusMap    = mempty
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
newtype GameComputation m a = GameComputation { runGameComputation :: ExceptT Text (GameStateT m) a }
  deriving newtype
    ( Applicative
    , Functor
    , Monad
    , MonadError Text
    , MonadState GameState
    )

instance MonadTrans GameComputation where
  lift = GameComputation . lift . lift

-- PossibilityGraph

type PossibilityGraph :: Type
data PossibilityGraph = PossibilityGraph
  { _entityActionEffects :: EntityActionRegistry
  , _worldOutcomeEffects :: WorldOutcomeRegistry
  , _witnessMap          :: WitnessMap
  , _newUserStartScene   :: Maybe (GID Scene)
  , _newUserMkAgent      :: Maybe (Text -> Agent)
  }

-- Defaults

defaultScene :: Scene
defaultScene = Scene
  { _title                 = mempty
  , _sceneDescription      = mempty
  , _sceneActionManagement = ActionManagementFunctions mempty
  , _sceneAgents           = mempty
  }

defaultObject :: Object
defaultObject = Object
  { _shortName              = mempty
  , _description            = mempty
  , _objectActionManagement = ActionManagementFunctions mempty
  }

defaultWorld :: World
defaultWorld = World
  { _objectMap              = GIDToDataMap mempty
  , _sceneMap               = GIDToDataMap mempty
  , _globalSemanticMap      = mempty
  , _agentMap               = AgentMap mempty
  , _spatialRelationshipMap = SpatialRelationshipMap mempty
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

#ifdef TESTING
deriving newtype instance Arbitrary SessionId
deriving via (GenericArbitrary Narration) instance Arbitrary Narration
#endif
