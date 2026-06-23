module Server.Session
  ( GameSession (..)
  , GameSessionRegistry
  , newGameRegistry
  , addGameSession
  , lookupGameSession
  , removeGameSession
  ) where

import SashaPrelude

import Control.Concurrent.STM (TMVar, TVar, atomically, modifyTVar', newTVarIO, readTVarIO)
import Data.Map.Strict (Map, delete, insert, lookup)
import Model.WireProtocol (WireMessage)

data GameSession = GameSession
  { gsSessionId  :: Text
  , gsSendMsgs   :: TMVar ([WireMessage] -> IO ())
  , gsShutdown   :: TVar Bool
  }

type GameSessionRegistry = TVar (Map Text GameSession)

newGameRegistry :: IO GameSessionRegistry
newGameRegistry = newTVarIO mempty

addGameSession :: GameSessionRegistry -> Text -> GameSession -> IO ()
addGameSession reg sid gs =
  atomically $ modifyTVar' reg (insert sid gs)

lookupGameSession :: GameSessionRegistry -> Text -> IO (Maybe GameSession)
lookupGameSession reg sid = do
  m <- readTVarIO reg
  pure (lookup sid m)

removeGameSession :: GameSessionRegistry -> Text -> IO ()
removeGameSession reg sid =
  atomically $ modifyTVar' reg (delete sid)
