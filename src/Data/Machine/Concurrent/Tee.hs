{-# LANGUAGE FlexibleContexts, GADTs #-}
module Data.Machine.Concurrent.Tee where
import Control.Concurrent.Async.Lifted (wait)
import Control.Monad.Trans.Control (MonadBaseControl)
import Data.Machine
import Data.Machine.Concurrent.AsyncStep

-- | Compose a pair of pipes onto the front of a Tee.
tee :: MonadBaseControl IO m
    => ProcessT m a a' -> ProcessT m b b' -> TeeT m a' b' c -> TeeT m a b c
tee ma mb m = MachineT $ do srcL <- asyncRun ma
                            srcR <- asyncRun mb
                            go m (Just srcL) (Just srcR)
  where go :: MonadBaseControl IO m
           => TeeT m a' b' c
           -> Maybe (AsyncStep m (Is a) a')
           -> Maybe (AsyncStep m (Is b) b')
           -> m (MachineStep m (T a b) c)
        go snk srcL srcR = runMachineT snk >>= \v -> case v of
          Stop -> return Stop
          Yield o k -> return . Yield o . MachineT $ go k srcL srcR
          Await f L ff -> maybe (return Stop) wait srcL >>= \u -> case u of
            Stop            -> go ff Nothing srcR
            Yield a k       -> asyncRun k >>= flip (go (f a)) srcR . Just
            Await g Refl fg -> 
              asyncAwait g L fg $ MachineT . flip (go (encased v)) srcR . Just
          Await f R ff -> maybe (return Stop) wait srcR >>= \u -> case u of
            Stop            -> go ff srcL Nothing
            Yield b k       -> asyncRun k >>= go (f b) srcL . Just
            Await g Refl fg -> 
              asyncAwait g R fg $ MachineT . go (encased v) srcL . Just
