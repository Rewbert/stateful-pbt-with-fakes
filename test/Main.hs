module Main (main) where

import Test.Tasty
import Test.Tasty.QuickCheck

import Example.Counter
import Example.Queue.Test
import Example.DieHard
import Example.TicketDispenser
import Example.Registry.Test
import Example.FileSystem.Test

------------------------------------------------------------------------

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Tests"
  [ testProperty "Counter" prop_counter
  , testProperty "ParallelCounter" (expectFailure prop_parallelCounter)
  , testProperty "Queue" prop_queue
  , testProperty "DieHard" (expectFailure prop_dieHard)
  , testProperty "RegistrySeq" prop_registrySeq
  , testProperty "RegistryPar" prop_registryPar
  , testProperty "TicketDispenserSeq" prop_ticketDispenserSeq
  , testProperty "TicketDispenserPar" (expectFailure prop_ticketDispenserPar)
  , testProperty "FileSystem" prop_fileSystem
  ]
