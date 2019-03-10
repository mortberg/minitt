module Main where

import Data.Text.Prettyprint.Doc hiding ((<+>))
import Data.Text.Prettyprint.Doc.Render.Text
import Data.Text.Prettyprint.Doc.Render.Util.Panic

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as IO
import System.IO

import Control.Monad.Reader
import qualified Control.Exception as E
import Data.List
import Data.Time
import System.Directory
import System.FilePath
import System.Environment
import System.Console.GetOpt
import System.Console.Haskeline
import System.Console.Haskeline.History
import Text.Printf

import Exp.Lex
import Exp.Par
import Exp.Print
import Exp.Abs hiding (NoArg)
import Exp.Layout
import Exp.ErrM

import CTT
import Resolver
import qualified TypeChecker as TC
import qualified Eval as E

type Interpreter a = InputT IO a

-- Flag handling
data Flag = Batch | Debug | Full | Help | Version | Eval String
  deriving (Eq,Show)

options :: [OptDescr Flag]
options = [ Option "d"  ["debug"]   (NoArg Debug)   "run in debugging mode"
          , Option "b"  ["batch"]   (NoArg Batch)   "run in batch mode"
          , Option "f"  ["full"]    (NoArg Full)    "do not truncate big terms"
          , Option "e"  ["eval"]    (ReqArg Eval "brunerie")   "normalize the given term"
          , Option ""   ["help"]    (NoArg Help)    "print help"
          , Option ""   ["version"] (NoArg Version) "print version number" ]

-- Version number, welcome message, usage and prompt strings
version, welcome, usage, prompt :: String
version = "1.0"
welcome = "cubical, version: " ++ version ++ "  (:h for help)\n"
usage   = "Usage: cubical [options] <file.ctt>\nOptions:"
prompt  = "> "

lexer :: String -> [Token]
lexer = resolveLayout True . myLexer

showTree :: (Show a, Print a) => a -> IO ()
showTree tree = do
  putStrLn $ "\n[Abstract Syntax]\n\n" ++ show tree
  putStrLn $ "\n[Linearized tree]\n\n" ++ printTree tree

-- Used for auto completion
searchFunc :: [String] -> String -> [Completion]
searchFunc ns str = map simpleCompletion $ filter (str `isPrefixOf`) ns

settings :: [String] -> Settings IO
settings ns = Settings
  { historyFile    = Nothing
  , complete       = completeWord Nothing " \t" $ return . searchFunc ns
  , autoAddHistory = True }

main :: IO ()
main = do
  args <- getArgs
  case getOpt Permute options args of
    (flags,files,[])
      | Help    `elem` flags -> putStrLn $ usageInfo usage options
      | Version `elem` flags -> putStrLn version
      | otherwise -> case files of
       []  -> do
         putStrLn welcome
         runInputT (settings []) (loop flags [] [] TC.verboseEnv)
       [f] -> do
         putStrLn welcome
         putStrLn $ "Loading " ++ show f
         initLoop flags f emptyHistory
       _   -> putStrLn $ "Input error: zero or one file expected\n\n" ++
                         usageInfo usage options
    (_,_,errs) -> putStrLn $ "Input error: " ++ concat errs ++ "\n" ++
                             usageInfo usage options

printdiv :: Int -> Int -> String
printdiv n m =
  printf "%.1f" ((fromIntegral n / fromIntegral m) :: Float)

humanReadable :: Int -> String
humanReadable n =
  if n < 1000 then show n
  else if n < 1000000 then printdiv n 1000 ++ "K"
  else if n < 1000000000 then printdiv n 1000000 ++ "M"
  else printdiv n 1000000000 ++ "G"

shrink :: String -> String
shrink s =
  if length s > 3959 then
    take 1701 s ++ "\n\n[...] (the full term has "
    ++ humanReadable (length s) ++ " characters, use option -f to print it)\n\n"
    ++ reverse (take 1701 (reverse s))
  else s

getEvalRequests :: [Flag] -> [String]
getEvalRequests [] = []
getEvalRequests (Eval s : l) = s : (getEvalRequests l)
getEvalRequests (_ : l) = getEvalRequests l

-- Initialize the main loop
initLoop :: [Flag] -> FilePath -> History -> IO ()
initLoop flags f hist = do
  -- Parse and type check files
  (_,_,mods) <- E.catch (imports True ([],[],[]) f)
                        (\e -> do putStrLn $ unlines $
                                    ("Exception: " :
                                     (takeWhile (/= "CallStack (from HasCallStack):")
                                                   (lines $ show (e :: SomeException))))
                                  return ([],[],[]))
  -- Translate to TT
  let res = runResolver $ resolveModules mods
  case res of
    Left err    -> do
      putStrLn $ "Resolver failed: " ++ err
      runInputT (settings []) (putHistory hist >> loop flags f [] TC.verboseEnv)
    Right (adefs,names) -> do
      -- After resolivng the file check if some definitions were shadowed:
      let ns = map fst names
          uns = nub ns
          dups = ns \\ uns
      unless (dups == []) $
        putStrLn $ "Warning: the following definitions were shadowed [" ++
                   intercalate ", " dups ++ "]"
      (merr,tenv) <- TC.runDeclss TC.verboseEnv adefs
      case merr of
        Just err -> putStrLn $ "Type checking failed: " ++ err
        Nothing  -> unless (mods == []) $ putStrLn "File loaded."
      let evalRequests = getEvalRequests flags
      if evalRequests /= [] || Batch `elem` flags
        then runInputT (settings [])
                       (foldr (exec (Full : flags) f names tenv True) (return ()) evalRequests)
        else -- Compute names for auto completion
             runInputT (settings [n | (n,_) <- names])
               (putHistory hist >> loop flags f names tenv)

-- Adapted from [renderIO] to make it insert newlines regularly
renderIOEmacsSafe :: Handle -> SimpleDocStream ann -> IO ()
renderIOEmacsSafe h = go 0
  where
    go :: Int -> SimpleDocStream ann -> IO ()
    go n doc = case doc of
             SFail              -> panicUncaughtFail
             SEmpty             -> pure ()
             SChar c rest       -> do hPutChar h c
                                      go2 (n + 1) rest
             SText l t rest     -> do IO.hPutStr h t
                                      go2 (n + l) rest
             SLine m rest       -> do hPutChar h '\n'
                                      IO.hPutStr h (T.replicate m (T.pack " "))
                                      go2 (n + m + 1) rest
             SAnnPush _ann rest -> go n rest
             SAnnPop rest       -> go n rest

    go2 :: Int -> SimpleDocStream ann -> IO ()
    go2 n doc =
      if n > 220 then do
       -- hPutChar h '\n'
        go 0 doc
      else
        go n doc

-- The main loop
loop :: [Flag] -> FilePath -> [(CTT.Ident,SymKind)] -> TC.TEnv -> Interpreter ()
loop flags f names tenv = do
  input <- getInputLine prompt
  case input of
    Nothing    -> outputStrLn help >> loop flags f names tenv
    Just ":q"  -> return ()
    Just ":r"  -> getHistory >>= lift . initLoop flags f
    Just (':':'l':' ':str)
      | ' ' `elem` str -> do outputStrLn "Only one file allowed after :l"
                             loop flags f names tenv
      | otherwise      -> getHistory >>= lift . initLoop flags str
    Just (':':'c':'d':' ':str) -> do lift (setCurrentDirectory str)
                                     loop flags f names tenv
    Just ":h"  -> outputStrLn help >> loop flags f names tenv
    Just str'  -> exec flags f names tenv False str' (loop flags f names tenv)

exec :: [Flag] -> FilePath -> [(CTT.Ident,SymKind)] -> TC.TEnv -> Bool -> String -> Interpreter () -> Interpreter ()
exec flags f names tenv batchmode str' k =
      let strinit = case batchmode of
            True -> "\n> " ++ str' ++ "\n"
            False -> "" in
      let (msg,str,mod) = case str' of
            (':':'n':' ':str) ->
              ("NORMEVAL: ",str,E.normal [])
            str -> ("EVAL: ",str,id)
      in case pExp (lexer str) of
      Bad err -> outputStrLn (strinit ++ "Parse error: " ++ err) >> k
      Ok  exp ->
        case runResolver $ local (insertIdents names) $ resolveExp exp of
          Left  err  -> do outputStrLn (strinit ++ "Resolver failed: " ++ err)
                           k
          Right body -> do
            x <- liftIO $ TC.runInfer tenv body
            case x of
              Left err -> do outputStrLn (strinit ++ "Could not type-check: " ++ err)
                             k
              Right _  -> do
                start <- liftIO getCurrentTime
                let e = mod $ E.eval (TC.env tenv) body
                -- Let's not crash if the evaluation raises an error:
                -- Use layoutCompact for now, if we want prettier printing use something nicer
                when (Full `elem` flags) $
                  liftIO $ catch (renderIOEmacsSafe stdout (layoutCompact (pretty strinit <+> pretty msg <+> showVal e <+> pretty "\n")))
                                 (\e -> putStrLn ("Exception: " ++
                                                  show (e :: SomeException)))
                when (Full `notElem` flags) $
                  liftIO $ catch (putStrLn (strinit ++ shrink (msg ++ show (showVal e))))
                                 (\e -> putStrLn ("Exception: " ++
                                                  show (e :: SomeException)))
                liftIO $ catch (putStrLn ("#hcomps: " ++ show (countHComp e)))
                               (\e -> putStrLn ("Exception: " ++
                                                show (e :: SomeException)))
--                 liftIO $ IO.writeFile "asdf.txt" (renderStrict (layoutCompact (showVal e)))
                stop <- liftIO getCurrentTime
                -- Compute time and print nicely
                let time = diffUTCTime stop start
                    secs = read (takeWhile (/='.') (init (show time)))
                    rest = read ('0':dropWhile (/='.') (init (show time)))
                    mins = secs `quot` 60
                    sec  = printf "%.3f" (fromInteger (secs `rem` 60) + rest :: Float)
                liftIO $ catch (putStrLn $ "Time: " ++ show mins ++ "m" ++ sec ++ "s")
                               (\e -> putStrLn ("Exception: " ++
                                                show (e :: SomeException)))
                -- Only print in seconds:
                -- when (Time `elem` flags) $ outputStrLn $ "Time: " ++ show time
                k

-- (not ok,loaded,already loaded defs) -> to load ->
--   (new not ok, new loaded, new defs)
-- the bool determines if it should be verbose or not
imports :: Bool -> ([String],[String],[Module]) -> String ->
           IO ([String],[String],[Module])
imports v st@(notok,loaded,mods) f
  | f `elem` notok  = error ("Looping imports in " ++ f)
  | f `elem` loaded = return st
  | otherwise       = do
    b <- doesFileExist f
    when (not b) $ error (f ++ " does not exist")
    let prefix = dropFileName f
    s <- readFile f
    let ts = lexer s
    case pModule ts of
      Bad s -> error ("Parse failed in " ++ show f ++ "\n" ++ show s)
      Ok mod@(Module (AIdent (_,name)) imp decls) -> do
        let imp_ctt = [prefix ++ i ++ ".ctt" | Import (AIdent (_,i)) <- imp]
        when (name /= dropExtension (takeFileName f)) $
          error ("Module name mismatch in " ++ show f ++ " with wrong name " ++ name)
        (notok1,loaded1,mods1) <-
          foldM (imports v) (f:notok,loaded,mods) imp_ctt
        when v $ putStrLn $ "Parsed " ++ show f ++ " successfully!"
        return (notok,f:loaded1,mods1 ++ [mod])

help :: String
help = "\nAvailable commands:\n" ++
       "  <statement>     infer type and evaluate statement\n" ++
       "  :n <statement>  normalize statement\n" ++
       "  :q              quit\n" ++
       "  :l <filename>   loads filename (and resets environment before)\n" ++
       "  :cd <path>      change directory to path\n" ++
       "  :r              reload\n" ++
       "  :h              display this message\n"
