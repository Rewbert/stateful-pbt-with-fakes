{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE TypeFamilies #-}

module Example.Registry.Test where

import Control.Arrow
import Control.Concurrent
import Control.Exception (ErrorCall(..), try)
import Control.Monad
import Test.QuickCheck
import Test.QuickCheck.Monadic

import Example.Registry.Real
import Parallel
import Stateful

------------------------------------------------------------------------

data RegState = RegState {
    tids :: [Var (ThreadId)],
    regs :: [(String, Var (ThreadId))]
  }
  deriving Show

instance StateModel RegState where

  initialState :: RegState
  initialState = RegState [] []

  type Reference RegState = ThreadId

  data Command RegState tid
    = Spawn
    | WhereIs String
    | Register String tid
    | Unregister String
    deriving (Show, Functor)

  data Response RegState tid
    = Spawn' tid
    | WhereIs' (NonFoldable (Maybe tid))
    | Register' (Either ErrorCall ())
    | Unregister' ()
    deriving (Eq, Show, Functor, Foldable)

  generateCommand :: RegState -> Gen (Command RegState (Var ThreadId))
  generateCommand s = oneof $
    [ return Spawn ] ++
    [ Register <$> arbitraryName <*> elements (tids s) | not (null (tids s)) ] ++
    [ Unregister <$> arbitraryName
    , WhereIs <$> arbitraryName
    ]

  type Failure RegState = ()

  runFake :: Command RegState (Var ThreadId)-> RegState
          -> Either () (RegState, Response RegState (Var ThreadId))
  runFake Spawn               s = let tid = Var (length (tids s)) in
                                  return (s { tids = tids s ++ [tid] }, Spawn' tid)
  runFake (WhereIs name)      s = return (s, WhereIs' (NonFoldable (lookup name (regs s))))
  runFake (Register name tid) s
    | tid `elem` tids s
    , name `notElem` map fst (regs s)
    , tid `notElem` map snd (regs s)
    = return (s { regs = (name, tid) : regs s }, Register' (Right ()))

    | tid `elem` tids s
    , name `elem` map fst (regs s)
    , tid `elem` map snd (regs s)
    = return (s, Register' (Left (ErrorCall "bad argument")))

    | otherwise = Left ()
  runFake (Unregister name)   s
    | name `elem` map fst (regs s) =
        return (s { regs = remove name (regs s) }, Unregister' ())
    | otherwise =
        Left ()
    where
      remove x = filter ((/= x) . fst)

  runReal :: Command RegState ThreadId -> IO (Response RegState ThreadId)
  runReal Spawn               = Spawn'    <$> forkIO (threadDelay 100000000)
  runReal (WhereIs name)      = WhereIs' . NonFoldable <$> whereis name
  runReal (Register name tid) = Register' <$> fmap (left abstractError) (try (register name tid))
    where
      -- Throws away the location information from the error, so that it matches
      -- up with the fake.
      abstractError (ErrorCallWithLocation msg _loc) = ErrorCall msg
  runReal (Unregister name)   = Unregister' <$> unregister name

  monitoring :: (RegState, RegState) -> Command RegState ThreadId -> Response RegState ThreadId
             -> Property -> Property
  monitoring (_s, s') _cmd _resp =
    counterexample $ "\n    State: " ++ show s' ++ "\n"

  runCommandMonad _ = id

arbitraryName :: Gen String
arbitraryName = elements allNames

allNames :: [String]
allNames = ["a", "b", "c", "d", "e"]

prop_registry :: Commands RegState -> Property
prop_registry cmds = monadicIO $ do
  runCommands cmds
  void (run cleanUp)
  assert True

cleanUp :: IO [Either ErrorCall ()]
cleanUp = sequence
  [ try (unregister name) :: IO (Either ErrorCall ())
  | name <- allNames
  ]

-- XXX: Not used.
kill :: ThreadId -> IO ()
kill tid = do
  killThread tid
  yield

prop_parallelRegistry :: ParallelCommands RegState -> Property
prop_parallelRegistry cmds = monadicIO $ do
  replicateM_ 10 $ do
    runParallelCommands cmds
    void (run cleanUp)
  assert True
