-- | A demonstration of concurrent vs serialized fanout. A single
-- input is fed to two workers who both perform a CPU intensive
-- task. The concurrent version is approximately twice as fast when
-- two CPU cores are available.
import Control.Monad (when)
import Data.List (sort)
import Data.Machine.Concurrent
import qualified Data.Machine.Fanout as M
import Data.Time.Clock
import Text.Printf

-- A slow Fibonacci sequence can occupy the CPU
fib :: Int -> Int
fib 0 = 0
fib 1 = 1
fib n = fib (n-1) + fib (n-2)

-- Build a worker process with the given name.
worker :: String -> ProcessT IO Int [String]
worker name = repeatedly $ do
                seed <- await
                let x = fib seed
                x `seq` yield $ [name++": "++show seed++" => "++show x]

main :: IO ()
main = do t1 <- getCurrentTime
          [responses] <- runT $ supply [42] (fanout workers) ~> taking 1
          t2 <- getCurrentTime
          [responses'] <- runT $ supply [42] (M.fanout workers) ~> taking 1
          t3 <- getCurrentTime
          when (map sort responses /= map sort responses') $
            putStrLn "Concurrent and serial workers gave different results!"
          let dt = realToFrac (diffUTCTime t2 t1) :: Double
              dt' = realToFrac (diffUTCTime t3 t2) :: Double
          putStrLn $ "Concurrent vs. serial ("++show responses++"): "
          putStrLn $ "  " ++ printf "%0.1fs vs %0.1fs" dt dt'
  where workers = [ worker "alpha"
                  , worker "beta" ]
