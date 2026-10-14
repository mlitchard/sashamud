module ReifySpec (spec) where

import           SashaPrelude
  ( Either (Left, Right)
  , Maybe (Just, Nothing)
  , pure
  , show
  , ($)
  )

import           Control.Monad.Except (runExceptT)
import           DSL.Reify (reifyDSL)
import           Language.Haskell.Interpreter (InterpreterError (WontCompile))
import           Server.World (loadWorld, worldLoadFailureText)
import           System.Environment (lookupEnv)
import           Test.Hspec (Spec, describe, expectationFailure, it)

spec :: Spec
spec = describe "reifyDSL" $ do
    it "loads the world from SASHA_WORLD_DIR" $ do
        worldDir <- lookupEnv "SASHA_WORLD_DIR"
        case worldDir of
            Nothing  -> expectationFailure "SASHA_WORLD_DIR unset"
            Just dir -> do
                result <- runExceptT (loadWorld dir)
                case result of
                    Right _  -> pure ()
                    Left err -> expectationFailure (worldLoadFailureText err)
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
