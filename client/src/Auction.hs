{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

{--------------------------------------------------------
  Logic for Updating Auction State
---------------------------------------------------------}
module Auction where

import Control.Concurrent (MVar, modifyMVar, modifyMVar_, newMVar, readMVar)
import Control.Exception (finally)
import Control.Monad (forM_, forever)
import Data.Aeson
import qualified Data.List as Li
import Data.Map.Lazy (Map)
import qualified Data.Map.Lazy as Map
import Data.Monoid 

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Data.Text.Lazy as X
import qualified Data.Text.Lazy.Encoding as D
import Prelude
import Types
import SharedTypes
import Debug.Trace


bidOnAuction :: AucTXID -> Bid -> Map AucTXID Auction -> Map AucTXID Auction
bidOnAuction key (bid@Bid {..}) =
  Map.adjust
    (\auction@Auction {..} -> Auction {bids = bid : bids, ..})
    key

createAuction ::
     AucTXID -> Auction -> Map AucTXID Auction -> Map AucTXID Auction
createAuction aucTXID auction auctionsMap =
  Map.insert aucTXID auction auctionsMap

auctionStatus :: Auction -> String
auctionStatus auc@Auction {..}
  | noBids == 0             = "No Bids"
  | getIsWinningBid lastBid = getBidder lastBid <> " has Won"
  | otherwise               = highBidder <> " is Winning"
  where
    noBids = numBids auc
    lastBid = head bids
    highBidder = highestBidder auc
    getBidder Bid{..} = bidder

auctionEnded :: Auction -> Bool
auctionEnded Auction{..} = length bids == aucMaxBidCount

getIsWinningBid :: Bid -> Bool
getIsWinningBid Bid{..} = isWinningBid

getBidValue :: Bid -> Int
getBidValue Bid {..} = bidValue

numBids :: Auction -> Int
numBids Auction {..} = Prelude.length bids

getBidder :: Bid -> String
getBidder Bid {..} = bidder

hasBid :: String -> [Bid] -> Bool
hasBid username bids = (Li.any ((== username) . bidder) bids)

currentBidValue :: Auction -> Int
currentBidValue auc@Auction {..}
  | length bids > 0 = bidValue $ Li.head bids
  | otherwise = 0

getUserBidTotal :: Auction -> String -> Int
getUserBidTotal Auction {..} username = maybe 0 bidValue (Li.find (((==) username) . bidder) bids)
  --Li.foldr (\Bid{..} acc -> if bidder == username then bidValue + acc else acc) 0 bids


highestBidder :: Auction -> String
highestBidder Auction {..}
  | length bids > 0 = (getBidder . Li.head) bids
  | otherwise = "No Bidders"

--aucCurrentPrice Auction{..} = bidValue $ Li.head bids