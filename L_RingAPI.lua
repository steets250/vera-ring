module('L_RingAPI', package.seeall)

local RingAPI = {}
RingAPI.__index = RingAPI

--Required Packages
local https = require'ssl.https'
local json = require'dkjson'
local ltn12 = require'ltn12'

--Helper Functions
local function generate_hardware_id()
    local seed = luup and tonumber(luup.pk_accesspoint)

    if seed then
        math.randomseed(seed)
    end

    local fmt = '%02x'
    local uuid = {}

    for i = 1, 16 do
        uuid[#uuid + 1] = fmt:format(math.random(0, 255))
    end

    return table.concat(uuid)
end

local function validate_device(device)
    if (type(device) ~= 'table') then
        print('Device needs to be an object')

        return true
    end

    if (type(device.id) == nil) then
        print('Device.id not found')

        return true
    end

    return false
end

local function validate_number(num)
    if (type(num) ~= 'number') then
        print('Limit needs to be an number')

        return true
    end

    return false
end

--Global Variables
local API_VERSION = 11
local hardware_id = generate_hardware_id()

--1. Check login information and retrieve working token.
local function authenticate(username, password)
    if (not username) then
        print('Username is required.')

        return true
    end

    if (not password) then
        print('Password is required.')

        return true
    end

    print('Requesting auth token with ' .. username .. ' and ' .. password .. '.')

    local request_json = json.encode({
        client_id = 'ring_official_android',
        grant_type = 'password',
        username = username,
        password = password,
        scope = 'client'
    })

    local response_body = {}

    local _, response_code, _, _ = https.request{
        url = 'https://oauth.ring.com/oauth/token',
        method = 'POST',
        headers = {
            ['content-type'] = 'application/json',
            ['content-length'] = string.len(request_json)
        },
        source = ltn12.source.string(request_json),
        sink = ltn12.sink.table(response_body)
    }

    if (response_code ~= 200) then
        print('Auth token request produced error ' .. response_code .. '.')

        return true
    end

    response_body = table.concat(response_body)
    local response_json, _, err = json.decode(response_body, 1, nil)

    if (err) then
        print('Error converting auth token response to json.')

        return true
    end

    if (not response_json.access_token) then
        print('Auth token response did not contain the access token.')

        return true
    end

    return false, response_json.access_token
end

local function establish(authToken)
    if (not authToken) then
        print('Auth token is required.')

        return true
    end

    print('Requesting session token with ' .. authToken .. '.')

    local request_json = json.encode({
        device = {
            hardware_id = hardware_id,
            metadata = {
                api_version = API_VERSION
            },
            os = 'android'
        }
    })

    local response_body = {}

    local _, response_code, _, _ = https.request{
        url = 'https://api.ring.com/clients_api/session',
        method = 'POST',
        headers = {
            ['Authorization'] = 'bearer ' .. authToken,
            ['content-type'] = 'application/json',
            ['content-length'] = string.len(request_json)
        },
        source = ltn12.source.string(request_json),
        sink = ltn12.sink.table(response_body)
    }

    if (response_code ~= 201) then
        print('Session token request produced error ' .. response_code .. '.')

        return true
    end

    response_body = table.concat(response_body)
    local response_json, _, err = json.decode(response_body, 1, nil)

    if (err) then
        print('Error converting session token response to json.')

        return true
    end

    if (not response_json.profile) then
        print('Session token response did not contain the profile section.')

        return true
    end

    if (not response_json.profile.authentication_token) then
        print('Session token response did not contain the session token.')

        return true
    end

    return false, response_json.profile.authentication_token
end

function RingAPI.registerAPI(username, password, token)
    if (token and not RingAPI.getDevices(token)) then return false, token end
    local authErr, authToken = authenticate(username, password)
    if (authErr) then return true, nil end
    local accessErr, accessToken = establish(authToken)
    if (accessErr) then return true, nil end

    return false, accessToken
end

--2. Retrieve a list of devices in the account.
local function processParameters(parameters)
    if (not parameters) then return '' end
    local result = ''
    local first = true

    for key, value in pairs(parameters) do
        if (first) then
            result = '?' .. key .. '=' .. value
            first = false
        else
            result = result .. '&' .. key .. '=' .. value
        end
    end

    return result
end

local function makeRequest(token, url, method, parameters, request_body)
    print('Doing a ' .. method .. ' request to ' .. url .. '.')
    parameters = parameters or {}
    parameters['api_version'] = API_VERSION
    parameters['auth_token'] = token
    local request_headers = {}
    request_headers['user-agent'] = 'android:com.ringapp:2.0.67(423)'
    local response_body = {}

    if (request_body) then
        request_json = json.encode(request_body)
        request_headers['content-type'] = 'application/x-www-form-urlencoded'
        request_headers['content-length'] = request_json.length

        _, response_code, _, _ = https.request{
            url = url .. processParameters(parameters),
            method = method,
            headers = request_headers,
            source = ltn12.source.string(request_json),
            sink = ltn12.sink.table(response_body)
        }
    else
        _, response_code, _, _ = https.request{
            url = url .. processParameters(parameters),
            method = method,
            headers = headers,
            sink = ltn12.sink.table(response_body)
        }
    end

    if (response_code ~= 200) then
        print('API Request was not a success, response code ' .. response_code)

        return true
    end

    response_body = table.concat(response_body)
    local response_json, _, err = json.decode(response_body, 1, nil)

    if (err) then
        print('Error converting API response to json.')

        return true
    end

    return false, response_json
end

function RingAPI.getDevices(token)
    return makeRequest(token, 'http://api.ring.com/clients_api/ring_devices', 'GET')
end

--3. Retrieve device details for each device.
function RingAPI.getDoorbotHealth(token, device)
    if (validate_device(device)) then return makeRequest(token, 'http://api.ring.com/clients_api/doorbots/' .. device.id .. '/health', 'GET') end

    return true
end

function RingAPI.getHistory(token, limit)
    return makeRequest(token, 'http://api.ring.com/clients_api/doorbots/history', 'GET', {
        limit = limit
    })
end

function RingAPI.getActiveDings(token, burst)
    return makeRequest(token, 'http://api.ring.com/clients_api/dings/active', 'GET', {
        burst = burst
    })
end

function RingAPI.getChimeDND(token, device)
    if (validate_device(device)) then return makeRequest(token, 'http://api.ring.com/clients_api/chimes/' .. device.id .. '/do_not_disturb', 'GET') end

    return true
end

--4. Provide access to individual device control.
function RingAPI.setLightOn(token, device)
    if (validate_device(device)) then return makeRequest(token, 'http://api.ring.com/clients_api/doorbots/' .. device.id .. '/floodlight_light_on', 'GET') end

    return true
end

function RingAPI.setLightOff(token, device)
    if (validate_device(device)) then return makeRequest(token, 'http://api.ring.com/clients_api/doorbots/' .. device.id .. '/floodlight_light_off', 'GET') end

    return true
end

function RingAPI.setChimeDND(token, device, time)
    if (validate_device(device) and validate_number(time)) then
        return makeRequest(token, 'http://api.ring.com/clients_api/doorbots/' .. device.id .. '/floodlight_light_off', 'POST', nil, {
            time = time
        })
    end

    return true
end

function RingAPI.setDoorbotDND(token, device, time)
    if (validate_device(device)) then
        if (time == 0) then
            return makeRequest(token, 'http://api.ring.com/clients_api/doorbots/' .. device.id .. '/motion_snooze/clear', 'POST', nil, {
                time = time
            })
        else
            return makeRequest(token, 'http://api.ring.com/clients_api/doorbots/' .. device.id .. '/motion_snooze', 'POST', nil, {
                time = time
            })
        end
    end

    return true
end

return RingAPI