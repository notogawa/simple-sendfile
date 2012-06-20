{-# LANGUAGE ForeignFunctionInterface #-}

module Network.Sendfile.BSD (
    sendfile
  , sendfileWithHeader
  ) where

import Control.Concurrent
import Control.Exception
import Control.Monad
import Data.ByteString (ByteString)
import Foreign.C.Error (eAGAIN, eINTR, getErrno, throwErrno)
import Foreign.C.Types (CInt, CSize)
import Foreign.Marshal (alloca)
import Foreign.Ptr (Ptr, nullPtr)
import Foreign.Storable (peek)
import Network.Sendfile.Types
import Network.Socket
import System.Posix.IO
import System.Posix.Types (Fd(..), COff)

{-|
   Simple binding for sendfile() of BSD.

   - Used system calls: open(), sendfile(), and close().

   The fourth action argument is called when a file is sent as chunks.
   Chucking is inevitable if the socket is non-blocking (this is the
   default) and the file is large. The action is called after a chunk
   is sent and bofore waiting the socket to be ready for writing.
-}
sendfile :: Socket -> FilePath -> FileRange -> IO () -> IO ()
sendfile sock path range hook = bracket
    (openFd path ReadOnly Nothing defaultFileFlags)
    closeFd
    sendfile'
  where
    dst = Fd $ fdSocket sock
    sendfile' fd = alloca $ \lenp -> case range of
        EntireFile -> sendEntire dst fd 0 lenp hook
        PartOfFile off len -> do
            let off' = fromInteger off
                len' = fromInteger len
            sendPart dst fd off' len' lenp hook

sendEntire :: Fd -> Fd -> COff -> Ptr COff -> IO () -> IO ()
sendEntire dst src off lenp hook = do
    rc <- c_sendfile src dst off 0 lenp
    when (rc /= 0) $ do
        errno <- getErrno
        if errno `elem` [eAGAIN, eINTR] then do
            sent <- peek lenp
            hook
            threadWaitWrite dst
            sendEntire dst src (off + sent) lenp hook
          else
            throwErrno "Network.SendFile.BSD.sendEntire"

sendPart :: Fd -> Fd -> COff -> CSize -> Ptr COff -> IO () -> IO ()
sendPart dst src off len lenp hook = do
    rc <- c_sendfile src dst off len lenp
    when (rc /= 0) $ do
        errno <- getErrno
        if errno `elem` [eAGAIN, eINTR] then do
            sent <- peek lenp
            let off' = off + sent
                len' = len - fromIntegral sent
            hook
            threadWaitWrite dst
            sendPart dst src off' len' lenp hook
          else
            throwErrno "Network.SendFile.BSD.sendPart"

c_sendfile :: Fd -> Fd -> COff -> CSize -> Ptr COff -> IO CInt
c_sendfile fd s offset len lenp = c_sendfile' fd s offset len nullPtr lenp 0

foreign import ccall unsafe "sys/uio.h sendfile" c_sendfile'
    :: Fd -> Fd -> COff -> CSize -> Ptr () -> Ptr COff -> CInt -> IO CInt

sendfileWithHeader :: Socket -> FilePath -> FileRange -> IO () -> [ByteString] -> IO ()
sendfileWithHeader = undefined
