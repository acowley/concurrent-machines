import Data.Time.Clock (getCurrentTime, diffUTCTime)
import Control.Concurrent (threadDelay)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Machine.Concurrent
import Test.Tasty
import Test.Tasty.HUnit

worker :: String -> Double -> ProcessT IO () ()
worker _name dt = repeatedly $ do _ <- await
                                  liftIO $ threadDelay dt'
                                  yield ()
  where dt' = floor $ dt * 10000

timed :: MonadIO m => m a -> m (a, Double)
timed m = do t1 <- liftIO getCurrentTime
             r <- m
             t2 <- liftIO getCurrentTime
             return (r, realToFrac $ t2 `diffUTCTime` t1)

pipeline :: TestTree
pipeline = testCaseSteps "pipeline" $ \step -> do
  (r,dt) <- timed . runT . supply (repeat ()) $
            worker "A" 1 ~> worker "B" 1 ~> worker "C" 1 ~> taking 10
  (r',dt') <- timed . runT . supply (repeat ()) $
              worker "A" 1 >~> worker "B" 1 >~> worker "C" 1 >~> taking 10
  step "Consistent results"
  assertEqual "Results" r r'
  step "Parallelism"
  assertBool ("Pipeline faster than sequential" ++ show (dt',dt)) (dt' * 1.5 < dt)

main :: IO ()
main = defaultMain $ 
       testGroup "concurrent-machines"
       [ pipeline ]
