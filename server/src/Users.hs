{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Users where

import Control.Monad.Except
import qualified Crypto.Hash.SHA256 as H
import qualified Data.ByteString.Char8 as C
import qualified Data.ByteString.Lazy.Char8 as CL
import Data.Proxy
import qualified Data.Text as T
import Data.Text (Text)
import Data.Time.Clock
import Database
import Database.Persist
import Database.Persist.Postgresql
import Servant
import Servant.Server.Experimental.Auth
import Web.JWT (Secret)

import Auth (hashPassword, signToken)
import Schema
import Types

type UsersAPI
   = "profile" :> AuthProtect "JWT" :> Get '[ JSON] UserProfile :<|> "login" :> ReqBody '[ JSON] Login :> Post '[ JSON] ReturnToken :<|> "register" :> ReqBody '[ JSON] Register :> Post '[ JSON] ReturnToken

-- | We need to specify the data returned after authentication
type instance AuthServerData (AuthProtect "JWT") = UserEntity

usersAPI :: Proxy UsersAPI
usersAPI = Proxy :: Proxy UsersAPI

usersServer :: Secret -> ConnectionString -> RedisConfig -> Server UsersAPI
usersServer secretKey connString redisConfig =
  fetchUserProfileHandler :<|> loginHandler secretKey connString :<|>
  registerUserHandler secretKey connString redisConfig

fetchUserProfileHandler :: UserEntity -> Handler UserProfile
fetchUserProfileHandler UserEntity {..} =
  return
    UserProfile
      { proEmail = userEntityEmail
      , proAvailableChips = userEntityAvailableChips
      , proChipsInPlay = userEntityChipsInPlay
      , proUsername = Username userEntityUsername
      , proUserCreatedAt = userEntityCreatedAt
      }

------------------------------------------------------------------------
-- | Handlers
loginHandler :: Secret -> ConnectionString -> Login -> Handler ReturnToken
loginHandler secretKey connString Login {..} = do
  maybeUser <- liftIO $ dbGetUserByLogin connString loginWithHashedPswd
  maybe (throwError unAuthErr) createToken maybeUser
  where
    unAuthErr = err401 {errBody = "Incorrect email or password"}
    createToken UserEntity {..} =
      signToken secretKey (Username userEntityUsername)
    loginWithHashedPswd = Login {loginPassword = hashPassword loginPassword, ..}

-- when we register new user we check to see if email and username are already taken
-- if they are then the exception will be propagated to the client
registerUserHandler ::
     Secret
  -> ConnectionString
  -> RedisConfig
  -> Register
  -> Handler ReturnToken
registerUserHandler secretKey connString redisConfig Register {..} = do
  let hashedPassword = hashPassword newUserPassword
  currTime <- liftIO getCurrentTime
  let (Username username) = newUsername
  let newUser =
        UserEntity
          { userEntityUsername = username
          , userEntityEmail = newUserEmail
          , userEntityPassword = hashedPassword
          , userEntityAvailableChips = 3000
          , userEntityChipsInPlay = 0
          , userEntityCreatedAt = currTime
          }
  registrationResult <-
    liftIO $ runExceptT $ dbRegisterUser connString redisConfig newUser
  case registrationResult of
    Left err -> throwError $ err401 {errBody = CL.pack $ T.unpack err}
    _ -> signToken secretKey newUsername
