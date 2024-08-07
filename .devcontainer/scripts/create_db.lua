#!/usr/bin/env lua

local mongo = require 'mongo'
local sodium = require 'sodium'
local uuid = require "lua_uuid"
local uuid_str = uuid()
local client = mongo.Client('mongodb://root:example@mongo')
local database = client:getDatabase('eiko')
local collection = client:getCollection('eiko', 'user')
local password = sodium.crypto_pwhash_str('password', sodium.crypto_pwhash_OPSLIMIT_MIN, sodium.crypto_pwhash_MEMLIMIT_MIN)

collection:insert{
      uuid = uuid_str,
      display_name = 'JaneBloggs',
      login = 'jane@bloggs.co.uk',
      hash = password,
}
