{-# LANGUAGE GADTs, FlexibleContexts, RankNTypes, TupleSections #-}
-- | The primary use of concurrent machines is to establish a
-- pipelined architecture that can boost overall throughput by running
-- each stage of the pipeline at the same time. The processing, or
-- production, rate of each stage may not be identical, so facilities
-- are provided to loosen the temporal coupling between pipeline
-- stages using buffers.
--
-- This architecture also lends itself to operations where multiple
-- workers are available for procesisng inputs. If each worker is to
-- process the same set of inputs, consider 'fanout' and
-- 'fanoutSteps'. If each worker is to process a disjoint set of
-- inputs, consider 'scatter'.
module Data.Machine.Concurrent (module Data.Machine,
                                -- * Concurrent connection
                                (>~>), (<~<),
                                -- * Buffered machines
                                buffer, rolling,
                                bufferConnect, rollingConnect,
                                -- * Concurrent processing of shared inputs
                                fanout, fanoutSteps,
                                -- * Concurrent multiple-input machines
                                wye, tee, scatter, splitSum, mergeSum, 
                                splitProd) where
import Control.Concurrent.Async.Lifted
import Control.Monad.Trans.Control
import Data.Machine hiding (tee, wye)
import Data.Machine.Concurrent.AsyncStep
import Data.Machine.Concurrent.Buffer
import Data.Machine.Concurrent.Fanout
import Data.Machine.Concurrent.Scatter
import Data.Machine.Concurrent.Wye
import Data.Machine.Concurrent.Tee

-- | Build a new 'Machine' by adding a 'Process' to the output of an
-- old 'Machine'. The upstream machine is run concurrently with
-- downstream with the aim that upstream will have a yielded value
-- ready as soon as downstream awaits. This effectively creates a
-- buffer between upstream and downstream, or source and sink, that
-- can contain up to one value.
--
-- @
-- ('<~<') :: 'Process' b c -> 'Process' a b -> 'Process' a c
-- ('<~<') :: 'Process' c d -> 'Data.Machine.Tee.Tee' a b c -> 'Data.Machine.Tee.Tee' a b d
-- ('<~<') :: 'Process' b c -> 'Machine' k b -> 'Machine' k c
-- @
(<~<) :: MonadBaseControl IO m
     => ProcessT m b c -> MachineT m k b -> MachineT m k c
mp <~< ma = MachineT $ asyncRun ma >>= go mp . Just
  where go :: MonadBaseControl IO m
           => ProcessT m b c
           -> Maybe (Async (StM m (MachineStep m k b)))
           -> m (MachineStep m k c)
        go snk src = runMachineT snk >>= \v -> case v of
          Stop            -> return Stop
          Yield o k       -> return . Yield o . MachineT $ go k src
          Await f Refl ff -> maybe (return Stop) wait src >>= \u -> case u of
            Stop           -> go ff Nothing
            Yield o k      -> async (runMachineT k) >>= go (f o) . Just
            Await g kg fg  -> 
              asyncAwait g kg fg $ MachineT . go (encased v) . Just

-- | Flipped ('<~<').
(>~>) :: MonadBaseControl IO m
     => MachineT m k b -> ProcessT m b c -> MachineT m k c
ma >~> mp = mp <~< ma

infixl 7 >~>
