{-# LANGUAGE QuasiQuotes #-}

module MigrationSpec (spec) where

import           SashaPrelude
  ( Bool (False, True)
  , Either (Left, Right)
  , Eq ((==))
  , IO
  , Int
  , pure
  , ($)
  )

import           Control.Exception (try)
import qualified Data.ByteString.Char8 (pack)
import           Database.PostgreSQL.Simple
  ( Connection
  , Only (Only)
  , Query
  , SqlError
  , connectPostgreSQL
  , query_
  )
import           Database.PostgreSQL.Simple.Migration
  ( MigrationResult (MigrationSuccess)
  , defaultOptions
  , runMigrations
  )
import           Database.PostgreSQL.Simple.SqlQQ (sql)
import           GHC.IO (FilePath)
import           Server.Migration (buildCommand, rollback)
import           System.Environment (getEnv)
import           Test.Hspec (Spec, describe, it, runIO, shouldBe)

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
    it "rollback removes the schema" $ do
      res <- runMigrations conn defaultOptions [rollback migrationsDir]
      res `shouldBe` MigrationSuccess
    it "only schema_migrations remains" $ do
      res <- emptyDB conn 1
      res `shouldBe` True

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
