module SashaPrelude
  ( -- * GHC.Base
    ($)
  , (.)
  , (<>)
  , pure
  , (>>=)
  , (>>)
  , fmap
  , (<$>)
  , (<*>)
  , (*>)
  , (<*)
  , (<$)
  , (<|>)
  , many
  , empty
  , Alternative
  , Applicative
  , Monad
  , MonadPlus
  , Functor
  , Monoid(mempty, mconcat)
  , Semigroup
  , IO
  , Maybe(Just, Nothing)
  , Either(Left, Right)
  , Bool(True, False)
  , (&&)
  , (||)
  , Int
  , Integer
  , String
  , not
  , otherwise
  , id
  , const
  , flip
  , error
  , undefined
  , seq
  , map
    -- * GHC.Show
  , Show(show)
    -- * GHC.Read
  , Read
    -- * GHC.Num
  , (+)
  , (-)
  , (*)
  , fromInteger
  , Num
    -- * GHC.Enum
  , Bounded(minBound, maxBound)
  , Enum(fromEnum)
    -- * GHC.Real
  , fromIntegral
  , toInteger
    -- * Data.Eq
  , Eq((==), (/=))
    -- * Data.Ord
  , Ord(compare, (<=), (>=), (<), (>))
  , Down(Down)
    -- * Data.Tuple
  , fst
  , snd
    -- * Data.Function
  , (&)
  , on
    -- * Data.List
  , filter
  , reverse
    -- * Data.Foldable
  , mapM_
  , forM_
  , for_
  , foldl'
  , foldr
  , null
  , length
  , elem
  , toList
  , concatMap
    -- * Data.Traversable
  , mapM
  , forM
  , traverse
    -- * Data.Text
  , Text
  , pack
  , unpack
    -- * Data.Kind
  , Type
  , Constraint
    -- * Control.Monad
  , when
  , void
  , unless
  , guard
  , (=<<)
  , (>=>)
    -- * Control.Monad.Fail
  , fail
    -- * Control.Monad.IO.Class
  , MonadIO(liftIO)
    -- * Data.Maybe
  , maybe
  , fromMaybe
  , isJust
  , isNothing
    -- * Data.Either
  , either
    -- * GHC.Generics
  , Generic
  , Generically(Generically)
    -- * System.IO
  , Handle
  , hPutStrLn
  , stderr
  ) where
-- remove
import           Control.Monad (guard, unless, void, when, (=<<), (>=>))
import           Control.Monad.Fail (fail)
import           Control.Monad.IO.Class (MonadIO (liftIO))
import           Data.Bool (not, (&&), (||))
import           Data.Either (Either (Left, Right), either)
import           Data.Eq (Eq ((/=), (==)))
import           Data.Foldable
  ( concatMap
  , elem
  , foldl'
  , foldr
  , forM_
  , for_
  , length
  , mapM_
  , null
  , toList
  )
import           Data.Function (on, (&))
import           Data.Functor ((<$>))
import           Data.Kind (Constraint, Type)
import           Data.List (filter, reverse)
import           Data.Maybe
  ( Maybe (Just, Nothing)
  , fromMaybe
  , isJust
  , isNothing
  , maybe
  )
import           Data.Ord (Down (Down), Ord (compare, (<), (<=), (>), (>=)))
import           Data.Text (Text, pack, unpack)
import           Data.Traversable (forM, mapM, traverse)
import           Data.Tuple (fst, snd)
import           GHC.Base
  ( Alternative (empty, many, (<|>))
  , Applicative (pure, (*>), (<*), (<*>))
  , Bool (False, True)
  , Functor (fmap, (<$))
  , IO
  , Int
  , Monad ((>>), (>>=))
  , MonadPlus
  , Monoid (mconcat, mempty)
  , Semigroup ((<>))
  , String
  , const
  , flip
  , id
  , map
  , otherwise
  , seq
  , ($)
  , (.)
  )
import           GHC.Enum (Bounded (maxBound, minBound), Enum (fromEnum))
import           GHC.Err (error, undefined)
import           GHC.Generics (Generic, Generically (Generically))
import           GHC.Num (Integer, Num, fromInteger, (*), (+), (-))
import           GHC.Read (Read)
import           GHC.Real (fromIntegral, toInteger)
import           GHC.Show (Show (show))
import           System.IO (Handle, hPutStrLn, stderr)
