module ReifySpec (spec) where

import           SashaPrelude
  ( Either (Left, Right)
  , Maybe (Just, Nothing)
  , Monoid (mempty)
  , pure
  , show
  , when
  , ($)
  , (.)
  , (<>)
  )

import           Control.Monad.Except (runExceptT)
import qualified Data.ByteString (writeFile)
import           Data.Map.Strict (lookup)
import           DSL.Builder (WorldBuilderResult (resultGameState))
import           DSL.Reify (reifyDSL)
import           Language.Haskell.Interpreter (InterpreterError (WontCompile))
import           Lens.Micro.Platform (view)
import           Model.Core (getGIDToDataMap, sceneMap, title, world)
import           Model.GID (GID (GID))
import           Server.World (loadWorld, worldLoadFailureText, worldPrograms)
import           System.Directory
  ( createDirectory
  , doesDirectoryExist
  , getTemporaryDirectory
  , removeDirectoryRecursive
  )
import           System.Environment (lookupEnv)
import           Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)

spec :: Spec
spec = describe "reifyDSL" $ do
    it "loads the world from SASHA_WORLD_DIR" $ do
        worldDir <- lookupEnv "SASHA_WORLD_DIR"
        case worldDir of
            Nothing  -> expectationFailure "SASHA_WORLD_DIR unset"
            Just dir -> do
                loaded <- runExceptT (loadWorld dir)
                case loaded of
                    Right result -> case lookup (GID 0) (view (world . sceneMap . getGIDToDataMap) (resultGameState result)) of
                        Nothing    -> expectationFailure "lobby scene not found at GID 0"
                        Just lobby -> view title lobby `shouldBe` "the lobby"
                    Left err     -> expectationFailure (worldLoadFailureText err)
    it "worldPrograms walks nested directories in sorted order" $ do
        tmpDir <- getTemporaryDirectory
        let root = tmpDir <> "/sasha-world-programs-test"
        existing <- doesDirectoryExist root
        when existing (removeDirectoryRecursive root)
        createDirectory root
        createDirectory (root <> "/b")
        createDirectory (root <> "/c")
        createDirectory (root <> "/c/x")
        Data.ByteString.writeFile (root <> "/a.dsl") mempty
        Data.ByteString.writeFile (root <> "/b/2.dsl") mempty
        Data.ByteString.writeFile (root <> "/b/1.dsl") mempty
        Data.ByteString.writeFile (root <> "/c/x/3.dsl") mempty
        Data.ByteString.writeFile (root <> "/notes.txt") mempty
        paths <- worldPrograms root
        removeDirectoryRecursive root
        paths `shouldBe` [root <> "/a.dsl", root <> "/b/1.dsl", root <> "/b/2.dsl", root <> "/c/x/3.dsl"]
    it "rejects a submission of the wrong type" $ do
        result <- reifyDSL "declareSceneGID"
        case result of
            Left (WontCompile _) -> pure ()
            Left err             -> expectationFailure (show err)
            Right _              -> expectationFailure "expected WontCompile"
    it "rejects a module that is not imported" $ do
        result <- reifyDSL "System.IO.Unsafe.unsafePerformIO"
        case result of
            Left (WontCompile _) -> pure ()
            Left err             -> expectationFailure (show err)
            Right _              -> expectationFailure "expected WontCompile"
