import Data.Time.Clock (getCurrentTime, diffUTCTime)
import Control.Concurrent (threadDelay)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Machine.Concurrent

worker :: String -> Double -> ProcessT IO () ()
worker name dt = repeatedly $ do _ <- await
                                 liftIO $ do
                                   putStrLn $ name ++ " working on its input"
                                   threadDelay dt'
                                 yield ()
  where dt' = floor $ dt * 1000000

timed :: MonadIO m => m a -> m (a, Double)
timed m = do t1 <- liftIO getCurrentTime
             r <- m
             t2 <- liftIO getCurrentTime
             return (r, realToFrac $ t2 `diffUTCTime` t1)

main :: IO ()
main = do (r,dt) <- timed . runT . supply (repeat ()) $
            worker "A" 1 ~> worker "B" 1 ~> worker "C" 1 ~> taking 3
          putStrLn $ "Sequentially produced "++show r
          putStrLn $ "Sequential processing took "++show dt++"s"
          (r',dt') <- timed . runT . supply (repeat ()) $
            worker "A" 1 >~> worker "B" 1 >~> worker "C" 1 >~> taking 3
          putStrLn $ "Pipeline produced "++show r'
          putStrLn $ "Pipeline processing took "++show dt'++"s"
