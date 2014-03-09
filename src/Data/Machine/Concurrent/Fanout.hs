{-# LANGUAGE FlexibleContexts, GADTs #-}
-- | Provide a notion of fanout wherein a single input is passed to
-- several consumers. The consumers are run concurrently.
module Data.Machine.Concurrent.Fanout (fanout, fanoutSteps) where
import Control.Arrow (second)
import Control.Concurrent.Async.Lifted (Async, async, wait)
import Control.Monad (foldM)
import Control.Monad.Trans.Control (MonadBaseControl, StM)
import Data.Machine (Step(..), MachineT(..), encased, ProcessT, Is(..))
import Data.Machine.Concurrent.AsyncStep (MachineStep)
import Data.Maybe (catMaybes)
import Data.Monoid (Monoid, mempty, mconcat)
import Data.Semigroup (Semigroup(sconcat))
import Data.List.NonEmpty (NonEmpty((:|)))

-- | Feed a value to a 'ProcessT' at an 'Await' 'Step'. If the
-- 'ProcessT' is awaiting a value, then its next step is
-- returned. Otherwise, the original process is returned.
feed :: MonadBaseControl IO m
     => a -> ProcessT m a b
     -> m (Async (StM m ([b], Maybe (MachineStep m (Is a) b))))
feed x m = async $ runMachineT m >>= \v ->
             case v of
               Await f Refl _ -> runMachineT (f x) >>= flushYields
               s -> return ([], Just s)

-- | Like 'Data.List.mapAccumL' but with a monadic accumulating
-- function.
mapAccumLM :: (Functor m, MonadBaseControl IO m)
           => (acc -> x -> m (acc, y)) -> acc -> [Async (StM m x)]
           -> m (acc, [y])
mapAccumLM f z = fmap (second ($ [])) . foldM aux (z,id)
  where aux (acc,ys) x = do (yielded, nxt) <- wait x >>= f acc
                            return $ (yielded, (nxt:) . ys)

-- | Exhaust a sequence of all successive 'Yield' steps taken by a
-- 'MachineT'. Returns the list of yielded values and the next
-- (non-Yield) step of the machine.
flushYields :: Monad m
            => Step k o (MachineT m k o) -> m ([o], Maybe (MachineStep m k o))
flushYields = go id
  where go rs (Yield o s) = runMachineT s >>= go ((o:) . rs)
        go rs Stop = return (rs [], Nothing)
        go rs s = return (rs [], Just s)

-- | Share inputs with each of a list of processes in lockstep. Any
-- values yielded by the processes for a given input are combined into
-- a single yield from the composite process.
fanout :: (Functor m, MonadBaseControl IO m, Semigroup r)
       => [ProcessT m a r] -> ProcessT m a r
fanout xs = encased $ Await (MachineT . aux) Refl (fanout xs)
  where aux y = do (rs,xs') <- mapM (feed y) xs >>= mapAccumLM yields []
                   let nxt = fanout . map encased $ catMaybes xs'
                   case rs of
                     [] -> runMachineT nxt
                     (r:rs') -> return $ Yield (sconcat $ r :| rs') nxt
        yields rs (rs', Nothing) = return (rs' ++ rs, Nothing)
        yields rs (rs', Just s) = return (rs' ++ rs, Just s)

-- | Share inputs with each of a list of processes in lockstep. If
-- none of the processes yields a value, the composite process will
-- itself yield 'mempty'. The idea is to provide a handle on steps
-- only executed for their side effects. For instance, if you want to
-- run a collection of 'ProcessT's that await but don't yield some
-- number of times, you can use 'fanOutSteps . map (fmap (const ()))'
-- followed by a 'taking' process.
fanoutSteps :: (Functor m, MonadBaseControl IO m, Monoid r)
            => [ProcessT m a r] -> ProcessT m a r
fanoutSteps xs = encased $ Await (MachineT . aux) Refl (fanoutSteps xs)
  where aux y = do (rs,xs') <- mapM (feed y) xs >>= mapAccumLM yields []
                   let nxt = fanoutSteps . map encased $ catMaybes xs'
                   if null rs
                   then return $ Yield mempty nxt
                   else return $ Yield (mconcat rs) nxt
        yields rs (rs', Nothing) = return (rs' ++ rs,Nothing)
        yields rs (rs', Just s) = return (rs'++rs, Just s)
