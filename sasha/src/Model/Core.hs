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
    -- * Action Management
  , ActionManagement (DSAManagementKey, ISAManagementKey, AVTargetManagementKey, AVSupportManagementKey, DVManagementKey, DVSurfaceManagementKey)
  , ActionManagementFunctions (ActionManagementFunctions)
  , actionManagementFunctions
  , ActionManagementOperation (AddDirectionalStimulus, AddImplicitStimulus, AddAcquisitionVerb, AddDivestmentVerb)
  , GIDToDataMap (GIDToDataMap)
  , getGIDToDataMap
    -- * Action Effects
  , ActionEffectKey (DirectionalStimulusActionKey, ImplicitStimulusActionKey, AcquisitionalActionKey, DivestmentActionKey)
  , ActionEffectKeyF
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
  , WitnessEffectF
  , WitnessF (WitnessF)
  , WitnessMap
    -- * World Outcomes
  , NarrationComputation (LookNarration, LookAtNarration, StaticNarration)
  , WorldOutcome (NarrationEffect, SpatialRelationshipEffect)
  , SpatialRelationshipComputation (Acquisition, Divestiture)
  , DivestmentTargetType (DivestToSurface')
  , EntityKey (SceneKey', ObjectKey', ActingAgentKey, AgentKey')
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
  , agentWitnessManagement
  , agentKind
  , shortName
  , description
  , objectActionManagement
  , title
  , sceneDescription
  , objectSemanticMap
  , sceneObjects
  , sceneActionManagement
  , sceneAgents
  , sceneMap
  , agentMap
  , sharedActionManagement
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
  ( AcquisitionVerb
  , DirectionalStimulusVerb
  , DivestmentVerb
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
                      | AVTargetManagementKey AcquisitionVerb (GID AcquisitionF)
                      | AVSupportManagementKey AcquisitionVerb (GID AcquisitionF)
                      | DVManagementKey DivestmentVerb (GID DivestmentF)
                      | DVSurfaceManagementKey DivestmentVerb (GID DivestmentF)
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
  , _objectSemanticMap     :: Map Text (Set (GID Object))
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
                         | Inventory (GID Agent)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type SpatialRelationshipMap :: Type
newtype SpatialRelationshipMap = SpatialRelationshipMap { _unSpatialRelationshipMap :: Map EntityID (Set SpatialRelationship) }
  deriving stock (Eq, Ord, Show)
  deriving newtype (NFData)

type World :: Type
data World = World
  { _objectMap               :: GIDToDataMap Object Object
  , _sceneMap                :: GIDToDataMap Scene Scene
  , _globalSemanticMap       :: Map Text (Set (GID Object))
  , _agentMap                :: AgentMap
  , _sharedActionManagement  :: ActionManagementFunctions
  , _sharedWitnessManagement :: Map VerbKey (GID WitnessF)
  , _spatialRelationshipMap  :: SpatialRelationshipMap
  , _declaredSceneGIDs       :: Map SceneLabel (GID Scene)
  , _declaredObjectGIDs      :: Map ObjectLabel (GID Object)
  }
  deriving stock (Eq, Ord, Show)

instance NFData World where
  rnf (World om sm gs am sam swm srm dsg dog) = rnf om `seq` rnf sm `seq` rnf gs `seq` rnf am `seq` rnf sam `seq` rnf swm `seq` rnf srm `seq` rnf dsg `seq` rnf dog

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

type DivestmentTargetType :: Type
data DivestmentTargetType
  = DivestToSurface'
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type SpatialRelationshipComputation :: Type
data SpatialRelationshipComputation = Acquisition EntityID EntityID
                                    | Divestiture (GID Object) (GID Object) DivestmentTargetType
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type WorldOutcome :: Type
data WorldOutcome = NarrationEffect NarrationComputation
                  | SpatialRelationshipEffect SpatialRelationshipComputation
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type EntityKey :: Type
data EntityKey = SceneKey' (GID Scene)
               | ObjectKey' (GID Object)
               | ActingAgentKey
               | AgentKey' (GID Agent)
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
  , _objectSemanticMap     = mempty
  , _sceneObjects          = mempty
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
  , _sharedActionManagement  = ActionManagementFunctions mempty
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
  , _actionMaps      = emptyActionMaps
  , _possibilityGraph = PossibilityGraph
      { _entityActionEffects = mempty
      , _worldOutcomeEffects = mempty
      , _witnessMap          = mempty
      , _newUserStartScene   = Nothing
      , _newUserMkAgent      = Nothing
      }
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
