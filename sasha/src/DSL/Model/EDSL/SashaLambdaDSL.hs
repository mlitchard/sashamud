module DSL.Model.EDSL.SashaLambdaDSL
  ( SashaLambdaDSL (..)
  , declareSceneGID
  , registerScene
  , title
  , sceneDescriptionRich
  , finalizeGameState
  ) where

import SashaPrelude hiding (map)

import Model.Core (GameState, Scene)
import Model.GID (GID)
import Model.RichText (RichText)

type SashaLambdaDSL :: Type -> Type
data SashaLambdaDSL a where
  Pure  :: a -> SashaLambdaDSL a
  Bind  :: SashaLambdaDSL a -> (a -> SashaLambdaDSL b) -> SashaLambdaDSL b
  DeclareSceneGID      :: Text -> SashaLambdaDSL (GID Scene)
  RegisterScene        :: GID Scene -> SashaLambdaDSL Scene -> SashaLambdaDSL ()
  Title                :: Text -> Scene -> SashaLambdaDSL Scene
  SceneDescription     :: RichText -> Scene -> SashaLambdaDSL Scene
  FinalizeGameState    :: SashaLambdaDSL GameState

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

finalizeGameState :: SashaLambdaDSL GameState
finalizeGameState = FinalizeGameState
