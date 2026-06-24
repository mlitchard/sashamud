{-# OPTIONS_GHC -Wno-orphans #-}

module Integration.LoginLogoutSpec (spec) where

import           SashaPrelude

import           API.Routes (LoginAPI, LogoutAPI)
import           API.Types
  ( LoginResponse (LoginResponse)
  , SessionId (SessionId)
  )
import           Network.HTTP.Client (defaultManagerSettings, newManager)
import           Network.Wai.Handler.Warp (Port, testWithApplication)
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
import           Server.App (GameLog (GameLog), newAppCtx)
import           Server.Server (app)
import           Server.Validator (PlayerNameUNV (PlayerNameUNV), ValidatedBody)
import           Test.Hspec
  ( Spec
  , around
  , describe
  , it
  , shouldBe
  , shouldSatisfy
  )

instance (RunClient m, HasClient m (ReqBody list unv :> api)) => HasClient m (ValidatedBody list unv val :> api) where
  type Client m (ValidatedBody list unv val :> api) = Client m (ReqBody list unv :> api)
  clientWithRoute pm _ = clientWithRoute pm (Proxy @(ReqBody list unv :> api))
  hoistClientMonad pm _ = hoistClientMonad pm (Proxy @(ReqBody list unv :> api))

loginClient :: PlayerNameUNV -> ClientM LoginResponse
loginClient = client (Proxy @LoginAPI)

logoutClient :: SessionId -> ClientM NoContent
logoutClient = client (Proxy @LogoutAPI)

testClientEnv :: Port -> IO ClientEnv
testClientEnv port = do
  mgr <- newManager defaultManagerSettings
  baseUrl <- parseBaseUrl "http://localhost"
  pure (mkClientEnv mgr baseUrl { baseUrlPort = port })

withTestApp :: (Port -> IO ()) -> IO ()
withTestApp = testWithApplication $ do
  ctx <- newAppCtx (GameLog stderr)
  pure (app ctx)

spec :: Spec
spec = do
  describe "Login/Logout roundtrip" . around withTestApp $ do

    it "login returns a sessionId" $ \port -> do
      env <- testClientEnv port
      result <- runClientM (loginClient (PlayerNameUNV "TestPlayer")) env
      case result of
        Left err -> error ("login failed: " <> show err)
        Right (LoginResponse sid) ->
          sid `shouldSatisfy` (/= SessionId "")

    it "logout returns 204 (NoContent)" $ \port -> do
      env <- testClientEnv port
      loginResult <- runClientM (loginClient (PlayerNameUNV "TestPlayer")) env
      case loginResult of
        Left err -> error ("login failed: " <> show err)
        Right (LoginResponse sid) -> do
          logoutResult <- runClientM (logoutClient sid) env
          logoutResult `shouldBe` Right NoContent

    it "login after logout produces a different sessionId" $ \port -> do
      env <- testClientEnv port
      r1 <- runClientM (loginClient (PlayerNameUNV "Roundtrip")) env
      case r1 of
        Left err -> error ("first login failed: " <> show err)
        Right (LoginResponse sid1) -> do
          _ <- runClientM (logoutClient sid1) env
          r2 <- runClientM (loginClient (PlayerNameUNV "Roundtrip")) env
          case r2 of
            Left err -> error ("second login failed: " <> show err)
            Right (LoginResponse sid2) ->
              sid1 `shouldSatisfy` (/= sid2)
