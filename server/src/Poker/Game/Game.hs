{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE LambdaCase #-}

module Poker.Game.Game where

import Control.Arrow
import Control.Lens
import Control.Monad.Random.Class
import Control.Monad.State

import Data.List
import qualified Data.List.Safe as Safe
import Data.List.Split
import Data.Maybe
import Data.Monoid
import Data.Text (Text)

import Poker.Game.Blinds
import Poker.Game.Hands
import Poker.Game.Utils
import Poker.Types

-- | Returns both the dealt players and remaining cards left in deck.
-- We return the new deck for the purposes of dealing the board cards 
-- over the remaining course of the hand.
dealToPlayers :: Deck -> [Player] -> (Deck, [Player])
dealToPlayers =
  mapAccumL
    (\(Deck cards) player ->
       if player ^. playerState == In
         then ( Deck $ drop 2 cards
              , (pockets .~ (PocketCards $ take 2 cards)) player)
         else (Deck cards, player))

dealBoardCards :: Int -> Game -> Game
dealBoardCards n game@Game {..} =
  Game {_board = _board <> boardCards, _deck = Deck newDeck, ..}
  where
    (boardCards, newDeck) = splitAt n (unDeck _deck)

deal :: Game -> Game
deal game@Game {..} = Game {_players = dealtPlayers, _deck = remainingDeck, ..}
  where
    (remainingDeck, dealtPlayers) = dealToPlayers (_deck) _players

-- Gets the next data constructor of the Street which represents
-- the name of the next game stage.
-- The term Street is poker terminology for hand stage.
getNextStreet :: Street -> Street
getNextStreet Showdown = minBound
getNextStreet _street = succ _street

-- Unless in the scenario where everyone is all in 
-- if no further player actions are possible (i.e betting has finished)
-- then actedThisTurn should be set to True for all active players in Hand.
-- This scenario occurs when all players or all but one players are all in. 
resetPlayers :: Game -> Game
resetPlayers game@Game {..} = (players .~ newPlayers) game
  where
    newPlayers = (bet .~ 0) . (actedThisTurn .~ False) <$> _players

-- When there are only two players in game (Heads Up) then the first player
-- to act PreFlop is the player at the dealer position.
-- First player to act is the player sitting to the right of the player
-- in the big blind position
progressToPreFlop :: Game -> Game
progressToPreFlop game@Game {..} =
  game &
  (street .~ PreFlop) .
  (currentPosToAct .~ firstPosToAct) .
  (players %~ (<$>) (actedThisTurn .~ False)) . deal . updatePlayersInHand
  where
    playerCount = length $ getActivePlayers _players
    incAmount = 2
    firstPosToAct =
      if playerCount == 2
        then _dealer
        else modInc incAmount _dealer (playerCount - 1)

progressToFlop :: Game -> Game
progressToFlop game
  | isEveryoneAllIn game = game & (street .~ Flop) . dealBoardCards 3
  | otherwise =
    game &
    (street .~ Flop) .
    (currentPosToAct .~ incPosToAct (_dealer game) game) .
    (maxBet .~ 0) . dealBoardCards 3 . resetPlayers

progressToTurn :: Game -> Game
progressToTurn game
  | isEveryoneAllIn game = game & (street .~ Turn) . dealBoardCards 1
  | otherwise =
    game &
    (street .~ Turn) .
    (maxBet .~ 0) .
    (currentPosToAct .~ incPosToAct (_dealer game) game) .
    dealBoardCards 1 . resetPlayers

progressToRiver :: Game -> Game
progressToRiver game@Game {..}
  | isEveryoneAllIn game = game & (street .~ River) . dealBoardCards 1
  | otherwise =
    game &
    (street .~ River) .
    (maxBet .~ 0) .
    (currentPosToAct .~ incPosToAct _dealer game) .
    dealBoardCards 1 . resetPlayers

progressToShowdown :: Game -> Game
progressToShowdown game@Game {..} =
  game &
  (street .~ Showdown) . (winners .~ winners') . (players .~ awardedPlayers)
  where
    winners' = getWinners game
    awardedPlayers = awardWinners _players _pot winners'

-- need to give players the chips they are due and split pot if necessary
-- if only one active player then this is a result of everyone else folding 
-- and they are awarded the entire pot
--
-- If only one player is active during the showdown stage then this means all other players
-- folded to him. The winning player then has the choice of whether to "muck"
-- (not show) his cards or not.
-- SinglePlayerShowdown occurs when everyone folds to one player
awardWinners :: [Player] -> Int -> Winners -> [Player]
awardWinners _players pot' =
  \case
    MultiPlayerShowdown winners' ->
      let chipsPerPlayer = pot' `div` length winners'
          playerNames = snd <$> winners'
       in (\p@Player {..} ->
             if _playerName `elem` playerNames
               then Player {_chips = _chips + chipsPerPlayer, ..}
               else p) <$>
          _players
    SinglePlayerShowdown _ ->
      (\p@Player {..} ->
         if p `elem` getActivePlayers _players
           then Player {_chips = _chips + pot', ..}
           else p) <$>
      _players

isEveryoneAllIn :: Game -> Bool
isEveryoneAllIn game@Game {..}
  | _street == PreDeal = False
  | _street == Showdown = False
  | numPlayersIn < 2 = False
  | haveAllPlayersActed game = (numPlayersIn - numPlayersAllIn) <= 1
  | otherwise = False
  where
    numPlayersIn = length $ getActivePlayers _players
    numPlayersAllIn =
      length $
      filter (\Player {..} -> _playerState == In && _chips == 0) _players

-- TODO move players from waitlist to players list
-- TODO need to send msg to players on waitlist when a seat frees up to inform them 
-- to choose a seat and set limit for them t pick one
-- TODO - have newBlindNeeded field which new players will initially be put into in order to 
-- ensure they cant play without posting a blind before the blind position comes round to them
-- new players can of course post their blinds early. In the case of an early posting the initial
-- blind must be the big blind. After this 'early' blind or the posting of a normal blind in turn the 
-- new player will be removed from the newBlindNeeded field and can play normally.
getNextHand :: Game -> Deck -> Game
getNextHand Game {..} newDeck =
  Game
    { _waitlist = newWaitlist
    , _maxBet = 0
    , _players = newPlayers
    , _board = []
    , _deck = newDeck
    , _winners = NoWinners
    , _street = PreDeal
    , _dealer = newDealer
    , _pot = 0
    , _currentPosToAct = nextPlayerToAct
    , ..
    }
  where
    incAmount = 1
    newDealer = modInc incAmount _dealer (length (getPlayersSatIn _players) - 1)
    freeSeatsNo = _maxPlayers - length _players
    newPlayers = resetPlayerCardsAndBets <$> _players
    newWaitlist = drop freeSeatsNo _waitlist
    nextPlayerToAct = modInc incAmount newDealer (length newPlayers - 1)

-- | If all players have acted and their bets are equal 
-- to the max bet then we can move to the next stage
haveAllPlayersActed :: Game -> Bool
haveAllPlayersActed game@Game {..}
  | _street == Showdown = True
  | _street == PreDeal = haveRequiredBlindsBeenPosted game
  | otherwise = not awaitingPlayerAction
  where
    activePlayers = getActivePlayers _players
    awaitingPlayerAction =
      any
        (\Player {..} ->
           not _actedThisTurn ||
           (_playerState == In && (_bet < _maxBet && _chips /= 0)))
        activePlayers

-- If all players have folded apart from a remaining player then the mucked boolean 
-- inside the player value will determine if we show the remaining players hand to the 
-- table. 
--
-- Otherwise we just get the handrankings of all active players.
getWinners :: Game -> Winners
getWinners game@Game {..} =
  if allButOneFolded game
    then SinglePlayerShowdown $
         head $
         flip (^.) playerName <$>
         filter (\Player {..} -> _playerState == In) _players
    else MultiPlayerShowdown $ maximums $ getHandRankings _players _board

-- Return the best hands and the active players (playerState of In) who hold
-- those hands.
--
-- If more than one player holds the same winning hand then the second part 
-- of the tuple will consist of all the players holding the hand
getHandRankings ::
     [Player] -> [Card] -> [((HandRank, PlayerShowdownHand), PlayerName)]
getHandRankings plyrs boardCards =
  (\(showdownHand, Player {..}) ->
     ((_2 %~ PlayerShowdownHand) showdownHand, _playerName)) <$>
  map
    (value . (++ boardCards) . unPocketCards . view pockets &&& id)
    remainingPlayersInHand
  where
    remainingPlayersInHand =
      filter
        (\Player {..} ->
           (_playerState /= Folded) ||
           (_playerState /= None) || null (unPocketCards _pockets))
        plyrs

-- Update active players states to prepare them for the next hand.
resetPlayerCardsAndBets :: Player -> Player
resetPlayerCardsAndBets Player {..} =
  Player
    { _pockets = PocketCards []
    , _playerState = newPlayerState
    , _bet = 0
    , _committed = 0
    , _actedThisTurn = False
    , ..
    }
  where
    newPlayerState =
      if _chips == 0
        then None
        else if _playerState == Folded || _playerState == In
               then In
               else None

-- The game should go straight to showdown if all but one players is In hand
allButOneFolded :: Game -> Bool
allButOneFolded game@Game {..} = _street /= PreDeal && length playersInHand <= 1
  where
    playersInHand = filter ((== In) . (^. playerState)) _players

getPlayer :: Text -> Int -> Player
getPlayer playerName chips =
  Player
    { _pockets = PocketCards []
    , _bet = 0
    , _playerState = In
    , _playerName = playerName
    , _committed = 0
    , _actedThisTurn = False
    , _chips = chips
    }

-- During PreDeal we start timing out players who do not post their respective blinds
-- in turn after an initial blind has been posted
--
-- No player is forced to post first blind during PreDeal (blind betting stage).
--
-- Important to note that this function is mainly for asserting whether we need to
-- time a player's action. Player actions which are not mandatory such as posting a blind
-- to start a game will not be timed actions. 
--
-- All possible player actions are either compulsary or optional. For example SitIn as a player is never forced to play a game. However if a player is already active in an 
-- ongoing hand then all future actions for this hand will be mandatory and therefore timed so that a given
-- player cannot postpone the game through inactivity for an indefinite amount of time.
--
-- Optional actions as as SitIn (changing player state to In to denote that they are active this hand) 
-- would return False in this function.
--
-- PostBlind actions are trickier. Depending on the context they will be compulsary or optional.
-- True is for a situation where the continued progression
-- of the game in a satisfactory timeframe is determined by the expediancy of the current
-- player's action. 
doesPlayerHaveToAct :: Text -> Game -> Bool
doesPlayerHaveToAct playerName game@Game {..}
  | _street == Showdown ||
      isEveryoneAllIn game ||
      (activePlayerCount < 2) ||
      haveAllPlayersActed game ||
      _playerState currentPlyrToAct /= In ||
      (_street == PreDeal && _maxBet == 0) = False
  | _street == PreDeal =
    currentPlayerNameToAct == playerName &&
    (blindRequiredByPlayer game playerName /= NoBlind)
  | otherwise = _playerName currentPlyrToAct == playerName
  where
    currentPlyrToAct = fromJust $ _players Safe.!! _currentPosToAct -- eh?! fromjust safe pointless
    currentPlayerNameToAct = _playerName currentPlyrToAct
    activePlayerCount =
      length $ filter (\Player {..} -> _playerState == In) _players
