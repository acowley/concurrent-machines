{-# LANGUAGE RankNTypes #-}
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import Control.Applicative ((<|>))
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


-- Based on GitHub Issue 7
-- https://github.com/acowley/concurrent-machines/issues/7
alternativeWorks :: TestTree
alternativeWorks = testCase "alternative" $ do
  xs <- runT (replicated 5 "Step" ~> construct aux)
  assertEqual "Results" (replicate 5 "Step" ++ ["Done"]) xs
  where aux = do x <- await <|> yield "Done" *> stop
                 yield x
                 aux

alternativeWorksDelay :: TestTree
alternativeWorksDelay = testCase "alternative with delay" $ do
  xs <- runT (construct (gen 5) ~> construct aux)
  assertEqual "Results" (replicate 5 "Step" ++ ["Done"]) xs
  where aux = do x <- await <|> yield "Done" *> stop
                 yield x
                 aux
        gen :: MonadIO m => Int -> PlanT k String m a
        gen 0 = stop
        gen n = yield "Step" >> liftIO (threadDelay 100000) >> gen (n-1)

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
       [ pipeline, workStealing, alternativeWorks, alternativeWorksDelay ]
