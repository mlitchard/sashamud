{-# LANGUAGE ExplicitNamespaces #-}
{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE FlexibleInstances  #-}

module Server.Validator
  ( Validate (validate)
  , ValidatedBody
  , PlayerNameUNV (PlayerNameUNV)
  , PlayerNameVAL (PlayerNameVAL)
  , unPlayerNameVAL
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, ToJSON, eitherDecode)
import           Data.Aeson.TypeScript (derivingTypeScriptDefinition)
import           Data.ByteString.Lazy (fromStrict)
import           Data.Char (isAlphaNum)
import           Data.String (fromString)
import           Data.Text (strip)
import qualified Data.Text
import           Data.Text.Encoding (encodeUtf8)
import           Lens.Micro.Platform (makeLenses)
#ifdef TESTING
import           Test.QuickCheck (Arbitrary)
import           Test.QuickCheck.Instances.Text ()
#endif
import           Network.Wai (lazyRequestBody)
import           Servant
  ( HasServer (ServerT, hoistServerWithContext, route)
  , Proxy (Proxy)
  , ServerError (errBody)
  , err400
  , type (:>)
  )
import           Servant.Server.Internal.Delayed (addHeaderCheck)
import           Servant.Server.Internal.DelayedIO
  ( DelayedIO
  , delayedFailFatal
  , withRequest
  )

class Validate unv val where
  validate :: unv -> Either Text val

data ValidatedBody (contentTypes :: [Type]) unv val

instance forall list unv val api ctx.
  ( FromJSON unv
  , Validate unv val
  , HasServer api ctx
  ) =>
  HasServer (ValidatedBody list unv val :> api) ctx
  where
  type ServerT (ValidatedBody list unv val :> api) m = val -> ServerT api m
  hoistServerWithContext _ ctx nt server =
    hoistServerWithContext (Proxy @api) ctx nt . server
  route _ ctx subserver =
    route (Proxy @api) ctx $
      addHeaderCheck subserver decodeAndValidate
    where
      decodeAndValidate :: DelayedIO val
      decodeAndValidate = withRequest $ \req -> do
        body <- liftIO (lazyRequestBody req)
        case eitherDecode body :: Either String unv of
          Left err -> delayedFailFatal err400
            { errBody = fromString ("Invalid request: " <> err) }
          Right unv -> case validate unv of
            Left valErr -> delayedFailFatal err400
              { errBody = fromStrict (encodeUtf8 valErr) }
            Right val -> pure val

newtype PlayerNameUNV = PlayerNameUNV { unPlayerNameUNV :: Text }
  deriving stock (Generic, Show)
  deriving newtype (Eq, FromJSON, Ord, ToJSON)
  deriving anyclass (NFData)

derivingTypeScriptDefinition ''PlayerNameUNV

newtype PlayerNameVAL = PlayerNameVAL { _unPlayerNameVAL :: Text }
  deriving stock (Generic, Show)
  deriving newtype (Eq, Ord, ToJSON)
  deriving anyclass (NFData)

makeLenses ''PlayerNameVAL

derivingTypeScriptDefinition ''PlayerNameVAL

instance Validate PlayerNameUNV PlayerNameVAL where
  validate (PlayerNameUNV raw) =
    let trimmed = strip raw
    in case () of
      _ | Data.Text.null trimmed ->
            Left "Player name cannot be empty"
        | Data.Text.length trimmed > 20 ->
            Left "Player name must be 20 characters or fewer"
        | not (Data.Text.all isAlphaNum trimmed) ->
            Left "Player name may only contain letters and numbers"
        | otherwise ->
            Right (PlayerNameVAL trimmed)

#ifdef TESTING
deriving newtype instance Arbitrary PlayerNameUNV
#endif
