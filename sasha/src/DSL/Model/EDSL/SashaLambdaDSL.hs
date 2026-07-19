module DSL.Model.EDSL.SashaLambdaDSL
  ( SashaLambdaDSL (..)
  , createDSAManagement
  , createISAManagement
  , declareDirectionalStimulusGID
  , declareImplicitStimulusGID
  , declareObjectGID
  , declareSceneGID
  , declareWitnessGID
  , description
  , finalizeGameState
  , linkWorldOutcomeEffect
  , newUser
  , objectBehavior
  , playerBehavior
  , registerObject
  , registerObjectToScene
  , registerScene
  , registerSpatial
  , sceneBehavior
  , sceneDescriptionRich
  , shortName
  , title
  , witnessBehavior
  ) where

import           SashaPrelude hiding (map)

import           Grammar.Parser.Atomics.Verbs
  ( DirectionalStimulusVerb
  , ImplicitStimulusVerb
  )
import           Grammar.Parser.GCase (VerbKey)
import           Model.Core
  ( ActionEffectKey
  , ActionManagement
  , Agent
  , DirectionalStimulusF
  , EntityID
  , GameState
  , ImplicitStimulusF
  , Object
  , Scene
  , SpatialRelationship
  , WitnessF
  , WorldOutcome
  )
import           Model.GID (GID)
import           Model.RichText (RichText)

type SashaLambdaDSL :: Type -> Type
data SashaLambdaDSL a where Pure :: a -> SashaLambdaDSL a
                            Bind :: SashaLambdaDSL a -> (a -> SashaLambdaDSL b) -> SashaLambdaDSL b
                            DeclareSceneGID :: Text -> SashaLambdaDSL (GID Scene)
                            RegisterScene :: GID Scene -> SashaLambdaDSL Scene -> SashaLambdaDSL ()
                            Title :: Text -> Scene -> SashaLambdaDSL Scene
                            SceneDescription :: RichText -> Scene -> SashaLambdaDSL Scene
                            DeclareObjectGID :: SashaLambdaDSL (GID Object)
                            RegisterObject :: GID Object -> SashaLambdaDSL Object -> SashaLambdaDSL ()
                            ShortName :: Text -> Object -> SashaLambdaDSL Object
                            Description :: RichText -> Object -> SashaLambdaDSL Object
                            ObjectBehavior :: Object -> ActionManagement -> SashaLambdaDSL Object
                            RegisterObjectToScene :: GID Scene -> GID Object -> Text -> SashaLambdaDSL ()
                            RegisterSpatial :: EntityID -> SpatialRelationship -> SashaLambdaDSL ()
                            DeclareImplicitStimulusGID :: ImplicitStimulusF -> SashaLambdaDSL (GID ImplicitStimulusF)
                            DeclareDirectionalStimulusGID :: DirectionalStimulusF -> SashaLambdaDSL (GID DirectionalStimulusF)
                            CreateISAManagement :: ImplicitStimulusVerb -> GID ImplicitStimulusF -> SashaLambdaDSL ActionManagement
                            CreateDSAManagement :: DirectionalStimulusVerb -> GID DirectionalStimulusF -> SashaLambdaDSL ActionManagement
                            DeclareWitnessGID :: WitnessF -> SashaLambdaDSL (GID WitnessF)
                            SceneBehavior :: Scene -> ActionManagement -> SashaLambdaDSL Scene
                            PlayerBehavior :: (Text -> Agent) -> ActionManagement -> SashaLambdaDSL (Text -> Agent)
                            WitnessBehavior :: (Text -> Agent) -> VerbKey -> GID WitnessF -> SashaLambdaDSL (Text -> Agent)
                            LinkWorldOutcomeEffect :: ActionEffectKey -> WorldOutcome -> SashaLambdaDSL ()
                            NewUser :: GID Scene -> (Text -> Agent) -> SashaLambdaDSL ()
                            FinalizeGameState :: SashaLambdaDSL GameState

instance Functor SashaLambdaDSL where
  fmap f m = Bind m (Pure . f)

instance Applicative SashaLambdaDSL where
  pure = Pure
  mf <*> ma = Bind mf (\f -> Bind ma (Pure . f))

instance Monad SashaLambdaDSL where
  (>>=) = Bind

declareSceneGID :: Text -> SashaLambdaDSL (GID Scene)
declareSceneGID = DeclareSceneGID

registerScene :: GID Scene -> SashaLambdaDSL Scene -> SashaLambdaDSL ()
registerScene = RegisterScene

title :: Text -> Scene -> SashaLambdaDSL Scene
title = Title

sceneDescriptionRich :: RichText -> Scene -> SashaLambdaDSL Scene
sceneDescriptionRich = SceneDescription

declareObjectGID :: SashaLambdaDSL (GID Object)
declareObjectGID = DeclareObjectGID

registerObject :: GID Object -> SashaLambdaDSL Object -> SashaLambdaDSL ()
registerObject = RegisterObject

shortName :: Text -> Object -> SashaLambdaDSL Object
shortName = ShortName

description :: RichText -> Object -> SashaLambdaDSL Object
description = Description

objectBehavior :: Object -> ActionManagement -> SashaLambdaDSL Object
objectBehavior = ObjectBehavior

registerObjectToScene :: GID Scene -> GID Object -> Text -> SashaLambdaDSL ()
registerObjectToScene = RegisterObjectToScene

registerSpatial :: EntityID -> SpatialRelationship -> SashaLambdaDSL ()
registerSpatial = RegisterSpatial

declareImplicitStimulusGID :: ImplicitStimulusF -> SashaLambdaDSL (GID ImplicitStimulusF)
declareImplicitStimulusGID = DeclareImplicitStimulusGID

declareDirectionalStimulusGID :: DirectionalStimulusF -> SashaLambdaDSL (GID DirectionalStimulusF)
declareDirectionalStimulusGID = DeclareDirectionalStimulusGID

createISAManagement :: ImplicitStimulusVerb -> GID ImplicitStimulusF -> SashaLambdaDSL ActionManagement
createISAManagement = CreateISAManagement

createDSAManagement :: DirectionalStimulusVerb -> GID DirectionalStimulusF -> SashaLambdaDSL ActionManagement
createDSAManagement = CreateDSAManagement

declareWitnessGID :: WitnessF -> SashaLambdaDSL (GID WitnessF)
declareWitnessGID = DeclareWitnessGID

sceneBehavior :: Scene -> ActionManagement -> SashaLambdaDSL Scene
sceneBehavior = SceneBehavior

playerBehavior :: (Text -> Agent) -> ActionManagement -> SashaLambdaDSL (Text -> Agent)
playerBehavior = PlayerBehavior

witnessBehavior :: (Text -> Agent) -> VerbKey -> GID WitnessF -> SashaLambdaDSL (Text -> Agent)
witnessBehavior = WitnessBehavior

linkWorldOutcomeEffect :: ActionEffectKey -> WorldOutcome -> SashaLambdaDSL ()
linkWorldOutcomeEffect = LinkWorldOutcomeEffect

newUser :: GID Scene -> (Text -> Agent) -> SashaLambdaDSL ()
newUser = NewUser

finalizeGameState :: SashaLambdaDSL GameState
finalizeGameState = FinalizeGameState
