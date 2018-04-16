{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Lib
  ( runServer
  ) where

import Control.Concurrent (MVar, modifyMVar, modifyMVar_, newMVar, readMVar)
import Control.Exception (finally)
import Control.Monad (forM_, forever)
import Data.Aeson
import qualified Data.ByteString.Lazy.Char8 as C
import Data.Maybe
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Data.Text.Lazy as X
import qualified Data.Text.Lazy.Encoding as D
import qualified Network.WebSockets as WS
import Prelude

import Auction
import Types

--Create a new, initial state:
newServerState :: ServerState
newServerState = ServerState {clients = [], auctions = []}

--Check if a user already exists (based on username):
clientExists :: Client -> ServerState -> Bool
clientExists client ServerState {..} = client `elem` clients

--Add a client (this does not check if the client already exists, you should do
--this yourself using `clientExists`):
addClient :: Client -> ServerState -> ServerState
addClient client ServerState {..} = ServerState {clients = client : clients, ..}

removeClient :: Client -> ServerState -> ServerState
removeClient client ServerState {..} =
  ServerState {clients = filteredClients, ..}
  where
    filteredClients = filter (/= client) clients

handleAuctionAction :: ServerState -> AuctionAction -> ServerState
handleAuctionAction ServerState {..} (CreateAuctionAction auction) =
  ServerState {auctions = [auction], ..}
handleAuctionAction ServerState {..} (BidAuctionAction bid) = ServerState {..}

--Send a message to all clients, and log it on stdout:
broadcast :: Text -> ServerState -> IO ()
broadcast message ServerState {..} = do
  T.putStrLn message
  forM_ clients $ \(Client (_, conn)) -> WS.sendTextData conn message

parseAuctionAction :: Text -> Maybe AuctionAction
parseAuctionAction jsonTxt = decode $ C.pack $ T.unpack jsonTxt

encodeAuctionAction :: AuctionAction -> Text
encodeAuctionAction a = T.pack $ show $ X.toStrict $ D.decodeUtf8 $ encode a

-- update auction in serverState based on action
updateServerState :: MVar ServerState -> Maybe AuctionAction -> Maybe (IO ())
updateServerState _ Nothing = Nothing
updateServerState state (Just action) =
  Just $
  modifyMVar_
    state
    (\serverState -> return (handleAuctionAction serverState action))

---modifyMVar_ :: MVar a -> (a -> IO a) -> IO ()
broadcastAuctionAction ::
     MVar ServerState -> Maybe AuctionAction -> Maybe (IO ())
broadcastAuctionAction _ Nothing = Nothing
broadcastAuctionAction state (Just auctionAction) =
  Just $ readMVar state >>= broadcast (encodeAuctionAction auctionAction)

--The talk function continues to read messages from a single client until he
--disconnects. All messages are broadcasted to the other clients.
-- also listens and broadcasts auction actions
talk :: WS.Connection -> MVar ServerState -> Client -> IO ()
talk conn state (Client (name, _)) =
  forever $ do
    msg <- WS.receiveData conn
    serverState <- readMVar state
  --  print $ "our unparsed ws message from" ++ T.unpack name
  --  putStrLn $ T.unpack msg
    print $ "our parsed ws message from: " ++ T.unpack name
    let parsedAuctionAction = parseAuctionAction msg
    print $ parseAuctionAction msg
    fromMaybe (pure ()) (updateServerState state parsedAuctionAction)
    fromMaybe (pure ()) (broadcastAuctionAction state parsedAuctionAction)
    print serverState
    --readMVar state >>= broadcast msg
    -- updateserverstate = updateServerState state parsedAuctionAction
    -- broadcastaction = (broadcastAuctionAction state parsedAuctionAction)
    --handleMsg msg = traverse_ fold [updateserverstate, broadcastaction] 

--actual server. For this purpose, we use the simple server provided by
--`WS.runServer`.
runServer :: IO ()
runServer = do
  state <- newMVar newServerState
  WS.runServer "127.0.0.1" 9160 $ application state

--Our main application has the type:
application :: MVar ServerState -> WS.ServerApp
--Note that `WS.ServerApp` is nothing but a type synonym for
--`WS.PendingConnection -> IO ()`.
--Our application starts by accepting the connection. In a more realistic
--application, you probably want to check the path and headers provided by the
--pending request.
--We also fork a pinging thread in the background. This will ensure the connection
--stays alive on some browsers.
application state pending = do
  conn <- WS.acceptRequest pending
  WS.forkPingThread conn 30
--When a client is succesfully connected, we read the first message. This should
--be in the format of "Hi! I am Jasper", where Jasper is the requested username.
  msg <- WS.receiveData conn
  clients <- readMVar state
  case msg
--Check that the given username is not already taken:
        of
    _
      | clientExists client clients ->
        WS.sendTextData conn ("User already exists" :: Text)
--All is right! We're going to allow the client, but for safety reasons we *first*
--setup a `disconnect` function that will be run when the connection is closed.
      | otherwise ->
        flip finally disconnect $
--We send a "Welcome!", according to our own little protocol. We add the client to
--the list and broadcast the fact that he has joined. Then, we give control to the
--'talk' function.
         do
          modifyMVar_ state $ \s -> do
            let s' = addClient client s
            T.putStrLn clientName
            --broadcast stringifiedJsonAction s'
            return s'
          talk conn state client
      where prefix = "Hi! I am "
            clientName =
              T.filter (\c -> c `notElem` ['"', ' ']) $
              T.drop (T.length prefix) msg
            client = Client (clientName, conn)
            sampleAction =
              CreateAuctionAction
                Auction
                  { initialValue = 1
                  , createdBy = "Argo"
                  , auctionStartTimestamp = "0200"
                  , maxNumBids = 3
                  }
            jsonAction = X.toStrict $ D.decodeUtf8 $ encode sampleAction
            stringifiedJsonAction = T.pack $ show jsonAction
            disconnect
                -- Remove client and return new state
             = do
              s <-
                modifyMVar state $ \s ->
                  let s' = removeClient client s
                   in return (s', s')
              broadcast (clientName `mappend` " disconnected") s
