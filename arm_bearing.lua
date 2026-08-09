-- NOTE: As of typing this wired modems cannot be connected to vertical bearings for whatever reason
package.path = package.path .. ";/?.lua"

-- This is used to control the rotation of the ring, limb 1 and limb 2 bearings.
local channels = require("protocols.channels")
local network = require("protocols.network")
local calculate = require("protocols.calculate")
local args = { ... }

local bearing_type = tonumber(args[1])
if not bearing_type or bearing_type < 1 or bearing_type > 4 then
	error("Usage: arm_bearing <1-4>\n1=ring 2=limb1 3=limb2 4=dock", 0)
end
local bearing_offset = bearing_type - 1

local bearing_names = { "RING BEARING", "LIMB 1", "LIMB 2", "LIMB DOCK BEARING" }
print("COMPUTER: " .. bearing_names[bearing_type])

local modem = peripheral.wrap("left") or error("No modem", 0)

-- Discover the arm controller this bearing belongs to by listening
-- for heartbeats and picking the closest one. The bearing is
-- physically mounted on the arm, so its own controller is nearest.
modem.open(channels.ARM_HEARTBEAT)
local arm_id
print("Discovering arm controller...")
while not arm_id do
	local timer = os.startTimer(5)
	local closest_dist
	while true do
		local event, _, channel, _, data, dist = os.pullEvent()
		if event == "modem_message" and channel == channels.ARM_HEARTBEAT
			and type(data) == "table" and data.id then
			if closest_dist == nil or (dist and dist < closest_dist) then
				closest_dist = dist
				arm_id = data.id
			end
		elseif event == "timer" then
			break
		end
	end
	if not arm_id then
		print("No arm controller found, retrying...")
		sleep(3)
	end
end
print(string.format("Found arm controller %d (%d blocks away)", arm_id, closest_dist))
modem.close(channels.ARM_HEARTBEAT)

if arm_id > 9000 then
	error("Arm controller ID " .. arm_id .. " is too large for the channel scheme (max 9000)", 0)
end

local localChannel = channels.BEARING_BASE + arm_id * 5 + bearing_offset
local ackChannel = channels.BEARING_BASE + arm_id * 5 + channels.BEARING_ACK_OFFSET

modem.open(localChannel)

for _, name in ipairs(peripheral.getNames()) do
	print(string.format("Found peripheral %s to the %s..", peripheral.getType(name), name))
end

local gearshift = peripheral.find("Create_SequencedGearshift")

local data

while true do
	data = network.poll(localChannel, 1)

	if type(data) == "number" then
		local bearing = peripheral.find("swivel_bearing")
		-- Go to a specific position relative to 0 degrees
		local pos = calculate.deg_direction(-math.rad(data - bearing.getTargetAngle()))
		gearshift.rotate(pos.angle, pos.dir)

		while gearshift.isRunning() do
			sleep(0.1)
		end

		modem.transmit(ackChannel, localChannel, true)
	else
		gearshift.rotate(data.angle, data.dir)

		while gearshift.isRunning() do
			sleep(0.1)
		end

		modem.transmit(ackChannel, localChannel, true)
	end
end
