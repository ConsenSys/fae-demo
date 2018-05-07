{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Clients where

import Control.Concurrent (MVar, modifyMVar, modifyMVar_, newMVar, readMVar)
import Control.Exception (finally)
import Control.Monad
import qualified Data.ByteString.Lazy.Char8 as C
import Data.Foldable
import Data.Map.Lazy (Map)
import qualified Data.Map.Lazy as Map
import Data.Maybe
import Data.Text (Text)
import qualified Network.WebSockets as WS
import Prelude
import Text.Pretty.Simple (pPrint)
import Types
import Utils
import Shared

-- call handler function for all decodable JSON Messages with client and Msg
clientListener ::
     MVar ServerState
  -> WS.Connection
  -> Text
  -> (MVar ServerState -> Text -> Msg -> IO a)
  -> IO b
clientListener state conn clientName msgCallback =
  forever $ do
    msg <- WS.receiveData conn
    print msg
    sendMsg conn (RequestCoins 1)
    for_ (parseMsg msg) $ \parsedMsg -> do
      pPrint $ (show msg) ++ "parsedmsg"
      msgCallback state clientName parsedMsg

clientExists :: Client -> [Client] -> Bool
clientExists client clients = client `elem` clients

addClient :: Client -> [Client] -> [Client]
addClient client clients = client : clients

removeClient :: Client -> [Client] -> [Client]
removeClient client = filter (/= client)

getClientConn :: Client -> WS.Connection
getClientConn Client {..} = conn

getClient :: [Client] -> Text -> Maybe Client
getClient clients clientName = find (\Client {..} -> name == clientName) clients

getClientWallet :: [Client] -> Text -> Maybe Wallet
getClientWallet clients clientName = do
  Client {..} <- getClient clients clientName
  return wallet

updateClientWallet :: [Client] -> Client -> Wallet -> [Client]
updateClientWallet clients client@Client {..} newWallet =
  map
    (\c@Client {..} ->
       if c == client
         then Client {wallet = newWallet, ..}
         else c)
    clients

getClientWsConns :: [Client] -> [WS.Connection]
getClientWsConns = Prelude.map getClientConn

sendMsgs :: [WS.Connection] -> Msg -> IO ()
sendMsgs conns msg = forM_ conns $ \conn -> sendMsg conn msg

sendMsg :: WS.Connection -> Msg -> IO ()
sendMsg conn msg = WS.sendTextData conn (encodeMsg msg)

broadcast :: MVar ServerState -> Msg -> IO ()
broadcast serverState msg =
  readMVar serverState >>=
  (\ServerState {..} -> do
     print
       ("outgoing to: [  " ++
        (show clients) ++ " ] ---------------> " ++ (show msg))
     sendMsgs (getClientWsConns clients) msg)
     -- the output of PostTX should decide this
--broadcastValidAuctionActions ::
--     MVar ServerState -> Map String Auction -> Msg -> IO ()
--broadcast state auctions aucAction = broadcast state jsonMsg
--  where
--    jsonMsg = encodeMsg aucAction
