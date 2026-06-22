#!/usr/bin/env eco

local websocket = require 'eco.websocket'
local test = require 'test'

local function make_con()
    local con = {
        resp = {
            head_sent = false
        },
        sock = {},
        headers = {}
    }

    function con:discard_body()
        return true
    end

    function con:set_status(status)
        self.status = status
    end

    function con:add_header(name, value)
        self.headers[name] = value
    end

    function con:flush()
        self.flushed = true
        return true
    end

    return con
end

local function make_req(headers)
    headers = headers or {}

    if headers.upgrade == nil then
        headers.upgrade = 'websocket'
    end

    if headers.connection == nil then
        headers.connection = 'keep-alive, Upgrade'
    end

    if headers['sec-websocket-version'] == nil then
        headers['sec-websocket-version'] = '13'
    end

    return {
        major_version = 1,
        minor_version = 1,
        headers = headers
    }
end

do
    local con = make_con()
    local ws, err = websocket.upgrade(con, make_req())

    assert(ws == nil and err == 'not found "sec-websocket-key" request header')
    assert(con.status == nil and con.flushed == nil)
end

do
    local con = make_con()
    local ws, err = websocket.upgrade(con, make_req({
        ['sec-websocket-key'] = '===='
    }))

    assert(ws == nil and err == 'bad "sec-websocket-key" request header')
    assert(con.status == nil and con.flushed == nil)
end

do
    local con = make_con()
    local ws, err = websocket.upgrade(con, make_req({
        connection = 'keep-alive, Upgrade',
        ['sec-websocket-protocol'] = 'chat, echo',
        ['sec-websocket-key'] = 'dGhlIHNhbXBsZSBub25jZQ=='
    }))

    assert(ws, err)
    assert(con.status == 101)
    assert(con.headers['sec-websocket-accept'] == 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=')
    assert(con.headers['sec-websocket-protocol'] == 'chat')
    assert(con.flushed == true)
end

print('websocket upgrade tests passed')
