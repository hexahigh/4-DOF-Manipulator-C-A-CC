-- NOTE: As of typing this wired modems cannot be connected to vertical bearings for whatever reason
package.path = package.path .. ";/?.lua"

-- This is used to control the rotation of the ring, limb 1 and limb 2 bearings.
local channels = require("protocols.channels")
local network = require("protocols.network")
local calculate = require("protocols.calculate")
local args = { ... }

local bearing_type = tonumber(args[1])
if not bearing_type or bearing_type < 1 or bearing_type > 4 then
	error("Usage: arm_bearing <1-4> <arm_id>\n1=ring 2=limb1 3=limb2 4=dock", 0)
end
local bearing_offset = bearing_type - 1

local arm_id = tonumber(args[2])
if not arm_id or arm_id < 1 then
	error("Usage: arm_bearing <1-4> <arm_id>\nExpected a valid arm controller ID", 0)
end

local bearing_names = { "RING BEARING", "LIMB 1", "LIMB 2", "LIMB DOCK BEARING" }
print(string.format("COMPUTER: %s (arm %d)", bearing_names[bearing_type], arm_id))

local modem = peripheral.wrap("left") or error("No modem", 0)

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
		if data.angle ~= data.angle or data.dir == nil then
			print("Received invalid rotation, ignoring..")
		else
			gearshift.rotate(data.angle, data.dir)

			while gearshift.isRunning() do
				sleep(0.1)
			end

			modem.transmit(ackChannel, localChannel, true)
		end
	end
end
