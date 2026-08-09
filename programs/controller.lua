package.path = package.path .. ";/?.lua"
local channels = require("protocols.channels")
local network = require("protocols.network")
local calculate = require("protocols.calculate")
local movement = require("programs.movement")
local geometry = require("protocols.geometry")

local arm_id = geometry.ARM_ID or 1
local arm_channel = channels.ARM_BASE + arm_id
local ack_channel = channels.BEARING_BASE + arm_id * 5 + channels.BEARING_ACK_OFFSET

local speed = peripheral.find("Create_RotationSpeedController")
local modem = peripheral.find("modem") or error("No modem", 0)
-- Requests from ships arrive on this arm's own channel
modem.open(arm_channel)
-- Bearing acknowledgements arrive on this arm's ack channel
modem.open(ack_channel)

-- This arm is currently serving a ship (docking in progress)
local busy = false
-- A ship is physically docked to this arm
local docked = false

-- If chunk is loaded and arm is still docked
if redstone.getAnalogInput("front") == 15 then
	docked = true
end

-- Broadcast heartbeats for 5 seconds so bearing computers can
-- discover this arm controller before we send any commands.
-- Each bearing scans for 5s — one heartbeat per second guarantees
-- at least one falls inside its scan window.
for _ = 1, 5 do
	modem.transmit(channels.ARM_HEARTBEAT, arm_channel, {
		id = arm_id,
		channel = arm_channel,
		status = docked and "docked" or "idle",
		pos = { x = geometry.ARM.x, y = geometry.ARM.y, z = geometry.ARM.z },
		radius = geometry.ARM_RADIUS,
		initial_angle = geometry.INITIAL_ARM_ANGLE,
	})
	sleep(1)
end

-- Now that bearings have had time to discover this arm, calibrate
if not docked then
	speed.setTargetSpeed(-32)
	movement.calibrate(1, modem, arm_id)
	sleep(4)
	speed.setTargetSpeed(-4)
end

-- Broadcasts this arm's status and position so ships can
-- find the closest available arm.
local function heartbeat()
	while true do
		local status = "idle"
		if docked then
			status = "docked"
		elseif busy then
			status = "busy"
		end
		modem.transmit(channels.ARM_HEARTBEAT, arm_channel, {
			id = arm_id,
			channel = arm_channel,
			status = status,
			pos = { x = geometry.ARM.x, y = geometry.ARM.y, z = geometry.ARM.z },
			radius = geometry.ARM_RADIUS,
			initial_angle = geometry.INITIAL_ARM_ANGLE,
		})
		sleep(2)
	end
end

-- Handles docking requests from ships. Only the ship that sent
-- the request is replied to, on its own channel.
local function dock()
	while true do
		local raw = network.poll(arm_channel, 1)
		if type(raw) == "table" and raw.arm == arm_id and type(raw.channel) == "number" then
			if busy or docked then
				print("Busy, rejecting ship..")
				modem.transmit(raw.channel, arm_channel, false)
			else
				busy = true
				print("Found ship.. ")
				local data = calculate.angles(calculate.process(raw))
				if movement.goto(data, modem, raw.channel, arm_channel, arm_id) then
					-- Initial timer before checking comparator signal
					sleep(10)
					while redstone.getAnalogInput("front") >= 1 do
						print("Dock is close..")
						sleep(0.5)
						if redstone.getAnalogInput("front") == 15 then
							docked = true
							while redstone.getAnalogInput("front") == 15 do
								print("Ship currently docked..")
								sleep(0.5)
							end
							break
						end
					end
					print("Ship undocked, waiting 5 seconds..")
					sleep(5)
					modem.transmit(raw.channel, arm_channel, "undocked")
					print("Returning back to idle position..")
					movement.calibrate(1, modem, arm_id)
				end
				docked = false
				busy = false
			end
		end
	end
end

-- If the arm was still docked when this computer started up,
-- go back to idle once the ship undocks.
local function waitForUndock()
	while true do
		if docked and not busy and redstone.getAnalogInput("front") < 15 then
			busy = true
			docked = false
			print("Ship undocked, waiting 5 seconds..")
			sleep(5)
			print("Returning back to idle position..")
			movement.calibrate(1, modem, arm_id)
			busy = false
		end
		sleep(0.5)
	end
end

parallel.waitForAll(heartbeat, dock, waitForUndock)
