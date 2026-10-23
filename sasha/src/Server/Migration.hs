module Server.Migration
  ( build
  , buildCommand
  , rollback
  ) where

import           SashaPrelude ((<>))

import           Database.PostgreSQL.Simple.Migration
  ( MigrationCommand (MigrationDirectory, MigrationInitialization)
  )
import           GHC.IO (FilePath)

build :: FilePath -> MigrationCommand
build dir = MigrationDirectory (dir <> "/build")

rollback :: FilePath -> MigrationCommand
rollback dir = MigrationDirectory (dir <> "/rollback")

buildCommand :: FilePath -> [MigrationCommand]
buildCommand dir = [MigrationInitialization, build dir]
