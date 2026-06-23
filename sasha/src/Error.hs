module Error
  ( throwMaybeM
  ) where

import SashaPrelude
import Control.Monad.Except (MonadError, throwError)

throwMaybeM :: (MonadError Text m) => Text -> Maybe a -> m a
throwMaybeM msg = \case
  Nothing -> throwError msg
  Just a  -> pure a
