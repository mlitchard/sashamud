module Error
  ( throwMaybeM
  ) where

import           Control.Monad.Except (MonadError, throwError)
import           Model.Core (GameError)
import           SashaPrelude

throwMaybeM :: (MonadError GameError m) => GameError -> Maybe a -> m a
throwMaybeM msg = \case
  Nothing -> throwError msg
  Just a  -> pure a
