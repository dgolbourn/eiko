#!/usr/bin/env lua

local mongo = require 'mongo'
local sodium = require 'sodium'
local uuid = require "uuid"
local config = require "eiko.config"
local client = mongo.Client(config.authenticator.db)
local collection = client:getCollection('eiko', 'user')

collection:insert{
      uuid = uuid(),
      display_name = 'JaneBloggs',
      login = 'jane@bloggs.co.uk',
      hash = sodium.crypto_pwhash_str('password', sodium.crypto_pwhash_OPSLIMIT_MIN, sodium.crypto_pwhash_MEMLIMIT_MIN),
}

collection:insert{
      uuid = uuid(),
      display_name = 'DavePerson',
      login = 'dave@person.com',
      hash = sodium.crypto_pwhash_str('password', sodium.crypto_pwhash_OPSLIMIT_MIN, sodium.crypto_pwhash_MEMLIMIT_MIN),
}

collection:insert{
      uuid = uuid(),
      display_name = 'Pam1234',
      login = 'pam1234@example.co.uk',
      hash = sodium.crypto_pwhash_str('password', sodium.crypto_pwhash_OPSLIMIT_MIN, sodium.crypto_pwhash_MEMLIMIT_MIN),
}
