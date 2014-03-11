import Data.Machine.Concurrent
import Data.Time.Clock

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
          responses <- runT $ supply [42] (fanout workers) ~> taking 1
          t2 <- getCurrentTime
          putStrLn $ "Got "++show responses++" in "++
                     show (realToFrac $ diffUTCTime t2 t1 :: Double)++"s"
  where workers = [ worker "alpha"
                  , worker "beta" ]
