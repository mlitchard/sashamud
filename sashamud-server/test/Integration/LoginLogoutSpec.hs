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
  , elem
  , fmap
  , fromMaybe
  , not
  , pack
  , pure
  , stderr
  , ($)
  , (.)
  , (<>)
  )

import           API.Routes (DSLAPI, LogoutAPI)
import           API.Types
  ( DSLSource (DSLSource)
  , MessageTo (GameCommand, Ping)
  , SessionId (SessionId)
  )
import           Control.Concurrent (readMVar, threadDelay)
import           Control.Concurrent.Async (async, cancel, race_)
import           Control.Exception (SomeException, finally, try)
import qualified Data.ByteString.Char8 (pack)
import           Data.ByteString.Lazy (null)
import           Data.List (lookup)
import           Data.Map.Strict (member)
import           Data.Pool (defaultPoolConfig, newPool, withResource)
import           Data.Text (isPrefixOf, stripPrefix, unlines)
import           Data.Text.Encoding (decodeUtf8', encodeUtf8)
import           Database.PostgreSQL.Simple
  ( Only (Only)
  , close
  , connectPostgreSQL
  , execute
  , query
  )
import           Database.PostgreSQL.Simple.Migration
  ( MigrationResult (MigrationSuccess)
  , defaultOptions
  , runMigrations
  )
import           DSL.Builder (WorldBuilderResult (resultCounters))
import           Engine.Simulation.SignalNetwork (gameLoop)
import           FakeProvider
  ( fakeApp
  , finalLocationThroughFake
  , loginThroughFake
  , newFakeState
  , seedAccount
  )
import           Lens.Micro.Platform (view)
import           Model.Account
  ( ClientId (ClientId)
  , ClientSecret (ClientSecret)
  , OidcBaseUrl (OidcBaseUrl)
  , RedirectUri (RedirectUri)
  )
import           Model.Authorization (RoleName (RoleName))
import           Model.Core (actionConsequence, presenceListing)
import           Model.RichText (toPlainText)
import           Model.WireProtocol
  ( MessageFrom (GameNarration, Pong, SystemMessage)
  )
import           Network.HTTP.Client
  ( Response (responseHeaders, responseStatus)
  , defaultManagerSettings
  , httpLbs
  , newManager
  , parseRequest
  , redirectCount
  )
import           Network.HTTP.Types (Status (Status))
import           Network.Wai.Handler.Warp (run)
import           Network.WebSockets
  ( Connection
  , defaultConnectionOptions
  , receiveData
  , runClientWith
  , sendTextData
  )
import           SashaMudWorld (buildResult, gameState)
import           Servant
  ( AuthProtect
  , NoContent (NoContent)
  , Proxy (Proxy)
  , type (:>)
  )
import           Servant.API.WebSocket (SecWebSocketProtocol)
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
  ( AuthClientData
  , AuthenticatedRequest
  , ClientError (FailureResponse)
  , HasClient (Client, clientWithRoute, hoistClientMonad)
  , Request
  , ResponseF (Response)
  , RunClient
  , addHeader
  , mkAuthenticatedRequest
  )
import           Server.App
  ( AppCtx (acDbPool, acKnownPlayers, acSessions)
  , GameLog (GameLog)
  , OidcConfig (OidcConfig)
  , newAppCtx
  )
import           Server.Authentication (CanDo, tokenDigest)
import           Server.Migration (buildCommand)
import           Server.Server (app, deliverOutbound)
import           Server.Validator (PlayerNameVAL (PlayerNameVAL))
import           System.Environment (lookupEnv)
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

-- Servant client adapter for the CanDo combinator
instance (RunClient m, HasClient m (AuthProtect SecWebSocketProtocol :> api))
  => HasClient m (CanDo r a :> api) where
  type Client m (CanDo r a :> api) = Client m (AuthProtect SecWebSocketProtocol :> api)
  clientWithRoute pm _ = clientWithRoute pm (Proxy @(AuthProtect SecWebSocketProtocol :> api))
  hoistClientMonad pm _ = hoistClientMonad pm (Proxy @(AuthProtect SecWebSocketProtocol :> api))

logoutClient :: SessionId -> ClientM NoContent
logoutClient = client (Proxy @LogoutAPI)

type instance AuthClientData (AuthProtect SecWebSocketProtocol) = SessionId

dslClient :: AuthenticatedRequest (AuthProtect SecWebSocketProtocol) -> DSLSource -> ClientM NoContent
dslClient = client (Proxy @DSLAPI)

makeAuthRequest :: SessionId -> AuthenticatedRequest (AuthProtect SecWebSocketProtocol)
makeAuthRequest sid = mkAuthenticatedRequest sid authenticatedRequest

authenticatedRequest :: SessionId -> Request -> Request
authenticatedRequest (SessionId sid) = addHeader "Sec-WebSocket-Protocol" sid

isErrorCode :: Int -> Either ClientError a -> Bool
isErrorCode _ (Right _) = False
isErrorCode code (Left (FailureResponse _ resp)) =
  case resp of
    (Response (Status scode _) _ _ _) -> scode == code
isErrorCode _ _ = False

testPort :: Int
testPort = 14567

fakePort :: Int
fakePort = 14568

testClientEnv :: IO ClientEnv
testClientEnv = do
  mgr <- newManager defaultManagerSettings
  baseUrl <- parseBaseUrl "http://127.0.0.1"
  pure (mkClientEnv mgr baseUrl { baseUrlPort = testPort })

withTestServer :: ((Int, AppCtx) -> IO ()) -> IO ()
withTestServer action = do
  let logCfg = GameLog stderr
  connStr <- fmap (fromMaybe "dbname=sashamud") (lookupEnv "SASHA_DB_CONNSTR")
  migrationsDir <- fmap (fromMaybe "migrations") (lookupEnv "SASHA_MIGRATIONS_DIR")
  pool <- newPool (defaultPoolConfig (connectPostgreSQL (Data.ByteString.Char8.pack connStr)) close 60 10)
  migrated <- withResource pool (\conn -> runMigrations conn defaultOptions (buildCommand migrationsDir))
  migrated `shouldBe` MigrationSuccess
  manager <- newManager defaultManagerSettings
  fakeState <- newFakeState
  let oidcConfig = OidcConfig
        (OidcBaseUrl ("http://127.0.0.1:" <> pack (show fakePort)))
        (ClientId "sashamud")
        (ClientSecret "sashamud-dev")
        (RedirectUri ("http://127.0.0.1:" <> pack (show testPort) <> "/api/auth/callback"))
  ctx <- newAppCtx logCfg pool oidcConfig manager (resultCounters buildResult)
  serverThread <- async $ race_
    (race_ (gameLoop ctx gameState) (deliverOutbound ctx))
    (race_ (run testPort (app ctx)) (run fakePort (fakeApp fakeState)))
  threadDelay 500000
  action (testPort, ctx) `finally` cancel serverThread

loginAs :: AppCtx -> RoleName -> Text -> IO SessionId
loginAs ctx role name = do
  seedAccount (acDbPool ctx) role (PlayerNameVAL name)
  manager <- newManager defaultManagerSettings
  loginThroughFake manager testPort name

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
isDeparture name (GameNarration narr) =
  name <> " has departed." `elem` fmap toPlainText (view actionConsequence narr)
isDeparture _ _ = False

isLookNarration :: MessageFrom -> Bool
isLookNarration (GameNarration narr) =
  "A spacious lobby with high ceilings." `elem` fmap toPlainText (view actionConsequence narr)
isLookNarration _ = False

hasPresence :: Text -> MessageFrom -> Bool
hasPresence name (GameNarration narr) =
  "Also here: " <> name `elem` fmap toPlainText (view presenceListing narr)
hasPresence _ _ = False

seesObjects :: Text -> MessageFrom -> Bool
seesObjects line (GameNarration narr) =
  line `elem` fmap toPlainText (view actionConsequence narr)
seesObjects _ _ = False

spec :: Spec
spec = describe "Integration" . around withTestServer $ do

  it "GET /api/auth/start redirects to the provider" $ \(_port, _ctx) -> do
    manager <- newManager defaultManagerSettings
    req <- parseRequest ("http://127.0.0.1:" <> show testPort <> "/api/auth/start")
    resp <- httpLbs req { redirectCount = 0 } manager
    case lookup "Location" (responseHeaders resp) of
      Nothing -> expectationFailure "no Location header"
      Just raw -> case decodeUtf8' raw of
        Left _ -> expectationFailure "Location header is not UTF-8"
        Right location ->
          location `shouldSatisfy`
            isPrefixOf ("http://127.0.0.1:" <> pack (show fakePort) <> "/application/o/authorize/")

  it "GET /api/auth/callback with an unknown state returns 401" $ \(_port, _ctx) -> do
    manager <- newManager defaultManagerSettings
    req <- parseRequest ("http://127.0.0.1:" <> show testPort <> "/api/auth/callback?code=wizard&state=bogus")
    resp <- httpLbs req { redirectCount = 0 } manager
    case responseStatus resp of
      Status code _ -> code `shouldBe` 401

  it "login through the provider returns a token" $ \(_port, ctx) -> do
    sid <- loginAs ctx (RoleName "wizard") "TestPlayer"
    sid `shouldSatisfy` (/= SessionId "")

  it "DELETE /api/game/logout removes session" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid <- loginAs ctx (RoleName "wizard") "TestPlayer"
    logoutResult <- runClientM (logoutClient sid) env
    logoutResult `shouldBe` Right NoContent

  it "login after logout produces a different token" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid1 <- loginAs ctx (RoleName "wizard") "Roundtrip"
    _ <- runClientM (logoutClient sid1) env
    sid2 <- loginAs ctx (RoleName "wizard") "Roundtrip"
    sid1 `shouldSatisfy` (/= sid2)

  it "an expired token is rejected" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid@(SessionId token) <- loginAs ctx (RoleName "wizard") "Expired"
    _ <- withResource (acDbPool ctx) $ \conn ->
      execute conn "UPDATE tokens SET expires_at = now() - interval '1 hour' WHERE token_digest = ?"
        (Only (tokenDigest (encodeUtf8 token)))
    result <- runClientM (dslClient (makeAuthRequest sid) (DSLSource worldSource)) env
    isErrorCode 401 result `shouldBe` True

  it "logout stops the token working" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid <- loginAs ctx (RoleName "wizard") "LoggedOut"
    _ <- runClientM (logoutClient sid) env
    result <- runClientM (dslClient (makeAuthRequest sid) (DSLSource worldSource)) env
    isErrorCode 401 result `shouldBe` True

  it "invalid token on WebSocket connect is rejected" $ \(_port, _ctx) -> do
    result <- try @SomeException
      (runClientWith "127.0.0.1" testPort "/ws/game"
        defaultConnectionOptions [] (\_ -> pure ()))
    case result of
      Left _  -> pure ()
      Right _ -> expectationFailure "connection without session should be rejected"

  it "login creates agent in agentMap with correct agentShortName" $ \(_port, ctx) -> do
    sid <- loginAs ctx (RoleName "wizard") "AgentTest"
    connectWS sid $ \conn -> do
      narr <- receiveUntil conn 10000000 isLookNarration
      case narr of
        Nothing -> expectationFailure "no auto-look narration received on login"
        Just _  -> do
          known <- readMVar (acKnownPlayers ctx)
          member (PlayerNameVAL "AgentTest") known `shouldBe` True

  it "login assigns agent to lobby scene" $ \(_port, ctx) -> do
    sid1 <- loginAs ctx (RoleName "wizard") "Alice"
    sid2 <- loginAs ctx (RoleName "wizard") "Bob"
    connectWS sid1 $ \conn1 -> do
      _ <- try @SomeException (connectWS sid2 $ \_ -> threadDelay 3000000)
      threadDelay 3000000
      result <- receiveUntil conn1 10000000 (isDeparture "Bob")
      case result of
        Nothing -> expectationFailure "departure not received — agents not in same scene"
        Just _  -> pure ()

  it "heartbeat delivery within timeout" $ \(_port, ctx) -> do
    sid <- loginAs ctx (RoleName "wizard") "HeartbeatTest"
    connectWS sid $ \conn -> do
      hb <- receiveUntil conn 10000000 isHeartbeat
      case hb of
        Nothing  -> expectationFailure "no heartbeat received within 10s"
        Just msg -> msg `shouldSatisfy` isHeartbeat

  it "multi-player: two players login, both in lobby" $ \(_port, ctx) -> do
    sid1 <- loginAs ctx (RoleName "wizard") "Player1"
    sid2 <- loginAs ctx (RoleName "wizard") "Player2"
    connectWS sid1 $ \conn1 ->
      connectWS sid2 $ \conn2 -> do
        n1 <- receiveUntil conn1 10000000 isLookNarration
        n2 <- receiveUntil conn2 10000000 isLookNarration
        case (n1, n2) of
          (Just _, Just _) -> do
            known <- readMVar (acKnownPlayers ctx)
            member (PlayerNameVAL "Player1") known `shouldBe` True
            member (PlayerNameVAL "Player2") known `shouldBe` True
          _ -> expectationFailure "both players should receive auto-look narration"

  it "multi-player: both clients receive heartbeats" $ \(_port, ctx) -> do
    sid1 <- loginAs ctx (RoleName "wizard") "HB1"
    sid2 <- loginAs ctx (RoleName "wizard") "HB2"
    connectWS sid1 $ \conn1 ->
      connectWS sid2 $ \conn2 -> do
        hb1 <- receiveUntil conn1 10000000 isHeartbeat
        hb2 <- receiveUntil conn2 10000000 isHeartbeat
        case (hb1, hb2) of
          (Just _, Just _) -> pure ()
          _                -> expectationFailure "both players should receive heartbeats"

  it "disconnect: agent removed from lobby scene but stays in agentMap" $ \(_port, ctx) -> do
    sid1 <- loginAs ctx (RoleName "wizard") "Stayer"
    sid2 <- loginAs ctx (RoleName "wizard") "Leaver"
    connectWS sid1 $ \conn1 -> do
      _ <- try @SomeException (connectWS sid2 $ \_ -> threadDelay 3000000)
      threadDelay 3000000
      result <- receiveUntil conn1 10000000 (isDeparture "Leaver")
      case result of
        Nothing -> expectationFailure "departure not received"
        Just _  -> do
          known <- readMVar (acKnownPlayers ctx)
          member (PlayerNameVAL "Leaver") known `shouldBe` True

  it "logout: agent removed from lobby scene, stays in agentMap, maps cleaned" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid1 <- loginAs ctx (RoleName "wizard") "Witness"
    sid2 <- loginAs ctx (RoleName "wizard") "LogoutTarget"
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
            sessions <- readMVar (acSessions ctx)
            member sid2 sessions `shouldBe` False

  it "login auto-look delivers the lobby description" $ \(_port, ctx) -> do
    sid <- loginAs ctx (RoleName "wizard") "LookOnLogin"
    connectWS sid $ \conn -> do
      narr <- receiveUntil conn 10000000 isLookNarration
      case narr of
        Nothing -> expectationFailure "no auto-look narration received on login"
        Just _  -> pure ()

  it "auto-look survives a slow websocket connect" $ \(_port, ctx) -> do
    sid <- loginAs ctx (RoleName "wizard") "SlowSocket"
    threadDelay 3000000
    connectWS sid $ \conn -> do
      narr <- receiveUntil conn 10000000 isLookNarration
      case narr of
        Nothing -> expectationFailure "no auto-look narration after slow connect"
        Just _  -> pure ()

  it "explicit look command repeats the lobby description" $ \(_port, ctx) -> do
    sid <- loginAs ctx (RoleName "wizard") "LookAgain"
    connectWS sid $ \conn -> do
      first <- receiveUntil conn 10000000 isLookNarration
      case first of
        Nothing -> expectationFailure "no auto-look narration received on login"
        Just _  -> do
          sendTextData conn (GameCommand "look")
          second <- receiveUntil conn 10000000 isLookNarration
          case second of
            Nothing -> expectationFailure "no narration received for explicit look"
            Just _  -> pure ()

  it "look presence listing names the other player" $ \(_port, ctx) -> do
    sid1 <- loginAs ctx (RoleName "wizard") "Looker"
    sid2 <- loginAs ctx (RoleName "wizard") "Seen"
    connectWS sid1 $ \conn1 ->
      connectWS sid2 $ \_ -> do
        threadDelay 3000000
        sendTextData conn1 (GameCommand "look")
        result <- receiveUntil conn1 10000000 (hasPresence "Seen")
        case result of
          Nothing -> expectationFailure "presence listing did not name other player"
          Just _  -> pure ()

  it "ping: client sends Ping, receives Pong through Rhine network" $ \(_port, ctx) -> do
    sid <- loginAs ctx (RoleName "wizard") "PingTest"
    connectWS sid $ \conn -> do
      threadDelay 2000000
      sendTextData conn Ping
      pong <- receiveUntil conn 10000000 isPong
      case pong of
        Nothing  -> expectationFailure "no Pong received within 10s"
        Just msg -> msg `shouldBe` Pong

  it "POST /api/game/dsl with unknown token returns 401" $ \(_port, _ctx) -> do
    env <- testClientEnv
    result <- runClientM (dslClient (makeAuthRequest (SessionId "unknown")) (DSLSource worldSource)) env
    isErrorCode 401 result `shouldBe` True

  it "POST /api/game/dsl with bad source returns 400 with an error body" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid <- loginAs ctx (RoleName "wizard") "BadWizard"
    result <- runClientM (dslClient (makeAuthRequest sid) (DSLSource "declareSceneGID")) env
    case result of
      Left (FailureResponse _ (Response (Status 400 _) _ _ body)) ->
        body `shouldSatisfy` (not . null)
      _ -> expectationFailure ("expected 400 with an error body, got: " <> show result)

  it "POST /api/game/dsl by a player without dsl/create returns 403" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid <- loginAs ctx (RoleName "player") "Peasant"
    result <- runClientM (dslClient (makeAuthRequest sid) (DSLSource worldSource)) env
    isErrorCode 403 result `shouldBe` True

  it "GET /api/auth/available answers 204 for a free name" $ \(_port, _ctx) -> do
    manager <- newManager defaultManagerSettings
    req <- parseRequest ("http://127.0.0.1:" <> show testPort <> "/api/auth/available?name=Freshname")
    resp <- httpLbs req manager
    case responseStatus resp of
      Status code _ -> code `shouldBe` 204

  it "GET /api/auth/available answers 409 for a taken name" $ \(_port, ctx) -> do
    seedAccount (acDbPool ctx) (RoleName "wizard") (PlayerNameVAL "Taken")
    manager <- newManager defaultManagerSettings
    req <- parseRequest ("http://127.0.0.1:" <> show testPort <> "/api/auth/available?name=Taken")
    resp <- httpLbs req manager
    case responseStatus resp of
      Status code _ -> code `shouldBe` 409

  it "GET /api/auth/available answers 400 for an invalid name" $ \(_port, _ctx) -> do
    manager <- newManager defaultManagerSettings
    req <- parseRequest ("http://127.0.0.1:" <> show testPort <> "/api/auth/available?name=bad%20name")
    resp <- httpLbs req manager
    case responseStatus resp of
      Status code _ -> code `shouldBe` 400

  it "a new subject with a free name gets an account and keeps it" $ \(_port, ctx) -> do
    manager <- newManager defaultManagerSettings
    first <- finalLocationThroughFake manager testPort (Just "Newbie") "newbie"
    first `shouldSatisfy` isPrefixOf "/#token="
    rows1 :: [Only Int] <- withResource (acDbPool ctx) $ \conn ->
      query conn "SELECT users.agent_gid FROM users JOIN credentials ON users.user_id = credentials.user_id WHERE credentials.subject = ?" (Only ("sub-newbie" :: Text))
    case rows1 of
      [Only _] -> pure ()
      _        -> expectationFailure "expected exactly one account for the new subject"
    second <- finalLocationThroughFake manager testPort Nothing "newbie"
    second `shouldSatisfy` isPrefixOf "/#token="
    rows2 :: [Only Int] <- withResource (acDbPool ctx) $ \conn ->
      query conn "SELECT users.agent_gid FROM users JOIN credentials ON users.user_id = credentials.user_id WHERE credentials.subject = ?" (Only ("sub-newbie" :: Text))
    rows2 `shouldBe` rows1

  it "a new subject with a taken name is sent back to choose again" $ \(_port, ctx) -> do
    seedAccount (acDbPool ctx) (RoleName "wizard") (PlayerNameVAL "Occupied")
    manager <- newManager defaultManagerSettings
    final <- finalLocationThroughFake manager testPort (Just "Occupied") "intruder"
    final `shouldBe` "/#taken=Occupied"

  it "a new subject without a name is sent to create an account" $ \(_port, _ctx) -> do
    manager <- newManager defaultManagerSettings
    final <- finalLocationThroughFake manager testPort Nothing "stranger"
    final `shouldBe` "/#new"

  it "an account created at login can submit DSL" $ \(_port, _ctx) -> do
    env <- testClientEnv
    manager <- newManager defaultManagerSettings
    final <- finalLocationThroughFake manager testPort (Just "Builderborn") "builderborn"
    case stripPrefix "/#token=" final of
      Nothing -> expectationFailure ("expected a token, got " <> show final)
      Just token -> do
        result <- runClientM (dslClient (makeAuthRequest (SessionId token)) (DSLSource worldSource)) env
        result `shouldBe` Right NoContent

  it "POST /api/game/dsl with the world source returns NoContent" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid <- loginAs ctx (RoleName "wizard") "Wizard"
    result <- runClientM (dslClient (makeAuthRequest sid) (DSLSource worldSource)) env
    result `shouldBe` Right NoContent

  it "a delivered submission appears in look after DSLTick" $ \(_port, ctx) -> do
    env <- testClientEnv
    wizardSid <- loginAs ctx (RoleName "wizard") "Builder"
    posted <- runClientM (dslClient (makeAuthRequest wizardSid) (DSLSource studySource)) env
    posted `shouldBe` Right NoContent
    threadDelay 6000000
    viewerSid <- loginAs ctx (RoleName "wizard") "Viewer"
    connectWS viewerSid $ \conn -> do
      narr <- receiveUntil conn 10000000 (seesObjects "You see: a ball, a cup")
      case narr of
        Nothing -> expectationFailure "look did not list the delivered cup"
        Just _  -> pure ()

worldSource :: Text
worldSource = unlines
  [ "let"
  , "  buildLobby :: ActionManagement -> ActionManagement -> SashaLambdaDSL Scene"
  , "  buildLobby sceneLookKey sceneLookAtKey ="
  , "    defaultScene"
  , "      & (title \"the lobby\" `andThen`"
  , "         sceneDescriptionRich (colored White \"A spacious lobby with high ceilings.\") `andThen`"
  , "         flip sceneBehavior sceneLookKey `andThen`"
  , "         flip sceneBehavior sceneLookAtKey)"
  , ""
  , "  buildFloor :: ActionManagement -> SashaLambdaDSL Object"
  , "  buildFloor lookAtKey ="
  , "    defaultObject"
  , "      & (shortName \"floor\" `andThen`"
  , "         description (colored White \"A plain stone floor.\") `andThen`"
  , "         flip objectBehavior lookAtKey)"
  , ""
  , "  buildBall :: ActionManagement -> SashaLambdaDSL Object"
  , "  buildBall lookAtKey ="
  , "    defaultObject"
  , "      & (shortName \"ball\" `andThen`"
  , "         description (colored White \"A small red ball.\") `andThen`"
  , "         flip objectBehavior lookAtKey)"
  , ""
  , "  defaultDenizen :: Text -> Agent"
  , "  defaultDenizen playerName = Agent"
  , "    { _agentShortName         = plain playerName"
  , "    , _agentDescription       = colored White \"A player.\""
  , "    , _agentTitle             = mempty"
  , "    , _agentActionManagement  = ActionManagementFunctions mempty"
  , "    , _agentWitnessManagement = mempty"
  , "    , _agentKind              = Denizen"
  , "    }"
  , "in do"
  , "  lobbyGID      <- declareSceneGID \"lobby\""
  , ""
  , "  sceneLookGID  <- declareImplicitStimulusGID lookF"
  , "  playerLookGID <- declareImplicitStimulusGID lookF"
  , "  sceneLookKey  <- createISAManagement isaLook sceneLookGID"
  , "  playerLookKey <- createISAManagement isaLook playerLookGID"
  , ""
  , "  sceneLookAtGID  <- declareDirectionalStimulusGID lookAtF"
  , "  playerLookAtGID <- declareDirectionalStimulusGID lookAtF"
  , "  floorLookAtGID  <- declareDirectionalStimulusGID lookAtF"
  , "  ballLookAtGID   <- declareDirectionalStimulusGID lookAtF"
  , "  sceneLookAtKey  <- createDSAManagement dsaLook sceneLookAtGID"
  , "  playerLookAtKey <- createDSAManagement dsaLook playerLookAtGID"
  , "  floorLookAtKey  <- createDSAManagement dsaLook floorLookAtGID"
  , "  ballLookAtKey   <- createDSAManagement dsaLook ballLookAtGID"
  , ""
  , "  witnessGID <- declareWitnessGID witnessF"
  , ""
  , "  floorGID <- declareObjectGID"
  , "  ballGID  <- declareObjectGID"
  , ""
  , "  registerObject floorGID (buildFloor floorLookAtKey)"
  , "  registerObject ballGID  (buildBall ballLookAtKey)"
  , ""
  , "  registerObjectToScene lobbyGID floorGID \"FLOOR\""
  , "  registerObjectToScene lobbyGID ballGID  \"BALL\""
  , ""
  , "  registerSpatial (EntityObject ballGID)  (SupportedBy (EntityObject floorGID))"
  , "  registerSpatial (EntityObject floorGID) (Supports (Data.Set.singleton (EntityObject ballGID)))"
  , ""
  , "  registerScene lobbyGID (buildLobby sceneLookKey sceneLookAtKey)"
  , ""
  , "  denizen       <- playerBehavior defaultDenizen playerLookKey"
  , "  denizen'      <- playerBehavior denizen playerLookAtKey"
  , "  w1            <- witnessBehavior denizen' (ImplicitStimulusKey isaLook) witnessGID"
  , "  w2            <- witnessBehavior w1 (DirectionalStimulusKey dsaLook) witnessGID"
  , "  newUser lobbyGID w2"
  , ""
  , "  linkWorldOutcomeEffect (ImplicitStimulusActionKey sceneLookGID) (NarrationEffect LookNarration)"
  , "  linkWorldOutcomeEffect (DirectionalStimulusActionKey ballLookAtGID) (NarrationEffect (LookAtNarration ballGID))"
  , "  linkWorldOutcomeEffect (DirectionalStimulusActionKey floorLookAtGID) (NarrationEffect (LookAtNarration floorGID))"
  , "  finalizeGameState"
  ]

studySource :: Text
studySource = unlines
  [ "do"
  , "  studyGID <- declareSceneGID \"study\""
  , "  tableGID <- declareObjectGID"
  , "  cupGID   <- declareObjectGID"
  , "  registerObject tableGID (defaultObject & shortName \"table\")"
  , "  registerObject cupGID   (defaultObject & shortName \"cup\")"
  , "  registerObjectToScene studyGID tableGID \"TABLE\""
  , "  registerObjectToScene studyGID cupGID   \"CUP\""
  , "  registerSpatial (EntityObject cupGID)   (SupportedBy (EntityObject tableGID))"
  , "  registerSpatial (EntityObject tableGID) (Supports (Data.Set.singleton (EntityObject cupGID)))"
  , "  registerScene studyGID (defaultScene & title \"the study\")"
  , "  finalizeGameState"
  ]
