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
  , Object
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
  , ComputationContext (..)
  , GameComputation (GameComputation, runGameComputation)
    -- * Action Management
  , ActionManagement (ISAManagementKey, WitnessManagementKey)
  , ActionManagementFunctions (ActionManagementFunctions)
  , actionManagementFunctions
  , ActionManagementOperation (AddImplicitStimulus)
  , GIDToDataMap (GIDToDataMap)
  , getGIDToDataMap
    -- * Action Effects
  , ActionEffectKey (ImplicitStimulusActionKey)
  , ActionEffectKeyF
  , ImplicitStimulusF (ImplicitStimulusF, ImplicitNoStimulusF)
  , ImplicitStimulusMap
  , WitnessEffectF
  , WitnessF (WitnessF)
  , WitnessMap
    -- * World Outcomes
  , NarrationComputation (LookNarration, StaticNarration)
  , WorldOutcome (NarrationEffect, WitnessEffect)
  , EntityKey (SceneKey')
    -- * Registries
  , ActionMaps (ActionMaps)
  , implicitStimulusMap
  , witnessMap
  , EntityActionRegistry
  , WorldOutcomeRegistry
  , emptyActionMaps
    -- * Defaults
  , defaultScene
  , defaultWorld
    -- * Lenses
  , agentShortName
  , agentDescription
  , agentTitle
  , agentActionManagement
  , agentKind
  , title
  , sceneDescription
  , sceneActionManagement
  , sceneAgents
  , sceneMap
  , agentMap
  , objectMap
  , globalSemanticMap
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
  , entityActionEffects
  , worldOutcomeEffects
  , newUserStartScene
  , newUserMkAgent
  , ctxPossibilityGraph
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData (rnf))
import           Control.Monad.Except (ExceptT, MonadError)
import           Control.Monad.Morph (MFunctor)
import           Control.Monad.Reader (MonadReader, ReaderT)
import           Control.Monad.State (MonadState, StateT)
import           Control.Monad.Trans (MonadTrans (lift))
import           Data.Aeson (FromJSON, ToJSON)
import           Data.Aeson.TypeScript (derivingTypeScriptDefinition)
import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (Map, unionWith)
import           Data.Set (Set)
import           Grammar.Parser.Atomics.Verbs (ImplicitStimulusVerb)
import           Grammar.Parser.Composites.Model (Sentence)
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
data ActionManagement = ISAManagementKey ImplicitStimulusVerb (GID ImplicitStimulusF)
                      | WitnessManagementKey (GID WitnessF)
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
data ActionManagementOperation = AddImplicitStimulus ImplicitStimulusVerb (GID ImplicitStimulusF)
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

data Object
  = Object
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type Agent :: Type
data Agent = Agent
  { _agentShortName        :: RichText
  , _agentDescription      :: RichText
  , _agentTitle            :: RichText
  , _agentActionManagement :: ActionManagementFunctions
  , _agentKind             :: AgentKind
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

type World :: Type
data World = World
  { _objectMap         :: GIDToDataMap Object Object
  , _sceneMap          :: GIDToDataMap Scene Scene
  , _globalSemanticMap :: Map Text (Set (GID Object))
  , _agentMap          :: AgentMap
  }
  deriving stock (Eq, Ord, Show)

instance NFData World where
  rnf (World om sm gs am) = rnf om `seq` rnf sm `seq` rnf gs `seq` rnf am

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
data NarrationComputation = LookNarration
                          | StaticNarration Text
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type WorldOutcome :: Type
data WorldOutcome = NarrationEffect NarrationComputation
                  | WitnessEffect NarrationComputation
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type EntityKey :: Type
data EntityKey = SceneKey' (GID Scene)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

-- Action Effect Types

type ActionEffectKey :: Type
data ActionEffectKey = ImplicitStimulusActionKey (GID ImplicitStimulusF)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type ActionEffectKeyF :: Type
type ActionEffectKeyF = GID Agent -> ActionEffectKey -> GameComputation Identity ()

type ImplicitStimulusF :: Type
data ImplicitStimulusF = ImplicitStimulusF ActionEffectKeyF
                       | ImplicitNoStimulusF ActionEffectKeyF

type ImplicitStimulusMap :: Type
type ImplicitStimulusMap = Map (GID ImplicitStimulusF) ImplicitStimulusF

type WitnessEffectF :: Type
type WitnessEffectF = GID Agent -> GID Agent -> NarrationComputation -> GameComputation Identity ()

type WitnessF :: Type
data WitnessF = WitnessF WitnessEffectF

type WitnessMap :: Type
type WitnessMap = Map (GID WitnessF) WitnessF

-- Registries

type ActionMaps :: Type
data ActionMaps = ActionMaps
  { _implicitStimulusMap :: ImplicitStimulusMap
  }

emptyActionMaps :: ActionMaps
emptyActionMaps = ActionMaps { _implicitStimulusMap = mempty }

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

type ComputationContext :: Type
data ComputationContext = ComputationContext
  { _ctxPossibilityGraph :: PossibilityGraph
  }

type GameComputation :: (Type -> Type) -> Type -> Type
newtype GameComputation m a = GameComputation { runGameComputation :: ReaderT ComputationContext (ExceptT Text (GameStateT m)) a }
  deriving newtype
    ( Applicative
    , Functor
    , Monad
    , MonadError Text
    , MonadReader ComputationContext
    , MonadState GameState
    )

instance MonadTrans GameComputation where
  lift = GameComputation . lift . lift . lift

-- PossibilityGraph

type PossibilityGraph :: Type
data PossibilityGraph = PossibilityGraph
  { _entityActionEffects :: EntityActionRegistry
  , _worldOutcomeEffects :: WorldOutcomeRegistry
  , _witnessMap          :: WitnessMap
  , _newUserStartScene   :: GID Scene
  , _newUserMkAgent      :: Text -> Agent
  }

-- Defaults

defaultScene :: Scene
defaultScene = Scene
  { _title                 = mempty
  , _sceneDescription      = mempty
  , _sceneActionManagement = ActionManagementFunctions mempty
  , _sceneAgents           = mempty
  }

defaultWorld :: World
defaultWorld = World
  { _objectMap              = GIDToDataMap mempty
  , _sceneMap               = GIDToDataMap mempty
  , _globalSemanticMap      = mempty
  , _agentMap               = AgentMap mempty
  }

-- Template Haskell (single stage — all types visible)

derivingTypeScriptDefinition ''SessionId
derivingTypeScriptDefinition ''Narration
makeLenses ''ActionManagementFunctions
makeLenses ''GIDToDataMap
makeLenses ''Agent
makeLenses ''AgentMap
makeLenses ''Scene
makeLenses ''World
makeLenses ''Narration
makeLenses ''NarrationMap
makeLenses ''Evaluator
makeLenses ''GameState
makeLenses ''ComputationContext
makeLenses ''ActionMaps
makeLenses ''PossibilityGraph

#ifdef TESTING
deriving newtype instance Arbitrary SessionId
deriving via (GenericArbitrary Narration) instance Arbitrary Narration
#endif
