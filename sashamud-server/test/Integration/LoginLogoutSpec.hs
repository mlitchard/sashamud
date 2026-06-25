{-# OPTIONS_GHC -Wno-orphans #-}

module Integration.LoginLogoutSpec (spec) where

import           SashaPrelude
  ( Bool (False, True)
  , Either (Left, Right)
  , Eq ((/=), (==))
  , IO
  , Int
  , Maybe (Just, Nothing)
  , Show (show)
  , Text
  , pure
  , stderr
  , ($)
  , (.)
  , (<>)
  )

import           API.Routes (LoginAPI, LogoutAPI)
import           API.Types
  ( LoginResponse (LoginResponse)
  , MessageTo (Ping)
  , SessionId (SessionId)
  )
import           Control.Concurrent (readMVar, threadDelay)
import           Control.Concurrent.Async (async, cancel, race_)
import           Control.Exception (SomeException, finally, try)
import           Data.Map.Strict (member)
import           Data.Text.Encoding (encodeUtf8)
import           Engine.Simulation.EffectNetwork (gameLoop)
import           Model.WireProtocol (MessageFrom (Pong, SystemMessage))
import           Network.HTTP.Client (defaultManagerSettings, newManager)
import           Network.Wai.Handler.Warp (run)
import           Network.WebSockets
  ( Connection
  , defaultConnectionOptions
  , receiveData
  , runClientWith
  , sendTextData
  )
import           SashaMudWorld (gameState, possibilityGraph)
import           Servant
  ( NoContent (NoContent)
  , Proxy (Proxy)
  , ReqBody
  , type (:>)
  )
import           Servant.Client
  ( BaseUrl (baseUrlPort)
  , ClientEnv
  , ClientM
  , client
  , mkClientEnv
  , parseBaseUrl
  , runClientM
  )
import           Servant.Client.Core
  ( HasClient (Client, clientWithRoute, hoistClientMonad)
  , RunClient
  )
import           Server.App
  ( AppCtx (acConnections, acKnownPlayers, acPlayerMap)
  , GameLog (GameLog)
  , newAppCtx
  )
import           Server.Server (app, deliverOutbound)
import           Server.Validator
  ( PlayerNameUNV (PlayerNameUNV)
  , PlayerNameVAL (PlayerNameVAL)
  , ValidatedBody
  )
import           System.Timeout (timeout)
import           Test.Hspec
  ( Spec
  , around
  , describe
  , expectationFailure
  , it
  , shouldBe
  , shouldSatisfy
  )

-- Servant client adapter for ValidatedBody combinator
instance (RunClient m, HasClient m (ReqBody list unv :> api))
  => HasClient m (ValidatedBody list unv val :> api) where
  type Client m (ValidatedBody list unv val :> api) = Client m (ReqBody list unv :> api)
  clientWithRoute pm _ = clientWithRoute pm (Proxy @(ReqBody list unv :> api))
  hoistClientMonad pm _ = hoistClientMonad pm (Proxy @(ReqBody list unv :> api))

loginClient :: PlayerNameUNV -> ClientM LoginResponse
loginClient = client (Proxy @LoginAPI)

logoutClient :: SessionId -> ClientM NoContent
logoutClient = client (Proxy @LogoutAPI)

testPort :: Int
testPort = 14567

testClientEnv :: IO ClientEnv
testClientEnv = do
  mgr <- newManager defaultManagerSettings
  baseUrl <- parseBaseUrl "http://127.0.0.1"
  pure (mkClientEnv mgr baseUrl { baseUrlPort = testPort })

withTestServer :: ((Int, AppCtx) -> IO ()) -> IO ()
withTestServer action = do
  let logCfg = GameLog stderr
  ctx <- newAppCtx logCfg
  serverThread <- async $ race_
    (race_ (gameLoop ctx gameState possibilityGraph) (deliverOutbound ctx))
    (run testPort (app ctx))
  threadDelay 500000
  action (testPort, ctx) `finally` cancel serverThread

connectWS :: SessionId -> (Connection -> IO a) -> IO a
connectWS (SessionId sid) =
  runClientWith "127.0.0.1" testPort "/ws/game"
    defaultConnectionOptions
    [("Sec-WebSocket-Protocol", encodeUtf8 sid)]

receiveMessageFrom :: Connection -> IO MessageFrom
receiveMessageFrom = receiveData

-- | Drain messages until predicate matches or timeout (microseconds)
receiveUntil :: Connection -> Int -> (MessageFrom -> Bool) -> IO (Maybe MessageFrom)
receiveUntil conn timeoutUs predicate = timeout timeoutUs go
  where
    go = do
      msg <- receiveMessageFrom conn
      if predicate msg then pure msg else go

isHeartbeat :: MessageFrom -> Bool
isHeartbeat (SystemMessage "*** heartbeat") = True
isHeartbeat _                               = False

isPong :: MessageFrom -> Bool
isPong Pong = True
isPong _    = False

isDeparture :: Text -> MessageFrom -> Bool
isDeparture name (SystemMessage msg) = msg == "*** " <> name <> " has departed"
isDeparture _ _                      = False

spec :: Spec
spec = describe "Integration" . around withTestServer $ do

  it "POST /api/game/login with valid name returns sessionId" $ \(_port, _ctx) -> do
    env <- testClientEnv
    result <- runClientM (loginClient (PlayerNameUNV "TestPlayer")) env
    case result of
      Left err -> expectationFailure ("login failed: " <> show err)
      Right (LoginResponse sid) ->
        sid `shouldSatisfy` (/= SessionId "")

  it "POST /api/game/login with empty name returns error" $ \(_port, _ctx) -> do
    env <- testClientEnv
    result <- runClientM (loginClient (PlayerNameUNV "")) env
    case result of
      Left _  -> pure ()
      Right _ -> expectationFailure "empty name should be rejected"

  it "DELETE /api/game/logout removes session" $ \(_port, _ctx) -> do
    env <- testClientEnv
    loginResult <- runClientM (loginClient (PlayerNameUNV "TestPlayer")) env
    case loginResult of
      Left err -> expectationFailure ("login failed: " <> show err)
      Right (LoginResponse sid) -> do
        logoutResult <- runClientM (logoutClient sid) env
        logoutResult `shouldBe` Right NoContent

  it "login after logout produces different sessionId" $ \(_port, _ctx) -> do
    env <- testClientEnv
    r1 <- runClientM (loginClient (PlayerNameUNV "Roundtrip")) env
    case r1 of
      Left err -> expectationFailure ("first login failed: " <> show err)
      Right (LoginResponse sid1) -> do
        _ <- runClientM (logoutClient sid1) env
        r2 <- runClientM (loginClient (PlayerNameUNV "Roundtrip")) env
        case r2 of
          Left err -> expectationFailure ("second login failed: " <> show err)
          Right (LoginResponse sid2) ->
            sid1 `shouldSatisfy` (/= sid2)

  it "invalid sessionId on WebSocket connect is rejected" $ \(_port, _ctx) -> do
    result <- try @SomeException
      (runClientWith "127.0.0.1" testPort "/ws/game"
        defaultConnectionOptions [] (\_ -> pure ()))
    case result of
      Left _  -> pure ()
      Right _ -> expectationFailure "connection without session should be rejected"

  it "login creates agent in agentMap with correct agentShortName" $ \(_port, ctx) -> do
    env <- testClientEnv
    result <- runClientM (loginClient (PlayerNameUNV "AgentTest")) env
    case result of
      Left err -> expectationFailure ("login failed: " <> show err)
      Right (LoginResponse sid) -> do
        threadDelay 2000000
        pMap <- readMVar (acPlayerMap ctx)
        member sid pMap `shouldBe` True
        known <- readMVar (acKnownPlayers ctx)
        member (PlayerNameVAL "AgentTest") known `shouldBe` True

  it "login assigns agent to lobby scene" $ \(_port, _ctx) -> do
    env <- testClientEnv
    r1 <- runClientM (loginClient (PlayerNameUNV "Alice")) env
    r2 <- runClientM (loginClient (PlayerNameUNV "Bob")) env
    case (r1, r2) of
      (Right (LoginResponse sid1), Right (LoginResponse sid2)) ->
        connectWS sid1 $ \conn1 -> do
          _ <- try @SomeException (connectWS sid2 $ \_ -> threadDelay 3000000)
          threadDelay 3000000
          result <- receiveUntil conn1 10000000 (isDeparture "Bob")
          case result of
            Nothing -> expectationFailure "departure not received — agents not in same scene"
            Just _  -> pure ()
      _ -> expectationFailure "both logins should succeed"

  it "heartbeat delivery within timeout" $ \(_port, _ctx) -> do
    env <- testClientEnv
    result <- runClientM (loginClient (PlayerNameUNV "HeartbeatTest")) env
    case result of
      Left err -> expectationFailure ("login failed: " <> show err)
      Right (LoginResponse sid) ->
        connectWS sid $ \conn -> do
          hb <- receiveUntil conn 10000000 isHeartbeat
          case hb of
            Nothing  -> expectationFailure "no heartbeat received within 10s"
            Just msg -> msg `shouldSatisfy` isHeartbeat

  it "multi-player: two players login, both in lobby" $ \(_port, ctx) -> do
    env <- testClientEnv
    r1 <- runClientM (loginClient (PlayerNameUNV "Player1")) env
    r2 <- runClientM (loginClient (PlayerNameUNV "Player2")) env
    case (r1, r2) of
      (Right (LoginResponse sid1), Right (LoginResponse sid2)) -> do
        threadDelay 2000000
        pMap <- readMVar (acPlayerMap ctx)
        member sid1 pMap `shouldBe` True
        member sid2 pMap `shouldBe` True
      _ -> expectationFailure "both logins should succeed"

  it "multi-player: both clients receive heartbeats" $ \(_port, _ctx) -> do
    env <- testClientEnv
    r1 <- runClientM (loginClient (PlayerNameUNV "HB1")) env
    r2 <- runClientM (loginClient (PlayerNameUNV "HB2")) env
    case (r1, r2) of
      (Right (LoginResponse sid1), Right (LoginResponse sid2)) ->
        connectWS sid1 $ \conn1 ->
          connectWS sid2 $ \conn2 -> do
            hb1 <- receiveUntil conn1 10000000 isHeartbeat
            hb2 <- receiveUntil conn2 10000000 isHeartbeat
            case (hb1, hb2) of
              (Just _, Just _) -> pure ()
              _                -> expectationFailure "both players should receive heartbeats"
      _ -> expectationFailure "both logins should succeed"

  it "disconnect: agent removed from lobby scene but stays in agentMap" $ \(_port, ctx) -> do
    env <- testClientEnv
    r1 <- runClientM (loginClient (PlayerNameUNV "Stayer")) env
    r2 <- runClientM (loginClient (PlayerNameUNV "Leaver")) env
    case (r1, r2) of
      (Right (LoginResponse sid1), Right (LoginResponse sid2)) ->
        connectWS sid1 $ \conn1 -> do
          _ <- try @SomeException (connectWS sid2 $ \_ -> threadDelay 3000000)
          threadDelay 3000000
          result <- receiveUntil conn1 10000000 (isDeparture "Leaver")
          case result of
            Nothing -> expectationFailure "departure not received"
            Just _  -> do
              known <- readMVar (acKnownPlayers ctx)
              member (PlayerNameVAL "Leaver") known `shouldBe` True
      _ -> expectationFailure "both logins should succeed"

  it "logout: agent removed from lobby scene, stays in agentMap, maps cleaned" $ \(_port, ctx) -> do
    env <- testClientEnv
    r1 <- runClientM (loginClient (PlayerNameUNV "Witness")) env
    r2 <- runClientM (loginClient (PlayerNameUNV "LogoutTarget")) env
    case (r1, r2) of
      (Right (LoginResponse sid1), Right (LoginResponse sid2)) ->
        connectWS sid1 $ \conn1 ->
          connectWS sid2 $ \_ -> do
            threadDelay 3000000
            _ <- runClientM (logoutClient sid2) env
            threadDelay 3000000
            result <- receiveUntil conn1 10000000 (isDeparture "LogoutTarget")
            case result of
              Nothing -> expectationFailure "departure not received after logout"
              Just _  -> do
                known <- readMVar (acKnownPlayers ctx)
                member (PlayerNameVAL "LogoutTarget") known `shouldBe` True
                conns <- readMVar (acConnections ctx)
                member sid2 conns `shouldBe` False
                pMap <- readMVar (acPlayerMap ctx)
                member sid2 pMap `shouldBe` False
      _ -> expectationFailure "both logins should succeed"

  it "ping: client sends Ping, receives Pong through Rhine network" $ \(_port, _ctx) -> do
    env <- testClientEnv
    result <- runClientM (loginClient (PlayerNameUNV "PingTest")) env
    case result of
      Left err -> expectationFailure ("login failed: " <> show err)
      Right (LoginResponse sid) ->
        connectWS sid $ \conn -> do
          threadDelay 2000000
          sendTextData conn Ping
          pong <- receiveUntil conn 10000000 isPong
          case pong of
            Nothing  -> expectationFailure "no Pong received within 10s"
            Just msg -> msg `shouldBe` Pong
