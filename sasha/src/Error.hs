module Error
  ( throwMaybeM
  ) where

import           Control.Monad.Except (MonadError, throwError)
import           SashaPrelude

throwMaybeM :: (MonadError Text m) => Text -> Maybe a -> m a
throwMaybeM msg = \case
  Nothing -> throwError msg
  Just a  -> pure a
