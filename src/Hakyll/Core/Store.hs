-- | A store for stroing and retreiving items
--
{-# LANGUAGE ExistentialQuantification, ScopedTypeVariables #-}
module Hakyll.Core.Store
    ( Store
    , StoreGet (..)
    , makeStore
    , storeSet
    , storeGet
    ) where

import Control.Concurrent.MVar (MVar, newMVar, readMVar, modifyMVar_)
import System.FilePath ((</>))
import System.Directory (doesFileExist)
import Data.Maybe (fromMaybe)
import Data.Map (Map)
import qualified Data.Map as M

import Data.Binary (Binary, encodeFile, decodeFile)
import Data.Typeable (Typeable, TypeRep, cast, typeOf)

import Hakyll.Core.Identifier
import Hakyll.Core.Util.File

-- | Items we can store
--
data Storable = forall a. (Binary a, Typeable a) => Storable a

-- | Result when an item from the store
--
data StoreGet a = Found a
                | NotFound
                | WrongType TypeRep TypeRep
                deriving (Show, Eq)

-- | Data structure used for the store
--
data Store = Store
    { -- | All items are stored on the filesystem
      storeDirectory :: FilePath
    , -- | And some items are also kept in-memory
      storeMap :: MVar (Map FilePath Storable)
    }

-- | Initialize the store
--
makeStore :: FilePath -> IO Store
makeStore directory = do
    mvar <- newMVar M.empty
    return Store
        { storeDirectory = directory
        , storeMap       = mvar
        }

-- | Auxiliary: add an item to the map
--
addToMap :: (Binary a, Typeable a) => Store -> FilePath -> a -> IO ()
addToMap store path value =
    modifyMVar_ (storeMap store) $ return . M.insert path (Storable value)

-- | Create a path
--
makePath :: Store -> String -> Identifier a -> FilePath
makePath store name identifier = storeDirectory store </> name
    </> group </> toFilePath identifier </> "hakyllstore"
  where
    group = fromMaybe "" $ identifierGroup identifier

-- | Store an item
--
storeSet :: (Binary a, Typeable a)
         => Store -> String -> Identifier a -> a -> IO ()
storeSet store name identifier value = do
    makeDirectories path
    encodeFile path value
    addToMap store path value
  where
    path = makePath store name identifier

-- | Load an item
--
storeGet :: forall a. (Binary a, Typeable a)
         => Store -> String -> Identifier a -> IO (StoreGet a)
storeGet store name identifier = do
    -- First check the in-memory map
    map' <- readMVar $ storeMap store
    case M.lookup path map' of
        -- Found in the in-memory map
        Just (Storable s) -> return $ case cast s of
            Nothing -> WrongType (typeOf s) $ typeOf (undefined :: a)
            Just s' -> Found s'
        -- Not found in the map, try the filesystem
        Nothing -> do
            exists <- doesFileExist path
            if not exists
                -- Not found in the filesystem either
                then return NotFound
                -- Found in the filesystem
                else do v <- decodeFile path
                        addToMap store path v
                        return $ Found v
  where
    path = makePath store name identifier
