{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Clients where

import Control.Concurrent (MVar, modifyMVar, modifyMVar_, newMVar, readMVar)
import Control.Exception (finally)
import Control.Monad
import Data.Aeson
import qualified Data.ByteString.Lazy.Char8 as C
import Data.Foldable
import Data.Map.Lazy (Map)
import qualified Data.Map.Lazy as Map

import Data.Maybe
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as X
import qualified Data.Text.Lazy.Encoding as D
import qualified Network.WebSockets as WS
import Prelude
import Text.Pretty.Simple (pPrint)
import Utils

import Auction
import Types

-- call handler function for all decodable JSON Messages with client and Msg
clientListener :: Client -> (Client -> Msg -> IO a) -> IO b
clientListener client@Client {..} msgHandler =
  forever $ do
    msg <- WS.receiveData conn
    print msg
    sendMsgs (encodeMsg (RequestCoinsMsg 1)) [conn]
    for_ (parseMsg msg) $ \parsedMsg -> do
      pPrint $ (show msg) ++ "parsedmsg"
      msgHandler client parsedMsg

clientExists :: Client -> [Client] -> Bool
clientExists client clients = client `elem` clients

addClient :: Client -> [Client] -> [Client]
addClient client clients = client : clients

removeClient :: Client -> [Client] -> [Client]
removeClient client = filter (/= client)

getClientConn :: Client -> WS.Connection
getClientConn Client {..} = conn

getClientWallet :: Client -> Wallet
getClientWallet Client {..} = wallet

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

sendMsgs :: Text -> [WS.Connection] -> IO ()
sendMsgs msg connections = forM_ connections $ \conn -> WS.sendTextData conn msg

broadcast :: MVar ServerState -> Text -> IO ()
broadcast serverState msg =
  readMVar serverState >>=
  (\ServerState {..} -> do
     print
       ("outgoing to: [  " ++
        (show clients) ++ " ] ---------------> " ++ (show msg))
     sendMsgs msg (getClientWsConns clients))
     -- the output of PostTX should decide this
--broadcastValidAuctionActions ::
--     MVar ServerState -> Map String Auction -> Msg -> IO ()
--broadcast state auctions aucAction = broadcast state jsonMsg
--  where
--    jsonMsg = encodeMsg aucAction
