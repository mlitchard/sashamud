module Model.Core
  ( -- * Entity Types
    Agent (..)
  , AgentKind (PlayerAgent, FixtureAgent)
  , AgentMap (AgentMap)
  , Scene (..)
  , World (..)
  , Narration (..)
  , Evaluator (Evaluator)
  , SpatialRelationshipMap (SpatialRelationshipMap)
  , PerceptionMap (PerceptionMap)
  , Object
    -- * Session
  , SessionId (SessionId, unSessionId)
    -- * GameState
  , GameState (..)
  , GameStateT (GameStateT, runGameStateT)
  , PossibilityGraph (..)
    -- * Defaults
  , defaultActionManagement
  , defaultScene
  , defaultNarration
  , defaultWorld
  , defaultGameState
  , defaultPossibilityGraph
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
  , spatialRelationshipMap
  , globalSemanticMap
  , perceptionMap
  , playerAction
  , actionConsequence
  , actionEpilogue
  , getAgentMap
  , world
  , narration
  , evaluation
  , actionMaps
  , entityActionEffects
  , worldOutcomeEffects
    -- * Re-exports from Mappings
  , module Model.Core.Mappings
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData (rnf))
import           Control.Monad.Morph (MFunctor)
import           Control.Monad.State (MonadState, StateT)
import           Control.Monad.Trans (MonadTrans (lift))
import           Data.Aeson (FromJSON, ToJSON)
import           Data.Aeson.TypeScript (derivingTypeScriptDefinition)
import           Data.Map.Strict (Map)
import           Data.Set (Set)
import           Lens.Micro.Platform (makeLenses)
import           Model.Core.Mappings
import           Model.GID (GID)
import           Model.RichText (RichText)

-- Session

newtype SessionId = SessionId { unSessionId :: Text }
  deriving stock (Generic, Show)
  deriving newtype (Eq, FromJSON, NFData, Ord, ToJSON)

derivingTypeScriptDefinition ''SessionId

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

type SpatialRelationshipMap :: Type
data SpatialRelationshipMap
  = SpatialRelationshipMap
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type PerceptionMap :: Type
data PerceptionMap
  = PerceptionMap
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type World :: Type
data World = World
  { _objectMap              :: GIDToDataMap Object Object
  , _sceneMap               :: GIDToDataMap Scene Scene
  , _spatialRelationshipMap :: SpatialRelationshipMap
  , _globalSemanticMap      :: Map Text (Set (GID Object))
  , _perceptionMap          :: PerceptionMap
  , _agentMap               :: AgentMap
  }
  deriving stock (Eq, Ord, Show)

instance NFData World where
  rnf (World om sm sr gs pm am) = rnf om `seq` rnf sm `seq` rnf sr `seq` rnf gs `seq` rnf pm `seq` rnf am

type Narration :: Type
data Narration = Narration
  { _playerAction      :: [RichText]
  , _actionConsequence :: [RichText]
  , _actionEpilogue    :: [RichText]
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)
  deriving (Monoid, Semigroup)
    via (Generically Narration)

type Evaluator :: Type
data Evaluator
  = Evaluator
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

-- GameState

type GameState :: Type
data GameState = GameState
  { _world      :: World
  , _narration  :: Narration
  , _evaluation :: Evaluator
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

-- PossibilityGraph

type PossibilityGraph :: Type
data PossibilityGraph = PossibilityGraph
  { _actionMaps          :: ActionMaps
  , _entityActionEffects :: EntityActionRegistry
  , _worldOutcomeEffects :: WorldOutcomeRegistry
  }

-- Defaults

defaultActionManagement :: ActionManagementFunctions
defaultActionManagement = ActionManagementFunctions mempty

defaultScene :: Scene
defaultScene = Scene
  { _title                 = ""
  , _sceneDescription      = mempty
  , _sceneActionManagement = defaultActionManagement
  , _sceneAgents           = mempty
  }

defaultNarration :: Narration
defaultNarration = Narration [] [] []

defaultWorld :: World
defaultWorld = World
  { _objectMap              = GIDToDataMap mempty
  , _sceneMap               = GIDToDataMap mempty
  , _spatialRelationshipMap = SpatialRelationshipMap
  , _globalSemanticMap      = mempty
  , _perceptionMap          = PerceptionMap
  , _agentMap               = AgentMap mempty
  }

defaultGameState :: GameState
defaultGameState = GameState
  { _world      = defaultWorld
  , _narration  = defaultNarration
  , _evaluation = Evaluator
  }

defaultPossibilityGraph :: PossibilityGraph
defaultPossibilityGraph = PossibilityGraph
  { _actionMaps          = emptyActionMaps
  , _entityActionEffects = mempty
  , _worldOutcomeEffects = mempty
  }

-- Lenses

makeLenses ''Agent
makeLenses ''AgentMap
makeLenses ''Scene
makeLenses ''World
makeLenses ''Narration
makeLenses ''GameState
makeLenses ''PossibilityGraph
