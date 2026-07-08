{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use newtype instead of data" #-}

module Model.Core
  ( -- * Entity Types
    Agent (..)
  , AgentKind (PlayerAgent, FixtureAgent)
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
  , ActionManagement (ISAManagementKey)
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
    -- * World Outcomes
  , NarrationComputation (LookNarration, StaticNarration)
  , WorldOutcome (NarrationEffect)
  , EntityKey (SceneKey')
    -- * Witness System
  , WitnessGenerate (WitnessGenerate, runWitnessGenerate)
  , WitnessFilter (WitnessFilter, runWitnessFilter)
  , WitnessEffect (WitnessEffect)
  , WitnessMap (WitnessMap)
  , getWitnessMap
  , witnessGenerate
  , witnessFilter
    -- * Registries
  , ActionMaps (ActionMaps)
  , implicitStimulusMap
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
  , agentCurrentScene
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
  , actionMaps
  , entityActionEffects
  , worldOutcomeEffects
  , ctxPossibilityGraph
  , ctxWitnessMap
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
import           Data.Map.Strict (Map)
import           Data.Set (Set)
import           Grammar.Parser.Atomics.Verbs (ImplicitStimulusVerb)
import           Grammar.Parser.Composites.Model (Sentence)
import           Lens.Micro.Platform (makeLenses)
import           Model.GID (GID)
import           Model.RichText (RichText)
#ifdef TESTING
import           Test.QuickCheck (Arbitrary)
import           Test.QuickCheck.Instances.Text ()
#endif

-- Action Management

type ActionManagement :: Type
data ActionManagement = ISAManagementKey ImplicitStimulusVerb (GID ImplicitStimulusF)
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
  = PlayerAgent
  | FixtureAgent
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

data Object
  = Object
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type Agent :: Type
data Agent = Agent
  { _agentShortName        :: Text
  , _agentDescription      :: RichText
  , _agentTitle            :: Text
  , _agentActionManagement :: ActionManagementFunctions
  , _agentCurrentScene     :: GID Scene
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

type Narration :: Type
data Narration = Narration
  { _playerAction      :: [RichText]
  , _actionConsequence :: [RichText]
  , _presenceListing   :: [RichText]
  , _actionEpilogue    :: [RichText]
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)
  deriving (Monoid, Semigroup)
    via (Generically Narration)

type NarrationMap :: Type
newtype NarrationMap = NarrationMap { _unNarrationMap :: Map (GID Agent) Narration }
  deriving stock (Eq, Ord, Show)
  deriving newtype (NFData)

-- World Outcomes

type NarrationComputation :: Type
data NarrationComputation = LookNarration
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

-- Witness System

type WitnessGenerate :: Type
newtype WitnessGenerate = WitnessGenerate { runWitnessGenerate :: GID Agent -> GameComputation Identity RichText }

type WitnessFilter :: Type
newtype WitnessFilter = WitnessFilter { runWitnessFilter :: RichText -> GID Agent -> GameComputation Identity RichText }

type WitnessEffect :: Type
data WitnessEffect = WitnessEffect
  { _witnessGenerate :: WitnessGenerate
  , _witnessFilter   :: WitnessFilter
  }

type WitnessMap :: Type
newtype WitnessMap = WitnessMap { _getWitnessMap :: Map ActionEffectKey WitnessEffect }

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

-- GameState

-- Evaluator

type Evaluator :: Type
newtype Evaluator = Evaluator { _runEvaluator :: GID Agent -> Sentence -> GameComputation Identity () }

type GameState :: Type
data GameState = GameState
  { _world        :: World
  , _narrationMap :: NarrationMap
  , _evaluation   :: Evaluator
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
  , _ctxWitnessMap       :: WitnessMap
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
  { _actionMaps          :: ActionMaps
  , _entityActionEffects :: EntityActionRegistry
  , _worldOutcomeEffects :: WorldOutcomeRegistry
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
makeLenses ''ActionManagementFunctions
makeLenses ''GIDToDataMap
makeLenses ''Agent
makeLenses ''AgentMap
makeLenses ''Scene
makeLenses ''World
makeLenses ''Narration
makeLenses ''NarrationMap
makeLenses ''WitnessEffect
makeLenses ''WitnessMap
makeLenses ''Evaluator
makeLenses ''GameState
makeLenses ''ComputationContext
makeLenses ''ActionMaps
makeLenses ''PossibilityGraph

#ifdef TESTING
deriving newtype instance Arbitrary SessionId
#endif
