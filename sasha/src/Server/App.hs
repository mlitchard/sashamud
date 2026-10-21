{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use newtype instead of data" #-}

module Server.App
  ( AppCtx (..)
  , AppM (..)
  , Environment (Development, Production)
  , GameLog (..)
  , OidcConfig (..)
  , PendingRepair (PendingRepair)
  , SessionPhase (SessionPhase)
  , SessionState (AwaitingSocket, AwaitingJoin, InGame)
  , newAppCtx
  , sessionGid
  , sessionPlayerName
  , sessionSend
  ) where

import           SashaPrelude

import           API.Types
  ( MessageTo
  , ParseFailure
  , PlayerJoined
  , RepairAttempt
  , Routed
  , SessionId
  )
import           Control.Concurrent (MVar, newMVar)
import           Control.Concurrent.STM (TChan, newTChanIO)
import           Control.Monad.Except (MonadError)
import           Control.Monad.Reader (MonadReader, ReaderT)
import           Data.IORef (IORef, newIORef)
import           Data.Map.Strict (Map)
import           Data.Pool (Pool)
import           Data.Time.Clock (UTCTime)
import           Database.PostgreSQL.Simple (Connection)
import           DSL.Model.EDSL.SashaLambdaDSL (SashaLambdaDSL)
import           GHC.IO (FilePath)
import           Grammar.Gbnf (UnparsedSentence)
import           Model.Account
  ( ClientId
  , ClientSecret
  , CodeVerifier
  , OidcBaseUrl
  , OidcState
  , RedirectUri
  , StartMode
  )
import           Model.Core (Agent, BuilderCounters, GameState)
import           Model.GID (GID)
import           Model.RichText (RichText)
import           Model.WireProtocol (MessageFrom)
import           Network.HTTP.Client (Manager)
import           Servant (Handler)
import           Servant.Server (ServerError)
import           Server.Validator (PlayerNameVAL)

data GameLog = GameLog
  { logHandle :: Handle
  , logPath   :: Maybe FilePath
  }

data SessionPhase = SessionPhase PlayerNameVAL (GID Agent) SessionState

data SessionState = AwaitingSocket
                  | AwaitingJoin ([MessageFrom] -> IO ())
                  | InGame ([MessageFrom] -> IO ())

data PendingRepair = PendingRepair UnparsedSentence ParseFailure [RepairAttempt]

sessionPlayerName :: SessionPhase -> PlayerNameVAL
sessionPlayerName (SessionPhase name _ _) = name

sessionGid :: SessionPhase -> Maybe (GID Agent)
sessionGid (SessionPhase _ _ AwaitingSocket)   = Nothing
sessionGid (SessionPhase _ _ (AwaitingJoin _)) = Nothing
sessionGid (SessionPhase _ gid (InGame _))     = Just gid

sessionSend :: SessionPhase -> Maybe ([MessageFrom] -> IO ())
sessionSend (SessionPhase _ _ AwaitingSocket)      = Nothing
sessionSend (SessionPhase _ _ (AwaitingJoin send)) = Just send
sessionSend (SessionPhase _ _ (InGame send))       = Just send

newtype AppM a = AppM { unAppM :: ReaderT AppCtx Handler a }
  deriving newtype
    ( Applicative
    , Functor
    , Monad
    , MonadError ServerError
    , MonadIO
    , MonadReader AppCtx
    )

data Environment
  = Development
  | Production

data OidcConfig = OidcConfig
  { ocBaseUrl      :: OidcBaseUrl
  , ocClientId     :: ClientId
  , ocClientSecret :: ClientSecret
  , ocRedirectUri  :: RedirectUri
  }

data AppCtx = AppCtx
  { acInbound :: TChan (Routed MessageTo)
  , acOutbound :: TChan (Routed MessageFrom)
  , acJoinChan :: TChan PlayerJoined
  , acDSLChan :: TChan (Routed (SashaLambdaDSL GameState))
  , acSessions :: MVar (Map SessionId SessionPhase)
  , acBuilderCounters :: IORef BuilderCounters
  , acDbPool :: Pool Connection
  , acOidcConfig :: OidcConfig
  , acHttpManager :: Manager
  , acOidcStates :: MVar (Map OidcState (UTCTime, CodeVerifier, PlayerNameVAL, StartMode))
  , acPendingRepairs :: MVar (Map SessionId PendingRepair)
  , acLastStateViews :: MVar (Map SessionId [RichText])
  , acGameLog :: GameLog
  }

newAppCtx :: GameLog -> Pool Connection -> OidcConfig -> Manager -> BuilderCounters -> IO AppCtx
newAppCtx logCfg pool oidcConfig manager counters = do
  inChan   <- newTChanIO
  outChan  <- newTChanIO
  joinChan <- newTChanIO
  dslChan  <- newTChanIO
  sessions <- newMVar mempty
  builderCounters <- newIORef counters
  oidcStates <- newMVar mempty
  pendingRepairs <- newMVar mempty
  lastStateViews <- newMVar mempty
  pure AppCtx
    { acInbound      = inChan
    , acOutbound     = outChan
    , acJoinChan     = joinChan
    , acDSLChan      = dslChan
    , acSessions     = sessions
    , acBuilderCounters = builderCounters
    , acDbPool       = pool
    , acOidcConfig   = oidcConfig
    , acHttpManager  = manager
    , acOidcStates   = oidcStates
    , acPendingRepairs = pendingRepairs
    , acLastStateViews = lastStateViews
    , acGameLog      = logCfg
    }
