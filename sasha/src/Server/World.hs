module Server.World
  ( WorldLoadFailure (WorldDecodeFailed, WorldReifyFailed, WorldBuildFailed)
  , loadWorld
  , worldLoadFailureText
  ) where

import           SashaPrelude

import           Control.Monad (foldM)
import           Control.Monad.Except (ExceptT, throwError)
import qualified Data.ByteString (readFile)
import           Data.List (isSuffixOf, sort)
import           Data.Text.Encoding (decodeUtf8')
import           Data.Text.Encoding.Error (UnicodeException)
import           DSL.Builder
  ( WorldBuilderError
  , WorldBuilderResult (WorldBuilderResult, resultCounters, resultGameState)
  , initialBuilderState
  , interpretDSL
  , runWorldBuilder
  )
import           DSL.Reify (reifyDSL)
import           Language.Haskell.Interpreter (InterpreterError)
import           Model.Core (defaultGameState)
import           Server.App (initialCounters)
import           System.Directory (listDirectory)
import           System.Environment (lookupEnv)

type WorldLoadFailure :: Type
data WorldLoadFailure = WorldDecodeFailed UnicodeException
                      | WorldReifyFailed InterpreterError
                      | WorldBuildFailed WorldBuilderError
  deriving stock (Generic, Show)

loadWorld :: ExceptT WorldLoadFailure IO WorldBuilderResult
loadWorld = do
  worldDir <- liftIO (fromMaybe "sashamud-world/src" <$> lookupEnv "SASHA_WORLD_DIR")
  entries  <- liftIO (listDirectory worldDir)
  let programs = sort (filter (".dsl" `isSuffixOf`) entries)
      runSubmission prev file = do
        bytes   <- liftIO (Data.ByteString.readFile (worldDir <> "/" <> file))
        source  <- case decodeUtf8' bytes of
          Left err   -> throwError (WorldDecodeFailed err)
          Right text -> pure (unpack text)
        reified <- liftIO (reifyDSL source)
        case reified of
          Left err  -> throwError (WorldReifyFailed err)
          Right dsl ->
            case runWorldBuilder (interpretDSL dsl) (initialBuilderState (resultGameState prev) (resultCounters prev)) of
              Left err   -> throwError (WorldBuildFailed err)
              Right next -> pure next
  foldM runSubmission (WorldBuilderResult defaultGameState initialCounters) programs

worldLoadFailureText :: WorldLoadFailure -> String
worldLoadFailureText (WorldDecodeFailed err) = "Failed to decode world source: " <> show err
worldLoadFailureText (WorldReifyFailed err) = "Failed to reify world source: " <> show err
worldLoadFailureText (WorldBuildFailed err) = "Failed to build game state: " <> show err
