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

workStealing :: TestTree
workStealing = testCaseSteps "work stealing" $ \step -> do
  (r,dt) <- timed . runT $
            source [1..32::Int] ~> scatter (replicate 4 slowDoubler)
  (r',dt') <- timed. runT $ source [1..32] ~> slowDoubler
  step "Consistent results"
  assertBool "Predicted Parallel Length" (length r == 32)
  assertBool "Predicted Serial Length" (length r' == 32)
  assertBool "Predicted Results" (all (`elem` r) (map (*2) [1..32]))
  assertBool "Results" (all (`elem` r) r')
  step "Parallelism"
  assertBool ("Work Stealing faster than sequential" ++ show (dt',dt))
             (dt * 1.5 < dt')
  where slowDoubler = repeatedly $ do x <- await
                                      liftIO (threadDelay 100000)
                                      yield (x * 2)

main :: IO ()
main = defaultMain $ 
       testGroup "concurrent-machines"
       [ pipeline, workStealing ]
