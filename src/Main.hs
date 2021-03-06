{- Main -- main entry point
Copyright (C) 2013  Benjamin Barenblat <bbaren@mit.edu>

This file is a part of decafc.

decafc is free software: you can redistribute it and/or modify it under the
terms of the MIT (X11) License as described in the LICENSE file.

decafc is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the X11 license for more details. -}
module Main where

import Prelude hiding (readFile)
import qualified Prelude

import DataflowAnalysis
import Data.List (intersperse)
import Debug.Trace (trace)
import Util (compose)
import Codegen
import ControlFlowGraph (BranchingStatement,makeCFG,getFunctionParamMap,lgraphSpanningFunctions)
import CodeGeneration 
import Control.Exception (bracket)
import Control.Monad (forM_, void, liftM)
import Control.Monad.Error (ErrorT(..), runErrorT)
import Control.Monad.IO.Class (liftIO)
import Data.Either (partitionEithers)
import GHC.IO.Handle (hDuplicate)
import System.Environment (getProgName)
import qualified System.Exit
import System.IO (IOMode(..), hClose, hPutStrLn, openFile, stdout, stderr)
import System.IO.Unsafe
import Text.Printf (printf)
import MidIR
import Util (mungeErrorMessage,putIRTree)

import qualified CLI
import Configuration (Configuration(outputFileName,opt), CompilerStage(..), OptimizationSpecification(..))
import Configuration.Types (debug)
import qualified Configuration
import qualified Parser
import qualified Checks
import qualified Scanner
import Transforms (convert)
import PrettyPrint
import Semantics (addSymbolTables)
import Optimization 
import RegisterAlloc
import LowIR
import Codegen
import CFGConcrete
import CFGConstruct
import Parallel(snoper,parallelize, treeParallelize)
------------------------ Impure code: Fun with ErrorT -------------------------

main :: IO ()
main = do
  {- Compiler work can be split into three stages: reading input (impure),
  processing it (pure), and writing output (impure).  Of course, input might be
  malformed or there might be an error in processing.  Thus, it makes most
  sense to think of the compiler as having type ErrorT String IO [IO ()] --
  that is, computation might fail with a String or succeed with a series of IO
  actions. -}
  result <- runErrorT $ do
    -- Part I: Get input
    configuration <- ErrorT CLI.getConfiguration
    input <- readFile $ Configuration.input configuration
    -- Part II: Process it
    hoistEither $ process configuration input
  case result of
    -- Part III: Write output
    Left errorMessage -> fatal errorMessage
    Right actions -> sequence_ actions
  where hoistEither = ErrorT . return

readFile :: FilePath -> ErrorT String IO String
readFile name = liftIO $ Prelude.readFile name

fatal :: String -> IO ()
fatal message = do
  progName <- getProgName
  hPutStrLn stderr $ printf "%s: %s" progName message
  System.Exit.exitFailure


---------------------------- Pure code: Processing ----------------------------

{- The pure guts of the compiler convert input to output.  Exactly what output
they produce, though, depends on the configuration. -}
process :: Configuration -> String -> Either String [IO ()]
process configuration input =
  -- Dispatch on the configuration, modifying error messages appropriately.
  case Configuration.target configuration of
    Scan -> scan configuration input
    Parse -> parse configuration input
    Inter -> checkSemantics configuration input
    Assembly -> assembleTree configuration input
    phase -> Left $ show phase ++ " not implemented\n"

scan :: Configuration -> String -> Either String [IO ()]
scan configuration input =
  let tokensAndErrors =
        Scanner.scan input |>
        map (mungeErrorMessage configuration) |>
        map Scanner.formatTokenOrError
  in
  {- We have to interleave output to standard error (for errors) and standard
  output or a file (for output), so we need to actually build an appropriate
  set of IO actions. -}
  Right $ [ bracket openOutputHandle hClose $ \hOutput ->
             forM_ tokensAndErrors $ \tokOrError ->
               case tokOrError of
                 Left err -> hPutStrLn stderr err
                 Right tok -> hPutStrLn hOutput tok
          ]
  where v |> f = f v            -- like a Unix pipeline, but pure
        openOutputHandle = maybe (hDuplicate stdout) (flip openFile WriteMode) $ Configuration.outputFileName configuration

parse :: Configuration -> String -> Either String [IO ()]
parse configuration input = do
  let (errors, tokens) = partitionEithers $ Scanner.scan input
  -- If errors occurred, bail out.
  mapM_ (mungeErrorMessage configuration . Left) errors
  -- Otherwise, attempt a parse.
  void $ mungeErrorMessage configuration $ Parser.parse tokens
  Right []

prependOutput :: String -> Either String [IO ()] -> Either String [IO ()]
prependOutput msg (Left s) = Left $ msg ++ "\n" ++ s
prependOutput msg actions = liftM (putStrLn msg :) actions

checkSemantics :: Configuration -> String -> Either String [IO ()]
checkSemantics configuration input = do
  let (errors, tokens) = partitionEithers $ Scanner.scan input
  -- If errors occurred, bail out.
  mapM_ (mungeErrorMessage configuration . Left) errors
  parseTree <- mungeErrorMessage configuration $ Parser.parse tokens
  let irTree = convert parseTree
      irTreeWithST = addSymbolTables irTree
      output = Checks.doChecks Checks.checksList $ irTreeWithST in
      case debug configuration of
          False -> output
          True -> prependOutput (pPrint irTree) output


-- List all optimizations you want to run in the specified order here

midIROpts :: [Opt Statement BranchingStatement]
midIROpts = [optGlobalCSE, untilStable optMidIrDeadCodeElim]

lowIROpts :: [Opt ProtoASM ProtoBranch]
lowIROpts = [untilStable optLowIrDeadCodeElim]

assembleTree :: Configuration -> String -> Either String [IO ()]
assembleTree configuration input = do
  let (errors, tokens) = partitionEithers $ Scanner.scan input
  -- If errors occurred, bail out.
  mapM_ (mungeErrorMessage configuration . Left) errors
  parseTree <- mungeErrorMessage configuration $ Parser.parse tokens
  let irTree = convert parseTree 
  let irTreeWithST = addSymbolTables irTree 
  let midir = snoper $MidIR.toMidIR irTreeWithST
--  Right [putStrLn $ show midir] {-
  --let paramidir = treeParallelize midir
  let globals = MidIR.scrapeGlobals midir ---paramidir
  let cfg = makeCFG midir
  let funmap = getFunctionParamMap $lgraphFromAGraph  cfg
  let midcfg = lgraphSpanningFunctions cfg
  ---let	scopedcfg  = scopeMidir midcfg globals funmap
  -- Should make interface to parallelize as just a regular 
  -- optimization if possible
--  let	parallelcfg  = parallelize scopedcfg
  let (runChosenLowIROpts,runChosenMidIROpts) = if opt configuration == Some [] 
                              then
                              (id,id)
                              else
                              (compose lowIROpts, compose midIROpts)
--  let optimizedMidCfg = runChosenMidIROpts scopedcfg
  let lowIRCfg = toLowIRCFG midcfg -- optimizedMidCfg
 -- let optimizedLowCfg = runChosenLowIROpts lowIRCfg
  let lowCfgRegAllocated = trace (pPrint lowIRCfg) $ doRegisterAllocation lowIRCfg --optimizedLowCfg
  let (prolog, asm, epilog) = navigate globals funmap lowCfgRegAllocated
  let ioFuncSeq = case outputFileName configuration of
                    Nothing -> repeat putStrLn
                    Just fp -> (writeFile fp):(repeat $ appendFile fp)
  -- Output goes here..
  let output = Right $ zipWith ($) ioFuncSeq $ intersperse "\n" [prolog, pPrint asm, epilog]
      -- Strings you want to output in debug mode go here.
      debugStrings = [pPrint $ computeInterferenceGraph lowIRCfg ,
                      pPrint $ (fst . defAllocateRegisters) lowIRCfg ,
                      pPrint $ augmentWithDFR lowLVAnalysis lowIRCfg ]
  if debug configuration
	then compose (map prependOutput debugStrings) output
 	else output
     --} 
