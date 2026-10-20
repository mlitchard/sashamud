module DSL.Model.EDSL.SashaLambdaDSL
  ( SashaLambdaDSL (..)
  , actorTargetBehavior
  , createAVSupportManagement
  , createAVTargetManagement
  , createDSAManagement
  , createDSATargetManagement
  , createDVManagement
  , createDVSurfaceManagement
  , createISAManagement
  , createISATargetManagement
  , declareAcquisitionActionGID
  , declareDirectionalStimulusGID
  , declareDivestmentActionGID
  , declareImplicitStimulusGID
  , declareObjectGID
  , declareSceneGID
  , declareWitnessGID
  , description
  , descriptive
  , finalizeGameState
  , linkActorTargetEntityActionEffect
  , linkActorTargetWorldOutcomeEffect
  , linkEntityActionEffect
  , linkTargetEntityActionEffect
  , linkTargetWorldOutcomeEffect
  , linkWorldOutcomeEffect
  , modifyNewUserAgent
  , modifyObject
  , modifyScene
  , newUser
  , objectBehavior
  , playerBehavior
  , registerObject
  , registerObjectToScene
  , registerScene
  , registerSpatial
  , sceneBehavior
  , sceneDescriptionRich
  , sharedBehavior
  , sharedWitnessBehavior
  , shortName
  , title
  ) where

import           SashaPrelude hiding (map)

import           Grammar.Parser.Atomics.Nouns (DirectionalStimulus)
import           Grammar.Parser.Atomics.Verbs
  ( AcquisitionVerb
  , DirectionalStimulusVerb
  , DivestmentVerb
  , ImplicitStimulusVerb
  )
import           Grammar.Parser.Composites.Nouns (NounPhrase)
import           Grammar.Parser.GCase (NounKey)
import           Model.Core
  ( AcquisitionF
  , ActionEffectKey
  , ActionManagement
  , ActionManagementOperation
  , ActorKey
  , Agent
  , DirectionalStimulusF
  , DivestmentF
  , Entity
  , EntityKey
  , GameState
  , ImplicitStimulusF
  , Object
  , ObjectLabel
  , Scene
  , SceneLabel
  , SpatialRelationship
  , TargetKey
  , WitnessF
  , WorldOutcome
  )
import           Model.GID (GID)
import           Model.RichText (RichText)

type SashaLambdaDSL :: Type -> Type
data SashaLambdaDSL a where Pure :: a -> SashaLambdaDSL a
                            Bind :: SashaLambdaDSL a -> (a -> SashaLambdaDSL b) -> SashaLambdaDSL b
                            DeclareSceneGID :: SceneLabel -> SashaLambdaDSL (GID Scene)
                            RegisterScene :: GID Scene -> SashaLambdaDSL Scene -> SashaLambdaDSL ()
                            Title :: Text -> Scene -> SashaLambdaDSL Scene
                            SceneDescription :: RichText -> Scene -> SashaLambdaDSL Scene
                            DeclareObjectGID :: ObjectLabel -> SashaLambdaDSL (GID Object)
                            RegisterObject :: GID Object -> SashaLambdaDSL Object -> SashaLambdaDSL ()
                            ShortName :: Text -> Object -> SashaLambdaDSL Object
                            Description :: RichText -> Object -> SashaLambdaDSL Object
                            Descriptive :: NounPhrase DirectionalStimulus -> Object -> SashaLambdaDSL Object
                            ObjectBehavior :: Object -> ActionManagement -> SashaLambdaDSL Object
                            RegisterObjectToScene :: GID Scene -> GID Object -> NounKey -> SashaLambdaDSL ()
                            RegisterSpatial :: EntityKey -> SpatialRelationship -> SashaLambdaDSL ()
                            DeclareImplicitStimulusGID :: ImplicitStimulusF -> SashaLambdaDSL (GID ImplicitStimulusF)
                            DeclareDirectionalStimulusGID :: DirectionalStimulusF -> SashaLambdaDSL (GID DirectionalStimulusF)
                            CreateISAManagement :: ImplicitStimulusVerb -> GID ImplicitStimulusF -> SashaLambdaDSL ActionManagement
                            CreateDSAManagement :: DirectionalStimulusVerb -> GID DirectionalStimulusF -> SashaLambdaDSL ActionManagement
                            CreateISATargetManagement :: ImplicitStimulusVerb -> GID ImplicitStimulusF -> SashaLambdaDSL ActionManagement
                            CreateDSATargetManagement :: DirectionalStimulusVerb -> GID DirectionalStimulusF -> SashaLambdaDSL ActionManagement
                            DeclareAcquisitionActionGID :: AcquisitionF -> SashaLambdaDSL (GID AcquisitionF)
                            DeclareDivestmentActionGID :: DivestmentF -> SashaLambdaDSL (GID DivestmentF)
                            CreateAVTargetManagement :: AcquisitionVerb -> GID AcquisitionF -> SashaLambdaDSL ActionManagement
                            CreateAVSupportManagement :: AcquisitionVerb -> GID AcquisitionF -> SashaLambdaDSL ActionManagement
                            CreateDVManagement :: DivestmentVerb -> GID DivestmentF -> SashaLambdaDSL ActionManagement
                            CreateDVSurfaceManagement :: DivestmentVerb -> GID DivestmentF -> SashaLambdaDSL ActionManagement
                            DeclareWitnessGID :: WitnessF -> SashaLambdaDSL (GID WitnessF)
                            SceneBehavior :: Scene -> ActionManagement -> SashaLambdaDSL Scene
                            PlayerBehavior :: (Text -> Agent) -> ActionManagement -> SashaLambdaDSL (Text -> Agent)
                            SharedBehavior :: Entity -> ActionManagement -> SashaLambdaDSL ()
                            ActorTargetBehavior :: ActorKey -> TargetKey -> ActionManagement -> SashaLambdaDSL ()
                            SharedWitnessBehavior :: Entity -> GID WitnessF -> SashaLambdaDSL ()
                            LinkWorldOutcomeEffect :: Entity -> ActionEffectKey -> WorldOutcome -> SashaLambdaDSL ()
                            LinkTargetWorldOutcomeEffect :: TargetKey -> ActionEffectKey -> WorldOutcome -> SashaLambdaDSL ()
                            LinkActorTargetWorldOutcomeEffect :: ActorKey -> TargetKey -> ActionEffectKey -> WorldOutcome -> SashaLambdaDSL ()
                            LinkEntityActionEffect :: Entity -> ActionEffectKey -> EntityKey -> ActionManagementOperation -> SashaLambdaDSL ()
                            LinkTargetEntityActionEffect :: TargetKey -> ActionEffectKey -> EntityKey -> ActionManagementOperation -> SashaLambdaDSL ()
                            LinkActorTargetEntityActionEffect :: ActorKey -> TargetKey -> ActionEffectKey -> EntityKey -> ActionManagementOperation -> SashaLambdaDSL ()
                            NewUser :: GID Scene -> (Text -> Agent) -> SashaLambdaDSL ()
                            ModifyScene :: SceneLabel -> (Scene -> SashaLambdaDSL Scene) -> SashaLambdaDSL ()
                            ModifyObject :: ObjectLabel -> (Object -> SashaLambdaDSL Object) -> SashaLambdaDSL ()
                            ModifyNewUserAgent :: ((Text -> Agent) -> SashaLambdaDSL (Text -> Agent)) -> SashaLambdaDSL ()
                            FinalizeGameState :: SashaLambdaDSL GameState

instance Functor SashaLambdaDSL where
  fmap f m = Bind m (Pure . f)

instance Applicative SashaLambdaDSL where
  pure = Pure
  mf <*> ma = Bind mf (\f -> Bind ma (Pure . f))

instance Monad SashaLambdaDSL where
  (>>=) = Bind

declareSceneGID :: SceneLabel -> SashaLambdaDSL (GID Scene)
declareSceneGID = DeclareSceneGID

registerScene :: GID Scene -> SashaLambdaDSL Scene -> SashaLambdaDSL ()
registerScene = RegisterScene

title :: Text -> Scene -> SashaLambdaDSL Scene
title = Title

sceneDescriptionRich :: RichText -> Scene -> SashaLambdaDSL Scene
sceneDescriptionRich = SceneDescription

declareObjectGID :: ObjectLabel -> SashaLambdaDSL (GID Object)
declareObjectGID = DeclareObjectGID

registerObject :: GID Object -> SashaLambdaDSL Object -> SashaLambdaDSL ()
registerObject = RegisterObject

shortName :: Text -> Object -> SashaLambdaDSL Object
shortName = ShortName

description :: RichText -> Object -> SashaLambdaDSL Object
description = Description

descriptive :: NounPhrase DirectionalStimulus -> Object -> SashaLambdaDSL Object
descriptive = Descriptive

objectBehavior :: Object -> ActionManagement -> SashaLambdaDSL Object
objectBehavior = ObjectBehavior

registerObjectToScene :: GID Scene -> GID Object -> NounKey -> SashaLambdaDSL ()
registerObjectToScene = RegisterObjectToScene

registerSpatial :: EntityKey -> SpatialRelationship -> SashaLambdaDSL ()
registerSpatial = RegisterSpatial

declareImplicitStimulusGID :: ImplicitStimulusF -> SashaLambdaDSL (GID ImplicitStimulusF)
declareImplicitStimulusGID = DeclareImplicitStimulusGID

declareDirectionalStimulusGID :: DirectionalStimulusF -> SashaLambdaDSL (GID DirectionalStimulusF)
declareDirectionalStimulusGID = DeclareDirectionalStimulusGID

createISAManagement :: ImplicitStimulusVerb -> GID ImplicitStimulusF -> SashaLambdaDSL ActionManagement
createISAManagement = CreateISAManagement

createDSAManagement :: DirectionalStimulusVerb -> GID DirectionalStimulusF -> SashaLambdaDSL ActionManagement
createDSAManagement = CreateDSAManagement

createISATargetManagement :: ImplicitStimulusVerb -> GID ImplicitStimulusF -> SashaLambdaDSL ActionManagement
createISATargetManagement = CreateISATargetManagement

createDSATargetManagement :: DirectionalStimulusVerb -> GID DirectionalStimulusF -> SashaLambdaDSL ActionManagement
createDSATargetManagement = CreateDSATargetManagement

declareAcquisitionActionGID :: AcquisitionF -> SashaLambdaDSL (GID AcquisitionF)
declareAcquisitionActionGID = DeclareAcquisitionActionGID

declareDivestmentActionGID :: DivestmentF -> SashaLambdaDSL (GID DivestmentF)
declareDivestmentActionGID = DeclareDivestmentActionGID

createAVTargetManagement :: AcquisitionVerb -> GID AcquisitionF -> SashaLambdaDSL ActionManagement
createAVTargetManagement = CreateAVTargetManagement

createAVSupportManagement :: AcquisitionVerb -> GID AcquisitionF -> SashaLambdaDSL ActionManagement
createAVSupportManagement = CreateAVSupportManagement

createDVManagement :: DivestmentVerb -> GID DivestmentF -> SashaLambdaDSL ActionManagement
createDVManagement = CreateDVManagement

createDVSurfaceManagement :: DivestmentVerb -> GID DivestmentF -> SashaLambdaDSL ActionManagement
createDVSurfaceManagement = CreateDVSurfaceManagement

declareWitnessGID :: WitnessF -> SashaLambdaDSL (GID WitnessF)
declareWitnessGID = DeclareWitnessGID

sceneBehavior :: Scene -> ActionManagement -> SashaLambdaDSL Scene
sceneBehavior = SceneBehavior

playerBehavior :: (Text -> Agent) -> ActionManagement -> SashaLambdaDSL (Text -> Agent)
playerBehavior = PlayerBehavior

sharedBehavior :: Entity -> ActionManagement -> SashaLambdaDSL ()
sharedBehavior = SharedBehavior

actorTargetBehavior :: ActorKey -> TargetKey -> ActionManagement -> SashaLambdaDSL ()
actorTargetBehavior = ActorTargetBehavior

sharedWitnessBehavior :: Entity -> GID WitnessF -> SashaLambdaDSL ()
sharedWitnessBehavior = SharedWitnessBehavior

linkWorldOutcomeEffect :: Entity -> ActionEffectKey -> WorldOutcome -> SashaLambdaDSL ()
linkWorldOutcomeEffect = LinkWorldOutcomeEffect

linkTargetWorldOutcomeEffect :: TargetKey -> ActionEffectKey -> WorldOutcome -> SashaLambdaDSL ()
linkTargetWorldOutcomeEffect = LinkTargetWorldOutcomeEffect

linkActorTargetWorldOutcomeEffect :: ActorKey -> TargetKey -> ActionEffectKey -> WorldOutcome -> SashaLambdaDSL ()
linkActorTargetWorldOutcomeEffect = LinkActorTargetWorldOutcomeEffect

linkEntityActionEffect :: Entity -> ActionEffectKey -> EntityKey -> ActionManagementOperation -> SashaLambdaDSL ()
linkEntityActionEffect = LinkEntityActionEffect

linkTargetEntityActionEffect :: TargetKey -> ActionEffectKey -> EntityKey -> ActionManagementOperation -> SashaLambdaDSL ()
linkTargetEntityActionEffect = LinkTargetEntityActionEffect

linkActorTargetEntityActionEffect :: ActorKey -> TargetKey -> ActionEffectKey -> EntityKey -> ActionManagementOperation -> SashaLambdaDSL ()
linkActorTargetEntityActionEffect = LinkActorTargetEntityActionEffect

newUser :: GID Scene -> (Text -> Agent) -> SashaLambdaDSL ()
newUser = NewUser

modifyScene :: SceneLabel -> (Scene -> SashaLambdaDSL Scene) -> SashaLambdaDSL ()
modifyScene = ModifyScene

modifyObject :: ObjectLabel -> (Object -> SashaLambdaDSL Object) -> SashaLambdaDSL ()
modifyObject = ModifyObject

modifyNewUserAgent :: ((Text -> Agent) -> SashaLambdaDSL (Text -> Agent)) -> SashaLambdaDSL ()
modifyNewUserAgent = ModifyNewUserAgent

finalizeGameState :: SashaLambdaDSL GameState
finalizeGameState = FinalizeGameState
