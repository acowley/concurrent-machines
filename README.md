A simple example of a pipelined computation whose throughput is improved by concurrently running distinct processing stages is given in [`examples/Pipeline.hs`](http://github.com/acowley/concurrent-machines/blob/master/examples/Pipeline.hs).

```haskell
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import Control.Concurrent (threadDelay)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Machine.Concurrent
```

Suppose we have a worker that performs a computation on its input before producing output. This operation may take some time due to, say, network IO or just CPU load. Here we simulate an operation that takes some time with `threadDelay`.

```haskell
worker :: String -> Double -> ProcessT IO () ()
worker name dt = repeatedly $ do _ <- await
                                 liftIO $ do
                                   putStrLn $ name ++ " working on its input"
                                   threadDelay dt'
                                 yield ()
  where dt' = floor $ dt * 1000000
```

We will use a little helper to time two variations of our test program.

```haskell
timed :: MonadIO m => m a -> m (a, Double)
timed m = do t1 <- liftIO getCurrentTime
             r <- m
             t2 <- liftIO getCurrentTime
             return (r, realToFrac $ t2 `diffUTCTime` t1)
```

Now we will run a three-stage pipeline where each stage takes one second to process its input before yielding some output. A sequential execution strategy will thus take three seconds to pass an input through this pipeline. At the top-level, we will request three outputs, each of which will take three seconds to produce, resulting in a total execution time of approximately nine seconds.

```haskell
main :: IO ()
main = do (r,dt) <- timed . runT . supply (repeat ()) $
            worker "A" 1 ~> worker "B" 1 ~> worker "C" 1 ~> taking 3
          putStrLn $ "Sequentially produced "++show r
          putStrLn $ "Sequential processing took "++show dt++"s"
```

If we instead run the same arrangement as a pipelined computation, we allow the independent stages to run concurrently, much like the stages in a pipelined CPU.

```haskell
          (r',dt') <- timed . runT . supply (repeat ()) $
            worker "A" 1 >~> worker "B" 1 >~> worker "C" 1 >~> taking 3
          putStrLn $ "Pipeline produced "++show r'
          putStrLn $ "Pipeline processing took "++show dt'++"s"
```

With this arrangement, the first output we request takes three seconds to produce as we must wait for an input to pass through the entire length of the pipeline. However, successive outputs are following that first output through the pipeline so that we will produce more output at one second intervals. Therefore it takes is `3 + 2 = 5` seconds to produce three outputs: three seconds for the first output, and one second for each of the following two.

[![Build Status](https://travis-ci.org/acowley/concurrent-machines.png)](https://travis-ci.org/acowley/concurrent-machines)
