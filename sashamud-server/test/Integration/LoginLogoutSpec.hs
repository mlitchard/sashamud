{-# LANGUAGE DataKinds   #-}
{-# LANGUAGE LambdaCase  #-}
{-# LANGUAGE QuasiQuotes #-}
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
  , any
  , elem
  , fmap
  , forM_
  , fromMaybe
  , not
  , pack
  , pure
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
import qualified Data.ByteString (readFile)
import qualified Data.ByteString.Char8 (pack)
import           Data.ByteString.Lazy (null)
import           Data.List (lookup)
import           Data.Map.Strict (member)
import           Data.Pool (defaultPoolConfig, newPool, withResource)
import           Data.Text (isInfixOf, isPrefixOf, stripPrefix, unlines)
import           Data.Text.Encoding (decodeUtf8', encodeUtf8)
import           Data.Time.Clock (secondsToNominalDiffTime)
import           Database.PostgreSQL.Simple
  ( Only (Only)
  , Query
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
import           Database.PostgreSQL.Simple.SqlQQ (sql)
import           DSL.Builder
  ( WorldBuilderError (UndeclaredSceneLabel)
  , WorldChange (ObjectModified, SceneModified)
  , worldBuilderErrorText
  , worldChangeText
  )
import           Engine.Simulation.SignalNetwork (gameLoop)
import           FakeProvider
  ( fakeApp
  , fakeAuthentikUserId
  , finalLocationThroughFake
  , loginThroughFake
  , newFakeState
  , seedAccount
  )
import           Lens.Micro.Platform (view)
import           Model.Account
  ( AccessToken (AccessToken)
  , ClientId (ClientId)
  , ClientSecret (ClientSecret)
  , OidcBaseUrl (OidcBaseUrl)
  , RedirectUri (RedirectUri)
  , StartMode (StartCreate, StartLogin)
  )
import           Model.Authorization (RoleName (Player, Wizard))
import           Model.Core
  ( ObjectLabel (ObjectLabel)
  , SceneLabel (SceneLabel)
  , actionConsequence
  , defaultGameState
  , presenceListing
  )
import           Model.Jwt
  ( Credentials (Credentials)
  , Jwt (unJwt)
  , hashToken
  , makeJwtForTesting
  )
import           Model.RichText (plain, toPlainText)
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
import           Servant
  ( AuthProtect
  , NoContent (NoContent)
  , Proxy (Proxy)
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
  ( AppCtx (acDbPool, acGameLog, acKnownPlayers, acSessions)
  , GameLog (GameLog, logPath)
  , OidcConfig (OidcConfig)
  , initialCounters
  , newAppCtx
  )
import           Server.Authentication (CanDo)
import           Server.Log (LogEntry (DSLBuildSucceeded))
import           Server.Migration (buildCommand)
import           Server.Server (app, deliverOutbound)
import           Server.Validator (PlayerNameVAL (PlayerNameVAL))
import           Server.World (worldPrograms)
import           System.Directory (getTemporaryDirectory)
import           System.Environment (lookupEnv)
import           System.IO
  ( BufferMode (LineBuffering)
  , hSetBuffering
  , openTempFile
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

-- Servant client adapter for the CanDo combinator
instance (RunClient m, HasClient m (AuthProtect "BEARER" :> api))
  => HasClient m (CanDo a :> api) where
  type Client m (CanDo a :> api) = Client m (AuthProtect "BEARER" :> api)
  clientWithRoute pm _ = clientWithRoute pm (Proxy @(AuthProtect "BEARER" :> api))
  hoistClientMonad pm _ = hoistClientMonad pm (Proxy @(AuthProtect "BEARER" :> api))

logoutClient :: AuthenticatedRequest (AuthProtect "BEARER") -> ClientM NoContent
logoutClient = client (Proxy @LogoutAPI)

type instance AuthClientData (AuthProtect "BEARER") = SessionId

dslClient :: AuthenticatedRequest (AuthProtect "BEARER") -> DSLSource -> ClientM NoContent
dslClient = client (Proxy @DSLAPI)

makeAuthRequest :: SessionId -> AuthenticatedRequest (AuthProtect "BEARER")
makeAuthRequest sid = mkAuthenticatedRequest sid authenticatedRequest

authenticatedRequest :: SessionId -> Request -> Request
authenticatedRequest (SessionId sid) = addHeader "BEARER" sid

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
  tmpDir <- getTemporaryDirectory
  (logFilePath, logFileHandle) <- openTempFile tmpDir "sashamud-integration.log"
  hSetBuffering logFileHandle LineBuffering
  let logCfg = GameLog logFileHandle (Just logFilePath)
  connStr <- fmap (fromMaybe "dbname=sashamud") (lookupEnv "SASHA_DB_CONNSTR")
  migrationsDir <- fmap (fromMaybe "migrations") (lookupEnv "SASHA_MIGRATIONS_DIR")
  pool <- newPool (defaultPoolConfig (connectPostgreSQL (Data.ByteString.Char8.pack connStr)) close 60 10)
  migrated <- withResource pool (\conn -> runMigrations conn defaultOptions (buildCommand migrationsDir))
  migrated `shouldBe` MigrationSuccess
  manager <- newManager defaultManagerSettings
  fakeState <- newFakeState
  worldDir <- lookupEnv "SASHA_WORLD_DIR"
  case worldDir of
    Nothing -> expectationFailure "SASHA_WORLD_DIR unset"
    Just dir -> do
      let oidcConfig = OidcConfig
            (OidcBaseUrl ("http://127.0.0.1:" <> pack (show fakePort)))
            (ClientId "sashamud")
            (ClientSecret "sashamud-dev")
            (RedirectUri ("http://127.0.0.1:" <> pack (show testPort) <> "/api/auth/callback"))
      ctx <- newAppCtx logCfg pool oidcConfig manager initialCounters
      serverThread <- async $ race_
        (race_ (gameLoop ctx defaultGameState) (deliverOutbound ctx))
        (race_ (run testPort (app ctx)) (run fakePort (fakeApp fakeState)))
      threadDelay 500000
      (do
          sid <- loginAs ctx Wizard "Bootstrap"
          env <- testClientEnv
          paths <- worldPrograms dir
          forM_ paths $ \path -> do
            bytes <- Data.ByteString.readFile path
            case decodeUtf8' bytes of
              Left err -> expectationFailure ("lobby file is not UTF-8: " <> path <> " " <> show err)
              Right source -> do
                delivered <- runClientM (dslClient (makeAuthRequest sid) (DSLSource source)) env
                case delivered of
                  Left err        -> expectationFailure ("lobby delivery failed: " <> show err)
                  Right NoContent -> pure ()
          threadDelay 6000000
          loggedOut <- runClientM (logoutClient (makeAuthRequest sid)) env
          case loggedOut of
            Left err        -> expectationFailure ("bootstrap logout failed: " <> show err)
            Right NoContent -> pure ()
          action (testPort, ctx))
        `finally` cancel serverThread

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

insertExpired :: Query
insertExpired =
  [sql|
    INSERT INTO tokens (token, hash, user_id, created, expires_at)
      SELECT ?, ?, credentials.user_id, now(), now() - interval '1 hour' FROM credentials
        WHERE credentials.player_name = ?
  |]

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
    sid <- loginAs ctx Wizard "TestPlayer"
    sid `shouldSatisfy` (/= SessionId "")

  it "DELETE /api/game/logout removes session" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid <- loginAs ctx Wizard "TestPlayer"
    logoutResult <- runClientM (logoutClient (makeAuthRequest sid)) env
    logoutResult `shouldBe` Right NoContent

  it "login after logout produces a different token" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid1 <- loginAs ctx Wizard "Roundtrip"
    _ <- runClientM (logoutClient (makeAuthRequest sid1)) env
    sid2 <- loginAs ctx Wizard "Roundtrip"
    sid1 `shouldSatisfy` (/= sid2)

  it "a second login replaces the first" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid1 <- loginAs ctx Wizard "Twice"
    manager <- newManager defaultManagerSettings
    sid2 <- loginThroughFake manager testPort "Twice"
    first <- runClientM (dslClient (makeAuthRequest sid1) (DSLSource studySource)) env
    isErrorCode 401 first `shouldBe` True
    second <- runClientM (dslClient (makeAuthRequest sid2) (DSLSource studySource)) env
    second `shouldBe` Right NoContent

  it "an expired token is rejected" $ \(_port, ctx) -> do
    env <- testClientEnv
    seedAccount (acDbPool ctx) Wizard (PlayerNameVAL "Expired")
    let access = AccessToken "Expired"
    hash <- hashToken access
    minted <- makeJwtForTesting (secondsToNominalDiffTime (-3600))
                (Credentials (fakeAuthentikUserId "Expired")) hash
    case minted of
      Left err -> expectationFailure ("could not mint an expired token: " <> show err)
      Right jwt -> do
        _ <- withResource (acDbPool ctx) $ \conn ->
          execute conn insertExpired (jwt, hash, "Expired" :: Text)
        case decodeUtf8' (unJwt jwt) of
          Left _ -> expectationFailure "minted token is not UTF-8"
          Right token -> do
            result <- runClientM (dslClient (makeAuthRequest (SessionId token)) (DSLSource studySource)) env
            isErrorCode 401 result `shouldBe` True

  it "logout stops the token working" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid <- loginAs ctx Wizard "LoggedOut"
    _ <- runClientM (logoutClient (makeAuthRequest sid)) env
    result <- runClientM (dslClient (makeAuthRequest sid) (DSLSource studySource)) env
    isErrorCode 401 result `shouldBe` True

  it "invalid token on WebSocket connect is rejected" $ \(_port, _ctx) -> do
    result <- try @SomeException
      (runClientWith "127.0.0.1" testPort "/ws/game"
        defaultConnectionOptions [] (\_ -> pure ()))
    case result of
      Left _  -> pure ()
      Right _ -> expectationFailure "connection without session should be rejected"

  it "login creates agent in agentMap with correct agentShortName" $ \(_port, ctx) -> do
    sid <- loginAs ctx Wizard "AgentTest"
    connectWS sid $ \conn -> do
      narr <- receiveUntil conn 10000000 isLookNarration
      case narr of
        Nothing -> expectationFailure "no auto-look narration received on login"
        Just _  -> do
          known <- readMVar (acKnownPlayers ctx)
          member (PlayerNameVAL "AgentTest") known `shouldBe` True

  it "login assigns agent to lobby scene" $ \(_port, ctx) -> do
    sid1 <- loginAs ctx Wizard "Alice"
    sid2 <- loginAs ctx Wizard "Bob"
    connectWS sid1 $ \conn1 -> do
      _ <- try @SomeException (connectWS sid2 $ \_ -> threadDelay 3000000)
      threadDelay 3000000
      result <- receiveUntil conn1 10000000 (isDeparture "Bob")
      case result of
        Nothing -> expectationFailure "departure not received — agents not in same scene"
        Just _  -> pure ()

  it "heartbeat delivery within timeout" $ \(_port, ctx) -> do
    sid <- loginAs ctx Wizard "HeartbeatTest"
    connectWS sid $ \conn -> do
      hb <- receiveUntil conn 10000000 isHeartbeat
      case hb of
        Nothing  -> expectationFailure "no heartbeat received within 10s"
        Just msg -> msg `shouldSatisfy` isHeartbeat

  it "multi-player: two players login, both in lobby" $ \(_port, ctx) -> do
    sid1 <- loginAs ctx Wizard "Player1"
    sid2 <- loginAs ctx Wizard "Player2"
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
    sid1 <- loginAs ctx Wizard "HB1"
    sid2 <- loginAs ctx Wizard "HB2"
    connectWS sid1 $ \conn1 ->
      connectWS sid2 $ \conn2 -> do
        hb1 <- receiveUntil conn1 10000000 isHeartbeat
        hb2 <- receiveUntil conn2 10000000 isHeartbeat
        case (hb1, hb2) of
          (Just _, Just _) -> pure ()
          _                -> expectationFailure "both players should receive heartbeats"

  it "one identity logs in as two characters at the same time" $ \(_port, ctx) -> do
    manager <- newManager defaultManagerSettings
    firstFinal <- finalLocationThroughFake manager testPort StartCreate "TwinOne" "twin"
    secondFinal <- finalLocationThroughFake manager testPort StartCreate "TwinTwo" "twin"
    case (stripPrefix "/#token=" firstFinal, stripPrefix "/#token=" secondFinal) of
      (Just t1, Just t2) ->
        connectWS (SessionId t1) $ \conn1 ->
          connectWS (SessionId t2) $ \conn2 -> do
            n1 <- receiveUntil conn1 10000000 isLookNarration
            n2 <- receiveUntil conn2 10000000 isLookNarration
            case (n1, n2) of
              (Just _, Just _) -> do
                sessions <- readMVar (acSessions ctx)
                member (SessionId t1) sessions `shouldBe` True
                member (SessionId t2) sessions `shouldBe` True
              _ -> expectationFailure "both characters should receive auto-look narration"
      _ -> expectationFailure ("expected two tokens, got " <> show (firstFinal, secondFinal))

  it "disconnect: agent removed from lobby scene but stays in agentMap" $ \(_port, ctx) -> do
    sid1 <- loginAs ctx Wizard "Stayer"
    sid2 <- loginAs ctx Wizard "Leaver"
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
    sid1 <- loginAs ctx Wizard "Witness"
    sid2 <- loginAs ctx Wizard "LogoutTarget"
    connectWS sid1 $ \conn1 ->
      connectWS sid2 $ \_ -> do
        threadDelay 3000000
        _ <- runClientM (logoutClient (makeAuthRequest sid2)) env
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
    sid <- loginAs ctx Wizard "LookOnLogin"
    connectWS sid $ \conn -> do
      narr <- receiveUntil conn 10000000 isLookNarration
      case narr of
        Nothing -> expectationFailure "no auto-look narration received on login"
        Just _  -> pure ()

  it "auto-look survives a slow websocket connect" $ \(_port, ctx) -> do
    sid <- loginAs ctx Wizard "SlowSocket"
    threadDelay 3000000
    connectWS sid $ \conn -> do
      narr <- receiveUntil conn 10000000 isLookNarration
      case narr of
        Nothing -> expectationFailure "no auto-look narration after slow connect"
        Just _  -> pure ()

  it "explicit look command repeats the lobby description" $ \(_port, ctx) -> do
    sid <- loginAs ctx Wizard "LookAgain"
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
    sid1 <- loginAs ctx Wizard "Looker"
    sid2 <- loginAs ctx Wizard "Seen"
    connectWS sid1 $ \conn1 ->
      connectWS sid2 $ \_ -> do
        threadDelay 3000000
        sendTextData conn1 (GameCommand "look")
        result <- receiveUntil conn1 10000000 (hasPresence "Seen")
        case result of
          Nothing -> expectationFailure "presence listing did not name other player"
          Just _  -> pure ()

  it "ping: client sends Ping, receives Pong through Rhine network" $ \(_port, ctx) -> do
    sid <- loginAs ctx Wizard "PingTest"
    connectWS sid $ \conn -> do
      threadDelay 2000000
      sendTextData conn Ping
      pong <- receiveUntil conn 10000000 isPong
      case pong of
        Nothing  -> expectationFailure "no Pong received within 10s"
        Just msg -> msg `shouldBe` Pong

  it "POST /api/game/dsl with unknown token returns 401" $ \(_port, _ctx) -> do
    env <- testClientEnv
    result <- runClientM (dslClient (makeAuthRequest (SessionId "unknown")) (DSLSource studySource)) env
    isErrorCode 401 result `shouldBe` True

  it "POST /api/game/dsl with bad source returns 400 with an error body" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid <- loginAs ctx Wizard "BadWizard"
    result <- runClientM (dslClient (makeAuthRequest sid) (DSLSource "declareSceneGID")) env
    case result of
      Left (FailureResponse _ (Response (Status 400 _) _ _ body)) ->
        body `shouldSatisfy` (not . null)
      _ -> expectationFailure ("expected 400 with an error body, got: " <> show result)

  it "POST /api/game/dsl by a player without dsl/create returns 403" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid <- loginAs ctx Player "Peasant"
    result <- runClientM (dslClient (makeAuthRequest sid) (DSLSource studySource)) env
    isErrorCode 403 result `shouldBe` True

  it "GET /api/auth/available answers 204 for a free name" $ \(_port, _ctx) -> do
    manager <- newManager defaultManagerSettings
    req <- parseRequest ("http://127.0.0.1:" <> show testPort <> "/api/auth/available?name=Freshname")
    resp <- httpLbs req manager
    case responseStatus resp of
      Status code _ -> code `shouldBe` 204

  it "GET /api/auth/available answers 409 for a taken name" $ \(_port, ctx) -> do
    seedAccount (acDbPool ctx) Wizard (PlayerNameVAL "Taken")
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
    first <- finalLocationThroughFake manager testPort StartCreate "Newbie" "newbie"
    first `shouldSatisfy` isPrefixOf "/#token="
    rows1 :: [Only Int] <- withResource (acDbPool ctx) $ \conn ->
      query conn "SELECT users.user_id FROM users JOIN credentials ON users.user_id = credentials.user_id WHERE credentials.authentik_user_id = ?" (Only (fakeAuthentikUserId "newbie"))
    case rows1 of
      [Only _] -> pure ()
      _        -> expectationFailure "expected exactly one account for the new subject"
    second <- finalLocationThroughFake manager testPort StartLogin "Newbie" "newbie"
    second `shouldSatisfy` isPrefixOf "/#token="
    rows2 :: [Only Int] <- withResource (acDbPool ctx) $ \conn ->
      query conn "SELECT users.user_id FROM users JOIN credentials ON users.user_id = credentials.user_id WHERE credentials.authentik_user_id = ?" (Only (fakeAuthentikUserId "newbie"))
    rows2 `shouldBe` rows1

  it "a new subject with a taken name is sent back to choose again" $ \(_port, ctx) -> do
    seedAccount (acDbPool ctx) Wizard (PlayerNameVAL "Occupied")
    manager <- newManager defaultManagerSettings
    final <- finalLocationThroughFake manager testPort StartCreate "Occupied" "intruder"
    final `shouldBe` "/#taken=Occupied"

  it "a subject logging in with a name it does not own is told the name is unknown" $ \(_port, _ctx) -> do
    manager <- newManager defaultManagerSettings
    final <- finalLocationThroughFake manager testPort StartLogin "Stranger" "stranger"
    final `shouldBe` "/#unknown=Stranger"

  it "an account created at login can submit DSL" $ \(_port, _ctx) -> do
    env <- testClientEnv
    manager <- newManager defaultManagerSettings
    final <- finalLocationThroughFake manager testPort StartCreate "Builderborn" "builderborn"
    case stripPrefix "/#token=" final of
      Nothing -> expectationFailure ("expected a token, got " <> show final)
      Just token -> do
        result <- runClientM (dslClient (makeAuthRequest (SessionId token)) (DSLSource studySource)) env
        result `shouldBe` Right NoContent

  it "POST /api/game/dsl with the world source returns NoContent" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid <- loginAs ctx Wizard "Wizard"
    result <- runClientM (dslClient (makeAuthRequest sid) (DSLSource studySource)) env
    result `shouldBe` Right NoContent

  it "a delivered submission appears in look after DSLTick" $ \(_port, ctx) -> do
    env <- testClientEnv
    wizardSid <- loginAs ctx Wizard "Builder"
    posted <- runClientM (dslClient (makeAuthRequest wizardSid) (DSLSource studySource)) env
    posted `shouldBe` Right NoContent
    threadDelay 6000000
    viewerSid <- loginAs ctx Wizard "Viewer"
    connectWS viewerSid $ \conn -> do
      narr <- receiveUntil conn 10000000 (seesObjects "You see: a ball, a cup")
      case narr of
        Nothing -> expectationFailure "look did not list the delivered cup"
        Just _  -> pure ()

  it "an amended scene keeps its players and shows the new description" $ \(_port, ctx) -> do
    env <- testClientEnv
    standingSid <- loginAs ctx Wizard "Standing"
    connectWS standingSid $ \conn -> do
      joined <- receiveUntil conn 10000000 (\case
        GameNarration _ -> True
        _               -> False)
      case joined of
        Nothing -> expectationFailure "no join narration"
        Just _  -> do
          wizardSid <- loginAs ctx Wizard "Amender"
          posted <- runClientM (dslClient (makeAuthRequest wizardSid) (DSLSource amendSource)) env
          posted `shouldBe` Right NoContent
          threadDelay 6000000
          sendTextData conn (GameCommand "look")
          narr <- receiveUntil conn 10000000 (seesObjects "A spacious lobby with a freshly polished floor.")
          case narr of
            Nothing -> expectationFailure "look did not show the amended lobby"
            Just _  -> pure ()

  it "the submitter receives the list of changes" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid <- loginAs ctx Wizard "Reporter"
    connectWS sid $ \conn -> do
      joined <- receiveUntil conn 10000000 (\case
        GameNarration _ -> True
        _               -> False)
      case joined of
        Nothing -> expectationFailure "no join narration"
        Just _  -> do
          posted <- runClientM (dslClient (makeAuthRequest sid) (DSLSource amendSource)) env
          posted `shouldBe` Right NoContent
          report <- receiveUntil conn 10000000 (\case
            GameNarration narr ->
              view actionConsequence narr
                == fmap (plain . worldChangeText)
                     [SceneModified (SceneLabel "lobby"), ObjectModified (ObjectLabel "ball")]
            _ -> False)
          case report of
            Nothing -> expectationFailure "no change report on the submitter's socket"
            Just _  -> pure ()

  it "the submitter receives the build error" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid <- loginAs ctx Wizard "Reporter"
    connectWS sid $ \conn -> do
      joined <- receiveUntil conn 10000000 (\case
        GameNarration _ -> True
        _               -> False)
      case joined of
        Nothing -> expectationFailure "no join narration"
        Just _  -> do
          posted <- runClientM (dslClient (makeAuthRequest sid) (DSLSource failSource)) env
          posted `shouldBe` Right NoContent
          report <- receiveUntil conn 10000000
            (seesObjects (worldBuilderErrorText (UndeclaredSceneLabel (SceneLabel "nowhere"))))
          case report of
            Nothing -> expectationFailure "no error report on the submitter's socket"
            Just _  -> pure ()

  it "a bystander receives no report" $ \(_port, ctx) -> do
    env <- testClientEnv
    bystanderSid <- loginAs ctx Wizard "Bystander"
    connectWS bystanderSid $ \conn -> do
      joined <- receiveUntil conn 10000000 (\case
        GameNarration _ -> True
        _               -> False)
      case joined of
        Nothing -> expectationFailure "no join narration"
        Just _  -> do
          reporterSid <- loginAs ctx Wizard "Reporter"
          posted <- runClientM (dslClient (makeAuthRequest reporterSid) (DSLSource amendSource)) env
          posted `shouldBe` Right NoContent
          leaked <- receiveUntil conn 8000000 (\case
            GameNarration narr ->
              any ((\line -> line `elem` fmap toPlainText (view actionConsequence narr)) . worldChangeText)
                [SceneModified (SceneLabel "lobby"), ObjectModified (ObjectLabel "ball")]
            _ -> False)
          leaked `shouldBe` Nothing

  it "the game log records the successful build" $ \(_port, ctx) -> do
    env <- testClientEnv
    sid <- loginAs ctx Wizard "Reporter"
    posted <- runClientM (dslClient (makeAuthRequest sid) (DSLSource amendSource)) env
    posted `shouldBe` Right NoContent
    threadDelay 6000000
    case logPath (acGameLog ctx) of
      Nothing -> expectationFailure "test server has no log file"
      Just path -> do
        bytes <- Data.ByteString.readFile path
        case decodeUtf8' bytes of
          Left err -> expectationFailure ("log is not UTF-8: " <> show err)
          Right logText ->
            logText `shouldSatisfy` isInfixOf (pack (show (DSLBuildSucceeded
              [SceneModified (SceneLabel "lobby"), ObjectModified (ObjectLabel "ball")])))

studySource :: Text
studySource = unlines
  [ "do"
  , "  studyGID <- declareSceneGID (SceneLabel \"study\")"
  , "  tableGID <- declareObjectGID (ObjectLabel \"table\")"
  , "  cupGID   <- declareObjectGID (ObjectLabel \"cup\")"
  , "  registerObject tableGID (defaultObject & shortName \"table\")"
  , "  registerObject cupGID   (defaultObject & shortName \"cup\")"
  , "  registerObjectToScene studyGID tableGID \"TABLE\""
  , "  registerObjectToScene studyGID cupGID   \"CUP\""
  , "  registerSpatial (EntityObject cupGID)   (SupportedBy (EntityObject tableGID))"
  , "  registerSpatial (EntityObject tableGID) (Supports (Data.Set.singleton (EntityObject cupGID)))"
  , "  registerScene studyGID (defaultScene & title \"the study\")"
  , "  finalizeGameState"
  ]

amendSource :: Text
amendSource = unlines
  [ "do"
  , "  modifyScene (SceneLabel \"lobby\") (sceneDescriptionRich (colored White \"A spacious lobby with a freshly polished floor.\"))"
  , "  modifyObject (ObjectLabel \"ball\") (description (colored White \"A small blue ball.\"))"
  , "  finalizeGameState"
  ]

failSource :: Text
failSource = unlines
  [ "do"
  , "  modifyScene (SceneLabel \"nowhere\") (title \"nowhere\")"
  , "  finalizeGameState"
  ]
