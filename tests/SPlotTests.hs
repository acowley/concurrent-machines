module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Exception (catch, throwIO)
import Control.Monad (when, forM_)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Trans.Writer
import Control.Monad.Trans.Class (lift)
import Data.Machine.Concurrent
import Data.Time.Clock (UTCTime, addUTCTime, diffUTCTime, getCurrentTime)
import Text.Printf (printf)
import Data.Time.Format (defaultTimeLocale, formatTime, readPTime)
import System.Exit (ExitCode (ExitSuccess), exitSuccess)
import System.IO (writeFile)
import qualified System.Process as Proc
import Text.ParserCombinators.ReadP (readP_to_S)

import qualified Test.Tasty as T
import qualified Test.Tasty.HUnit as TH

writeSPlot :: Bool
writeSPlot = True

showTime :: UTCTime -> String
showTime = formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S%Q"

worker :: (Show a, MonadIO m)
       => (a -> b) -> Int -> Double -> ProcessT (WriterT [String] m) a b
worker f i dt = repeatedly $ do
  x <- await
  t1 <- liftIO getCurrentTime
  lift $ tell [ printf "%s >%d colour%d" (showTime t1) i i
              , printf "%s !%d black %s" (showTime t1) i (show x) ]
  liftIO $ threadDelay (floor (dt * 10000))
  t2 <- liftIO getCurrentTime
  lift $ tell [printf "%s <%d" (showTime t2) i]
  yield (f x)

timed :: MonadIO m => m a -> m (a, Double)
timed m = do
  t1 <- liftIO getCurrentTime
  r <- m
  t2 <- liftIO getCurrentTime
  return (r, realToFrac $ t2 `diffUTCTime` t1)

pipeline :: T.TestTree
pipeline = TH.testCaseSteps "pipeline" $ \step -> do
  let xs = [(0::Int)..]

  ((r,dt), ls) <- runWriterT . timed . runT $
    source xs ~> worker id 1 3 ~> worker id 2 5 ~> worker id 3 10 ~> taking 10

  ((r',dt'), ls') <- runWriterT . timed . runT $
    source xs ~> worker id 1 2 >~> worker id 2 4 >~> worker id 3 8 ~> taking 10

  when writeSPlot $ do
    writeFile "pipeline-seq.splot" (unlines ls)
    writeFile "pipeline-par.splot" (unlines ls')

  step "Consistent results"
  TH.assertEqual "Results" r r'

  step "Parallelism"
  TH.assertBool ("Pipeline faster than sequential" ++ show (dt',dt))
                (dt' * 1.5 < dt)

buffering1 :: T.TestTree
buffering1 = TH.testCaseSteps "buffering1" $ \step -> do
  let xs = [1..32::Int]

  ((r, dt), ls) <- runWriterT . timed . runT $
    source xs ~> worker (*2) 1 2 ~> worker (+1) 2 4

  ((r', dt'), ls') <- runWriterT . timed . runT $
    source xs ~> bufferConnect 5 (worker (*2) 1 2) (worker (+1) 2 4)

  when writeSPlot $ do
    writeFile "buffering1-seq.splot" (unlines ls)
    writeFile "buffering1-par.splot" (unlines ls')

  step "Consistent results"
  TH.assertEqual "Results" r r'

  step "Parallelism"
  TH.assertBool ("Buffered pipeline faster than sequential" ++ show (dt', dt))
                (dt' * 1.4 < dt)

rolling1 :: T.TestTree
rolling1 = TH.testCaseSteps "rolling1" $ \step -> do
  let xs = [1..32::Int]

  ((r, dt), ls) <- runWriterT . timed . runT $
    source xs ~> worker (*2) 1 2 ~> worker (+1) 2 4

  ((r', dt'), ls') <- runWriterT . timed . runT $
    source xs ~> rollingConnect 5 (worker (*2) 1 2) (worker (+1) 2 4)

  when writeSPlot $ do
    writeFile "rolling1-seq.splot" (unlines ls)
    writeFile "rolling1-par.splot" (unlines ls')

  step "Consistent results"
  TH.assertBool "Results" (all (`elem` r) r')

  step "Parallelism"
  TH.assertBool ("Rolling pipeline faster than sequential" ++ show (dt', dt))
                (dt' * 1.5 < dt)

workStealing :: T.TestTree
workStealing = TH.testCaseSteps "work stealing" $ \step -> do
  let xs = [1..32::Int]

  ((r,dt), ls) <- runWriterT . timed . runT $
    source xs ~> (worker (*2) 0 4)

  ((r',dt'), ls') <- runWriterT . timed . runT $
    source xs ~> scatter (map (\i -> worker (*2) i 4) [1..4])

  when writeSPlot $ do
    writeFile "work-stealing-seq.splot" (unlines ls)
    writeFile "work-stealing-par.splot" (unlines ls')

  step "Consistent results"
  TH.assertBool "Predicted Serial Length" (length r == length xs)
  TH.assertBool "Predicted Parallel Length" (length r' == length xs)
  TH.assertBool "Predicted Results" (all (`elem` r') (map (*2) xs))
  TH.assertBool "Results" (all (`elem` r') r)

  step "Parallelism"
  TH.assertBool ("Work Stealing faster than sequential" ++ show (dt,dt'))
                (dt' * 1.5 < dt)

main :: IO ()
main = do
  catch
    (T.defaultMain
      (T.testGroup "concurrent-machines"
        [ pipeline, buffering1, rolling1, workStealing ]))
    (\e -> if e == ExitSuccess
             then return ()
             else throwIO e)
  when writeSPlot $ do
    let splots = [ "pipeline-seq.splot"
                 , "pipeline-par.splot"
                 , "buffering1-seq.splot"
                 , "buffering1-par.splot"
                 , "rolling1-seq.splot"
                 , "rolling1-par.splot"
                 , "work-stealing-seq.splot"
                 , "work-stealing-par.splot"
                 ]
    forM_ splots $ \path -> do
      l:_ <- lines <$> readFile path
      case readP_to_S (readPTime False defaultTimeLocale "%Y-%m-%d %H:%M:%S%Q") l of
        [] ->
          fail "Shit no."
        (fromTime,_):_ -> do
          let toTime = addUTCTime 2.5 fromTime
          let args = [ "-if", path
                     , "-o", path ++ ".png"
                     , "-w", "2048"
                     , "-h", "200"
                     , "-bh", "1"
                     , "-tickInterval", "100"
                     , "-legendWidth", "20"
                     , "-numTracks", "4"
                     , "-fromTime", showTime fromTime
                     , "-toTime", showTime toTime
                     ]
          Proc.readProcess "splot" args "" >>= putStr
          putStrLn $ "OK: " ++ show (fromTime :: UTCTime) ++ " " ++ path
  exitSuccess
