module Main (
	main
	) where

import Control.Monad.Error
import Data.Aeson
import Data.Aeson.Encode.Pretty (encodePretty)
import Data.ByteString.Lazy (toStrict)
import qualified Data.Map as M
import Data.Monoid (Monoid(..))
import qualified Data.Text as T (unpack, pack)
import qualified Data.Text.Encoding as T (decodeUtf8)

import HDocs.Haddock
import HDocs.Module

import System.Console.GetOpt
import System.Environment (getArgs)
import System.FilePath (takeExtension)
import System.IO

data HDocsOptions = HDocsOptions {
	optionPretty :: Bool,
	optionGHC :: [String] }

instance Monoid HDocsOptions where
	mempty = HDocsOptions False []
	mappend l r = HDocsOptions (optionPretty l || optionPretty r) (optionGHC l ++ optionGHC r)

opts :: [OptDescr HDocsOptions]
opts = [
	Option [] ["pretty"] (NoArg $ HDocsOptions True []) "pretty JSON output",
	Option ['g'] ["ghc"] (ReqArg (\s -> HDocsOptions False [s]) "GHC_OPT") "option to pass to GHC"]

main :: IO ()
main = do
	hSetEncoding stdout utf8

	(cfgs, cmds, _) <- fmap (getOpt Permute opts) getArgs

	let
		cfg = mconcat cfgs
		isPretty = optionPretty cfg

		toStr :: ToJSON a => a -> String
		toStr = T.unpack . T.decodeUtf8 . toStrict . encode' where
			encode'
				| isPretty = encodePretty
				| otherwise = encode

		jsonError :: String -> Value
		jsonError err = object [
			T.pack "error" .= err]

		run :: ToJSON a => ErrorT String IO a -> IO ()
		run act = runErrorT act >>= putStrLn . either (toStr . jsonError) toStr

		loadDocs :: String -> ErrorT String IO ModuleDocMap
		loadDocs m
			| takeExtension m == ".hs" = liftM snd $ readSource (optionGHC cfg) m
			| otherwise = moduleDocs (optionGHC cfg) m

	case cmds of
		["dump", "r"] -> run $ liftM (M.map formatDocs) $ installedDocs (optionGHC cfg)
		["dump"] -> run $ liftM (M.map formatDocs) $ readInstalledDocs (optionGHC cfg)
		[m] -> run $ liftM formatDocs $ loadDocs m
		[m, n] -> run $ liftM formatDocs $ do
			docs <- loadDocs m
			maybe (throwError $ "Symbol '" ++ n ++ "' not found") (return . M.singleton n) $ M.lookup n docs
		_ -> printUsage

printUsage :: IO ()
printUsage = mapM_ putStrLn [
	"Usage:",
	"  hdocs <module> - get docs for module/file",
	"  hdocs <module> <name> - get docs for name in module/file",
	"  hdocs dump [r] - dump all installed docs, if [r], find docs for reexported declarations",
	"",
	usageInfo "flags" opts]
