module DSL.BuilderSpec (spec) where

import           Control.Monad.Except (runExceptT)
import           Data.Map.Strict (lookup, size)
import qualified Data.Set (insert, member)
import           DSL.Builder
  ( WorldBuilderError (DuplicateObjectGID, DuplicateSceneGID, InvalidObjectGID, InvalidSceneGID, MissingNewUserAgent, UndeclaredObjectLabel, UndeclaredSceneLabel)
  , WorldBuilderResult (resultChanges, resultCounters, resultGameState)
  , WorldChange (NewUserAgentModified, NewUserRegistered, ObjectCreated, ObjectModified, SceneCreated, SceneModified)
  , initialBuilderState
  , interpretDSL
  , runWorldBuilder
  , worldBuilderErrorText
  , worldChangeText
  )
import           DSL.Model.EDSL.SashaLambdaDSL
  ( declareObjectGID
  , declareSceneGID
  , description
  , finalizeGameState
  , modifyNewUserAgent
  , modifyObject
  , modifyScene
  , newUser
  , registerObject
  , registerScene
  , sceneDescriptionRich
  )
import           Lens.Micro.Platform (ix, view, (%~), (&), (.~))
import           Model.Core
  ( ObjectLabel (ObjectLabel)
  , SceneLabel (SceneLabel)
  , actionMaps
  , agentShortName
  , defaultGameState
  , defaultObject
  , defaultScene
  , getGIDToDataMap
  , implicitStimulusMap
  , newUserMkAgent
  , objectMap
  , possibilityGraph
  , sceneAgents
  , sceneDescription
  , sceneMap
  , title
  , world
  )
import qualified Model.Core (description)
import           Model.GID (GID (GID))
import           Model.RichText (TextColor (White), colored, plain, toPlainText)
import           SashaPrelude
  ( Bool (True)
  , Either (Left, Right)
  , Maybe (Just, Nothing)
  , pack
  , pure
  , show
  , ($)
  , (.)
  , (<>)
  , (>>)
  , (>>=)
  )
import           Server.App (initialCounters)
import           Server.World (loadWorld, worldLoadFailureText)
import           System.Environment (lookupEnv)
import           Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)

spec :: Spec
spec = describe "DSL.Builder" $ do
  it "runWorldBuilder produces GameState with lobby scene" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result -> do
            let scenes = view (world . sceneMap . getGIDToDataMap) (resultGameState result)
            size scenes `shouldBe` 1

  it "lobby scene has correct title" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result -> do
            let scenes = view (world . sceneMap . getGIDToDataMap) (resultGameState result)
            case lookup (GID 0) scenes of
              Just lobby ->
                view title lobby `shouldBe` "the lobby"
              Nothing -> expectationFailure "lobby scene not found at GID 0"

  it "lobby scene has description" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result -> do
            let scenes = view (world . sceneMap . getGIDToDataMap) (resultGameState result)
            case lookup (GID 0) scenes of
              Just lobby ->
                toPlainText (view sceneDescription lobby) `shouldBe` "A spacious lobby with high ceilings."
              Nothing -> expectationFailure "lobby scene not found at GID 0"

  it "implicitStimulusMap has two look actions" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result ->
            size (view (actionMaps . implicitStimulusMap) (resultGameState result)) `shouldBe` 2

  it "the last world file reports the ball creation" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result ->
            resultChanges result `shouldBe` [ObjectCreated (GID 1)]

  it "an amendment reports the scene and object it changed" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result -> do
            let amendment = modifyScene (SceneLabel "lobby") (sceneDescriptionRich (colored White "x")) >> modifyObject (ObjectLabel "ball") (description (colored White "y")) >> finalizeGameState
            case runWorldBuilder (interpretDSL amendment) (initialBuilderState (resultGameState result) (resultCounters result)) of
              Left err -> expectationFailure (show err)
              Right amended ->
                resultChanges amended `shouldBe` [SceneModified (SceneLabel "lobby"), ObjectModified (ObjectLabel "ball")]

  it "world changes render to their lines" $ do
    worldChangeText (SceneCreated (GID 0)) `shouldBe` "Scene created: " <> pack (show (GID 0))
    worldChangeText (ObjectCreated (GID 1)) `shouldBe` "Object created: " <> pack (show (GID 1))
    worldChangeText (SceneModified (SceneLabel "lobby")) `shouldBe` "Scene modified: lobby"
    worldChangeText (ObjectModified (ObjectLabel "ball")) `shouldBe` "Object modified: ball"
    worldChangeText NewUserAgentModified `shouldBe` "New user agent modified"
    worldChangeText (NewUserRegistered (GID 0)) `shouldBe` "New user registered in " <> pack (show (GID 0))

  it "builder errors render to their lines" $ do
    worldBuilderErrorText (UndeclaredSceneLabel (SceneLabel "nowhere")) `shouldBe` "Undeclared scene label: nowhere"
    worldBuilderErrorText (UndeclaredObjectLabel (ObjectLabel "nothing")) `shouldBe` "Undeclared object label: nothing"
    worldBuilderErrorText MissingNewUserAgent `shouldBe` "No new user agent to modify"
    worldBuilderErrorText (InvalidObjectGID (GID 3) "Object not registered") `shouldBe` "Invalid object " <> pack (show (GID 3)) <> ": Object not registered"
    worldBuilderErrorText (InvalidSceneGID (GID 3) "Scene not registered") `shouldBe` "Invalid scene " <> pack (show (GID 3)) <> ": Scene not registered"
    worldBuilderErrorText (DuplicateSceneGID (GID 3) "Scene already registered") `shouldBe` "Duplicate scene " <> pack (show (GID 3)) <> ": Scene already registered"
    worldBuilderErrorText (DuplicateObjectGID (GID 3) "Object already registered") `shouldBe` "Duplicate object " <> pack (show (GID 3)) <> ": Object already registered"

  it "amending an undeclared scene label is an error" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result ->
            case runWorldBuilder (interpretDSL (modifyScene (SceneLabel "nowhere") (sceneDescriptionRich (colored White "x")) >> finalizeGameState)) (initialBuilderState (resultGameState result) (resultCounters result)) of
              Left err -> err `shouldBe` UndeclaredSceneLabel (SceneLabel "nowhere")
              Right _ -> expectationFailure "expected an error"

  it "modifyScene changes the description and keeps the scene's agents" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result -> do
            let seeded = resultGameState result & world . sceneMap . getGIDToDataMap . ix (GID 0) . sceneAgents %~ Data.Set.insert (GID 7)
            case runWorldBuilder (interpretDSL (modifyScene (SceneLabel "lobby") (sceneDescriptionRich (colored White "changed")) >> finalizeGameState)) (initialBuilderState seeded (resultCounters result)) of
              Left err -> expectationFailure (show err)
              Right amended ->
                case lookup (GID 0) (view (world . sceneMap . getGIDToDataMap) (resultGameState amended)) of
                  Nothing -> expectationFailure "lobby scene not found at GID 0"
                  Just lobby -> do
                    toPlainText (view sceneDescription lobby) `shouldBe` "changed"
                    Data.Set.member (GID 7) (view sceneAgents lobby) `shouldBe` True

  it "modifyObject changes the object's description" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result ->
            case runWorldBuilder (interpretDSL (modifyObject (ObjectLabel "ball") (description (colored White "blue")) >> finalizeGameState)) (initialBuilderState (resultGameState result) (resultCounters result)) of
              Left err -> expectationFailure (show err)
              Right amended ->
                case lookup (GID 1) (view (world . objectMap . getGIDToDataMap) (resultGameState amended)) of
                  Nothing -> expectationFailure "ball not found at GID 1"
                  Just ball ->
                    toPlainText (view Model.Core.description ball) `shouldBe` "blue"

  it "modifyNewUserAgent changes the template" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result ->
            case runWorldBuilder (interpretDSL (modifyNewUserAgent (\mkAgent -> pure (\name -> mkAgent name & agentShortName .~ plain "amended")) >> finalizeGameState)) (initialBuilderState (resultGameState result) (resultCounters result)) of
              Left err -> expectationFailure (show err)
              Right amended ->
                case view (possibilityGraph . newUserMkAgent) (resultGameState amended) of
                  Nothing -> expectationFailure "no new user template"
                  Just template -> view agentShortName (template "anyone") `shouldBe` plain "amended"

  it "amending an undeclared object label is an error" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result ->
            case runWorldBuilder (interpretDSL (modifyObject (ObjectLabel "nothing") (description (colored White "x")) >> finalizeGameState)) (initialBuilderState (resultGameState result) (resultCounters result)) of
              Left err -> err `shouldBe` UndeclaredObjectLabel (ObjectLabel "nothing")
              Right _ -> expectationFailure "expected an error"

  it "amending a declared but unregistered object is an error" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result ->
            case runWorldBuilder (interpretDSL (declareObjectGID (ObjectLabel "ghost") >> modifyObject (ObjectLabel "ghost") (description (colored White "x")) >> finalizeGameState)) (initialBuilderState (resultGameState result) (resultCounters result)) of
              Left err -> err `shouldBe` InvalidObjectGID (GID 2) "Object not registered"
              Right _ -> expectationFailure "expected an error"

  it "modifyNewUserAgent with no template is an error" $
    case runWorldBuilder (interpretDSL (modifyNewUserAgent pure >> finalizeGameState)) (initialBuilderState defaultGameState initialCounters) of
      Left err -> err `shouldBe` MissingNewUserAgent
      Right _  -> expectationFailure "expected an error"

  it "a known scene label returns its GID" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result ->
            case runWorldBuilder (interpretDSL (declareSceneGID (SceneLabel "lobby") >>= \gid -> registerScene gid (pure defaultScene) >> finalizeGameState)) (initialBuilderState (resultGameState result) (resultCounters result)) of
              Left err -> err `shouldBe` DuplicateSceneGID (GID 0) "Scene already registered"
              Right _ -> expectationFailure "expected a duplicate scene error"

  it "a known object label returns its GID" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result ->
            case runWorldBuilder (interpretDSL (declareObjectGID (ObjectLabel "ball") >>= \gid -> registerObject gid (pure defaultObject) >> finalizeGameState)) (initialBuilderState (resultGameState result) (resultCounters result)) of
              Left err -> err `shouldBe` DuplicateObjectGID (GID 1) "Object already registered"
              Right _ -> expectationFailure "expected a duplicate object error"

  it "a new scene label mints the next GID" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result ->
            case runWorldBuilder (interpretDSL (declareSceneGID (SceneLabel "annex") >>= \gid -> registerScene gid (pure defaultScene) >> finalizeGameState)) (initialBuilderState (resultGameState result) (resultCounters result)) of
              Left err -> expectationFailure (show err)
              Right amended ->
                resultChanges amended `shouldBe` [SceneCreated (GID 1)]

  it "registering and amending the new user are reported" $ do
    worldDir <- lookupEnv "SASHA_WORLD_DIR"
    case worldDir of
      Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
      Just dir -> do
        loaded <- runExceptT (loadWorld dir)
        case loaded of
          Left err -> expectationFailure (worldLoadFailureText err)
          Right result ->
            case view (possibilityGraph . newUserMkAgent) (resultGameState result) of
              Nothing -> expectationFailure "no new user template"
              Just template ->
                case runWorldBuilder (interpretDSL (newUser (GID 0) template >> modifyNewUserAgent pure >> finalizeGameState)) (initialBuilderState (resultGameState result) (resultCounters result)) of
                  Left err -> expectationFailure (show err)
                  Right amended ->
                    resultChanges amended `shouldBe` [NewUserRegistered (GID 0), NewUserAgentModified]
