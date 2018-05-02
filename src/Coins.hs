module Coins where

----------------------------------------
-- Post Coin Transactions to Fae
----------------------------------------
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
import FaeTX.Post
import qualified Network.WebSockets as WS
import Prelude
import Text.Pretty.Simple (pPrint)
import Types
import FaeTX.Types (Key, CoinTXID, TXConfig(GetCoinConfig))

-- given a previous cache returns a new cache with requested coins
getCoins :: Int -> Key -> CoinTXID -> IO (Either PostTXError PostTXResponse)
getCoins numCoins key coinCache = executeContract (GetCoinConfig key)

addCoinsToWallet :: Wallet -> CoinTXID -> Int -> Wallet
addCoinsToWallet (Wallet wallet) coinTXID numCoins = Wallet (Map.insert  coinTXID numCoins wallet)

emptyWallet :: Wallet
emptyWallet = Wallet Map.empty