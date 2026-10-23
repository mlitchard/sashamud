module Main (main) where

import           SashaPrelude

import           FakeProvider (fakeApp, newFakeState)
import           Network.Wai.Handler.Warp (run)
import           System.Environment (lookupEnv)
import           Text.Read (readMaybe)

main :: IO ()
main = do
  port <- maybe 9000 readPort <$> lookupEnv "SASHA_FAKE_OIDC_PORT"
  st <- newFakeState
  hPutStrLn stderr ("sasha-fake-oidc listening on port " <> show port)
  run port (fakeApp st)

readPort :: String -> Int
readPort s = fromMaybe 9000 (readMaybe s)
