#!/usr/bin/env lua

local mongo = require 'mongo'
local client = mongo.Client('mongodb://root:example@mongo')
local database = client:getDatabase('eiko')
local collection = client:getCollection('eiko', 'user')

collection:insert{
      uuid= '8ebe702b-06cc-485d-b8c8-f63bc3f0a797',
      display_name= 'JaneBloggs',
      login= 'jane@bloggs.co.uk',
      hash='asdf',
}
