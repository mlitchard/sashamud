{-# LANGUAGE QuasiQuotes #-}

module MigrationSpec (spec) where

import           SashaPrelude
  ( Bool (False, True)
  , Either (Left, Right)
  , Eq ((==))
  , IO
  , Int
  , Text
  , pure
  , void
  , ($)
  )

import           API.Types
  ( ParseFailure (ParseFailure)
  , RepairAttempt (RepairAttempt)
  , SlmName (SlmName)
  )
import           Control.Exception (try)
import qualified Data.ByteString.Char8 (pack)
import           Database.PostgreSQL.Simple
  ( Connection
  , Only (Only)
  , Query
  , SqlError
  , connectPostgreSQL
  , execute
  , query_
  )
import           Database.PostgreSQL.Simple.Migration
  ( MigrationResult (MigrationSuccess)
  , defaultOptions
  , runMigrations
  )
import           Database.PostgreSQL.Simple.SqlQQ (sql)
import           Database.PostgreSQL.Simple.Types (PGArray (PGArray))
import           Engine.Simulation.SignalNetwork
  ( insertRepairFailure
  , insertRepairSuccess
  )
import           GHC.IO (FilePath)
import           Grammar.Gbnf (UnparsedSentence (UnparsedSentence))
import           Model.Core (SceneLabel (SceneLabel))
import           Model.Mid (Mid (Mid))
import           Server.Migration (buildCommand, rollback)
import           System.Environment (getEnv)
import           Test.Hspec
  ( Spec
  , describe
  , expectationFailure
  , it
  , runIO
  , shouldBe
  )

spec :: Spec
spec = do
  connStr <- runIO (getEnv "SASHA_DB_CONNSTR")
  migrationsDir <- runIO (getEnv "SASHA_MIGRATIONS_DIR")
  conn <- runIO (connectPostgreSQL (Data.ByteString.Char8.pack connStr))
  migrationTest conn migrationsDir

migrationTest :: Connection -> FilePath -> Spec
migrationTest conn migrationsDir =
  describe "migrations" $ do
    it "database is clean" $ do
      res <- emptyDB conn 0
      res `shouldBe` True
    it "build creates the schema" $ do
      res <- runMigrations conn defaultOptions (buildCommand migrationsDir)
      res `shouldBe` MigrationSuccess
    it "repair tables round trip" $ do
      users :: [Only Int] <- query_ conn insertPlayer
      case users of
        [Only uid] -> do
          insertRepairFailure conn (SceneLabel "lobby") (Mid uid) (UnparsedSentence "pick up the red ball") (ParseFailure "e0") [RepairAttempt "pick red ball" (ParseFailure "e1")] (SlmName "qwen-Qwen3-1.7B-Q8_0")
          insertRepairSuccess conn (SceneLabel "lobby") (Mid uid) (UnparsedSentence "pick up the red ball") "get the red ball" (SlmName "slm-absent")
          failures :: [(Text, Int, Text, Text, PGArray Text, PGArray Text, Text)] <- query_ conn selectFailures
          successes :: [(Text, Int, Text, Text, Text)] <- query_ conn selectSuccesses
          void $ execute conn [sql| DELETE FROM repair_failures WHERE actor = ? |] (Only uid)
          void $ execute conn [sql| DELETE FROM repair_successes WHERE actor = ? |] (Only uid)
          void $ execute conn [sql| DELETE FROM users WHERE user_id = ? |] (Only uid)
          failures `shouldBe` [("lobby", uid, "pick up the red ball", "e0", PGArray ["pick red ball"], PGArray ["e1"], "qwen-Qwen3-1.7B-Q8_0")]
          successes `shouldBe` [("lobby", uid, "pick up the red ball", "get the red ball", "slm-absent")]
        [] -> expectationFailure "insert into users returned no row"
        _  -> expectationFailure "insert into users returned more than one row"
    it "rollback removes the schema" $ do
      res <- runMigrations conn defaultOptions [rollback migrationsDir]
      res `shouldBe` MigrationSuccess
    it "only schema_migrations remains" $ do
      res <- emptyDB conn 1
      res `shouldBe` True

insertPlayer :: Query
insertPlayer =
  [sql|
    INSERT INTO users (status, role_id, activated_on, player_name)
      SELECT 'active', role_id, now(), 'tester' FROM roles WHERE name = 'player'
      RETURNING user_id
  |]

selectFailures :: Query
selectFailures =
  [sql|
    SELECT scene, actor, unparsed_sentence, parse_error, attempts, attempt_errors, slm.name
      FROM repair_failures JOIN slm USING (slm_id)
  |]

selectSuccesses :: Query
selectSuccesses =
  [sql|
    SELECT scene, actor, unparsed_sentence, rewrite, slm.name
      FROM repair_successes JOIN slm USING (slm_id)
  |]

emptyDB :: Connection -> Int -> IO Bool
emptyDB conn target = do
  res :: Either SqlError [Only Int] <- try (query_ conn emptyDBQuery)
  pure $ case res of
    Left _                 -> False
    Right [Only numTables] -> target == numTables
    Right _                -> False
  where
    emptyDBQuery :: Query
    emptyDBQuery =
      [sql|
        SELECT count(table_name) FROM information_schema.tables
          WHERE table_schema = 'public'
          AND table_type = 'BASE TABLE'
      |]
