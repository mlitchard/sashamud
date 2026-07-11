module DSL.Model.EDSL.SashaLambdaDSL
  ( SashaLambdaDSL (..)
  , declareSceneGID
  , registerScene
  , title
  , sceneDescriptionRich
  , declareImplicitStimulusGID
  , createISAManagement
  , sceneBehavior
  , playerBehavior
  , linkWorldOutcomeEffect
  , newUser
  , finalizeGameState
  ) where

import           SashaPrelude hiding (map)

import           Grammar.Parser.Atomics.Verbs (ImplicitStimulusVerb)
import           Model.Core
  ( ActionEffectKey
  , ActionManagement
  , Agent
  , GameState
  , ImplicitStimulusF
  , Scene
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
                            DeclareImplicitStimulusGID :: ImplicitStimulusF -> SashaLambdaDSL (GID ImplicitStimulusF)
                            CreateISAManagement :: ImplicitStimulusVerb -> GID ImplicitStimulusF -> SashaLambdaDSL ActionManagement
                            SceneBehavior :: Scene -> ActionManagement -> SashaLambdaDSL Scene
                            PlayerBehavior :: (Text -> Agent) -> ActionManagement -> SashaLambdaDSL (Text -> Agent)
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

declareImplicitStimulusGID :: ImplicitStimulusF -> SashaLambdaDSL (GID ImplicitStimulusF)
declareImplicitStimulusGID = DeclareImplicitStimulusGID

createISAManagement :: ImplicitStimulusVerb -> GID ImplicitStimulusF -> SashaLambdaDSL ActionManagement
createISAManagement = CreateISAManagement

sceneBehavior :: Scene -> ActionManagement -> SashaLambdaDSL Scene
sceneBehavior = SceneBehavior

playerBehavior :: (Text -> Agent) -> ActionManagement -> SashaLambdaDSL (Text -> Agent)
playerBehavior = PlayerBehavior

linkWorldOutcomeEffect :: ActionEffectKey -> WorldOutcome -> SashaLambdaDSL ()
linkWorldOutcomeEffect = LinkWorldOutcomeEffect

newUser :: GID Scene -> (Text -> Agent) -> SashaLambdaDSL ()
newUser = NewUser

finalizeGameState :: SashaLambdaDSL GameState
finalizeGameState = FinalizeGameState
