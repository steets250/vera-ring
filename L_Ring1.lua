module("L_Ring1", package.seeall)

_PLUGIN_NAME = "Ring"
_PLUGIN_COMPACT = "Ring"
_PLUGIN_REQUESTNAME = _PLUGIN_COMPACT
MYTYPE = "urn:schemas-steets250-com:device:Ring:1"
MYSID = "urn:steets250-com:serviceId:Ring1"

local json = require"dkjson"
local RingAPI = require"L_RingAPI"

-- Random SHIT
D = function(msg, ...)
    PFB.log(PFB.LOGLEVEL.DEBUG1, msg, ...)
end

L = function(msg, ...)
    PFB.log(PFB.LOGLEVEL.NOTICE, msg, ...)
end

function checkVersion(dev_id)
    L("checkVersion(%1)", dev_id)
    if luup.version_major < 7 then return false, "This plugin only runs under UI7 or above" end

    return true
end

function runOnce(dev_id)
    L("runOnce(%1)", dev_id)
end

local function variableChanged(dev, sid, var, oldVal, newVal, dev_id, a, b)
    L("Ring: variableChanged() called! extra arguments: %1, %2", a, b)
end

-- Helper Functions

local function count(T)
    if (not T or type(T) ~= 'table') then
        L('Ring: count(T) input error')

        return nil
    end

    local count = 0

    for _ in pairs(T) do
        count = count + 1
    end

    return count
end

function getVeraID(deviceId, label)
    L('Ring: checking for existing ' .. label .. ' from ' .. deviceId)

    for k, v in pairs(luup.devices) do
        if (v.device_num_parent == deviceId and v.id == label) then return k end
    end
end

function getRingID(deviceId)
	for k, v in pairs(luup.devices) do
        if (v.attributes.id == deviceId) then return tonumber(string.sub(v.id,1,-2)) end
    end
end

-- Battery Functions
local function getBatteryStatus(rootDevice, device, extension)
	local id = getVeraID(rootDevice, device.id .. extension)
    if (id and device["battery_life"]) then
    	luup.variable_set("urn:micasaverde-com:serviceId:HaDevice1", "BatteryLevel", device["battery_life"], id)
    end
end

-- Doorbell Functions
local function doorbellAbility(rootDevice, childDevices, device)
    luup.chdev.append(rootDevice, childDevices, device.id .. 'D', device.description .. ' Doorbell', "urn:schemas-steets250-com:device:RingDoorbell:1", "D_RingDoorbell1.xml", "I_Ring1.xml", "", true)
end

local function getDoorbellStatus(rootDevice, device)
    local id = getVeraID(rootDevice, device.id .. 'D')
    if (id) then
    	-- TODO
    end
end

-- Motion Functions
local function motionAbility(rootDevice, childDevices, device)
    luup.chdev.append(rootDevice, childDevices, device.id .. 'M', device.description .. ' Motion', "urn:schemas-micasaverde-com:device:MotionSensor:1", "D_MotionSensor1.xml", "I_Ring1.xml", "", true)
end

local function getMotionStatus(rootDevice, device)
    local id = getVeraID(rootDevice, device.id .. 'D')
    if (id) then end
end

-- Light Functions
local function lightAbility(rootDevice, childDevices, device)
    luup.chdev.append(rootDevice, childDevices, device.id .. 'L', device.description .. ' Light', "urn:schemas-upnp-org:device:BinaryLight:1", "D_BinaryLight1.xml", "I_Ring1.xml", "", true)
end

local function getLightStatus(rootDevice, device)
    local id = getVeraID(rootDevice, device.id .. 'L')

    print(device["led_status"])

    if (id and device["led_status"]) then
        if (device["led_status"] == "on") then
            luup.variable_set("urn:upnp-org:serviceId:SwitchPower1", "Status", 1, id)
        end

        if (device["led_status"] == "off") then
            luup.variable_set("urn:upnp-org:serviceId:SwitchPower1", "Status", 0, id)
        end
    end
end

local function setLightStatus(dev_id, params)
	local device = {id = getRingID(dev_id)}

	if (params.newTargetValue) then
		RingAPI.setLightOn(PFB.var.get("AuthToken"), device)
	else
		RingAPI.setLightOff(PFB.var.get("AuthToken"), device)
	end
end

-- Establishing Functions
local function establishDoorbot(childDevices, device)
    L('Ring: Establishing ' .. device.description)
    doorbellAbility(ROOT_DEVICE, childDevices, device)
    motionAbility(ROOT_DEVICE, childDevices, device)
end

local function establishCamera(childDevices, device)
    L('Ring: Establishing ' .. device.description)
    motionAbility(ROOT_DEVICE, childDevices, device)
    lightAbility(ROOT_DEVICE, childDevices, device)
end

local function establishDevices(devices)
    local childDevices = luup.chdev.start(ROOT_DEVICE)

    if (devices['doorbots'] and count(devices['doorbots']) ~= 0) then
        L('Ring: Found Doorbells')

        for i = 1, count(devices['doorbots']) do
            establishDoorbot(childDevices, devices['doorbots'][i])
        end
    end

    if (devices['stickup_cams'] and count(devices['stickup_cams']) ~= 0) then
        L('Ring: Found Cameras')

        for i = 1, count(devices['stickup_cams']) do
            establishCamera(childDevices, devices['stickup_cams'][i])
        end
    end

    if (devices['authorized_doorbots'] and count(devices['authorized_doorbots']) ~= 0) then
        L('Ring: Found Shared Doorbells')

        for i = 1, count(devices['authorized_doorbots']) do
            establishDoorbot(childDevices, devices['authorized_doorbots'][i])
        end
    end

    luup.chdev.sync(ROOT_DEVICE, childDevices)
end

-- Processing Functions
local function processDoorbot(rootDevice, device)
    L('Ring: Processing ' .. device.description)
    getBatteryStatus(ROOT_DEVICE, device, 'D')
    getBatteryStatus(ROOT_DEVICE, device, 'M')
    getDoorbellStatus(ROOT_DEVICE, device)
    getMotionStatus(ROOT_DEVICE, device)
end

local function processCamera(rootDevice, device)
    L('Ring: Processing ' .. device.description)
    getBatteryStatus(ROOT_DEVICE, device, 'M')
    getBatteryStatus(ROOT_DEVICE, device, 'L')
    getMotionStatus(ROOT_DEVICE, device)
    getLightStatus(ROOT_DEVICE, device)
end

local function processDevices(devices)
    if (devices['doorbots'] and count(devices['doorbots']) ~= 0) then
        for i = 1, count(devices['doorbots']) do
            processDoorbot(ROOT_DEVICE, devices['doorbots'][i])
        end
    end

    if (devices['stickup_cams'] and count(devices['stickup_cams']) ~= 0) then
        for i = 1, count(devices['stickup_cams']) do
            processCamera(ROOT_DEVICE, devices['stickup_cams'][i])
        end
    end

    if (devices['authorized_doorbots'] and count(devices['authorized_doorbots']) ~= 0) then
        for i = 1, count(devices['authorized_doorbots']) do
            processDoorbot(ROOT_DEVICE, devices['authorized_doorbots'][i])
        end
    end
end

local function checkDevices()
	local err, devices = RingAPI.getDevices(PFB.var.get("AuthToken"))

    if (err) then
        L("Ring: " .. (err and 'true' or 'false'))
        return
    end

    processDevices(devices)
end

--END--

-- This example function will be called by the demo timer set below in start()
local function timerExpired(a, b)
    L("Ring: timerExpired() called! arguments: %1, %2", a, b)

    local err, devices = RingAPI.getDevices(PFB.var.get("AuthToken"))

    if (err) then
        L("Ring: " .. (err and 'true' or 'false'))

        return
    end

    getLightStatus(ROOT_DEVICE, devices["stickup_cams"][1])
end

-- Do local initialization of plugin instance data and get things rolling.
function start(dev_id)
    D("start(%1)", dev_id)
    ROOT_DEVICE = dev_id
    PFB.loglevel = PFB.LOGLEVEL.DEFAULT
    PFB.var.init("Enabled", "1")
    PFB.var.init("ExampleVariable", "Initial Value")
    PFB.var.init("Username", "username_here")
    PFB.var.init("Password", "password_here")
    PFB.var.init("AuthToken", "xxxxxxxxxxxxxxxxxxxx")
    PFB.var.init("PollInterval", "5")

    -- Check for Enabled
    if PFB.var.getNumeric("Enabled", 1) == 0 then
        PFB.log(PFB.LOGLEVEL.err, "Disabled by configuration; aborting startup.")

        return true, "Disabled"
    end

    -- Create API Token
    local err, token = RingAPI.registerAPI(PFB.var.get("Username"), PFB.var.get("Password"), PFB.var.get("AuthToken"))

    if (err) then
        L("Ring " .. (err and 'true' or 'false'))

        if (PFB.isOpenLuup) then
            luup.variable_set("urn:upnp-org:serviceId:altui1", "DisplayLine1", "Invalid Login", ROOT_DEVICE)
            luup.variable_set("urn:upnp-org:serviceId:altui1", "DisplayLine2", "Check the username and password.", ROOT_DEVICE)
        end

        return false, "Unable to obtain token."

    else

        luup.variable_set("urn:upnp-org:serviceId:altui1", "DisplayLine1", "Connected to: ", ROOT_DEVICE)
        luup.variable_set("urn:upnp-org:serviceId:altui1", "DisplayLine2", PFB.var.get("Username"), ROOT_DEVICE)

    end

    PFB.var.set("AuthToken", token)
    -- Load and Process Devices
    local err, devices = RingAPI.getDevices(PFB.var.get("AuthToken"))

    if (err) then
        L("Ring " .. (err and 'true' or 'false'))

        return false, "Unable to obtain devices."
    end

    establishDevices(devices)

    -- local timerId = PFB.delay.interval(10, checkDevices)
    
    L("Ring: Startup complete/successful!")

    return true, "OK"
end

function handleRequest(request, params, outputformat, dev_id)
    L("handleRequest(%1,%2,%3,%4)", request, params, outputformat, dev_id)

    if params.action == "say" then
        return '{ "text": ' .. tostring(params.text) .. ' }', "application/json"
    else
        return "ERROR\r\nInvalid request", "text/plain"
    end
end

function actionLight(dev_id, params)
	L("actionLight(%1,%2)", dev_id, params)

	setLightStatus(dev_id, params)
end

function actionExample(dev_id, params)
    L("actionExample(%1,%2)", dev_id, params)
    -- Use: luup.call_action( "urn:steets250-com:serviceId:Ring1", "Example", { newValue="23" }, n )
    PFB.var.set("ExampleVariable", params.newValue)
end