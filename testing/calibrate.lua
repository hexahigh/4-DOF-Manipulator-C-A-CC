package.path = package.path .. ";/?.lua"
local channels = require("protocols.channels")
local network = require("protocols.network")
local calculate = require("protocols.calculate")
local geometry = require("protocols.geometry")
local args = { ... }

local arm_id = os.getComputerID()
local ch = {
	ring = channels.BEARING_BASE + arm_id * 5 + channels.BEARING_RING_OFFSET,
	limb1 = channels.BEARING_BASE + arm_id * 5 + channels.BEARING_LIMB1_OFFSET,
	limb2 = channels.BEARING_BASE + arm_id * 5 + channels.BEARING_LIMB2_OFFSET,
	dock = channels.BEARING_BASE + arm_id * 5 + channels.BEARING_DOCK_OFFSET,
	ack = channels.BEARING_BASE + arm_id * 5 + channels.BEARING_ACK_OFFSET,
}

local modem = peripheral.find("modem") or error("No modem", 0)
modem.open(ch.ack)

local degrees = {}
-- Go to base position (0 degrees)
if type(args[1]) == "nil" then
	degrees[1], degrees[2], degrees[3] = 0, 0, 0
-- Go to neutral position
elseif args[1] == "n" then
	degrees[1], degrees[2], degrees[3] = math.deg(geometry.LIMB_1), math.deg(geometry.LIMB_2), 0
end

print("Rotating limb 1 bearing..")
modem.transmit(ch.limb1, ch.ack, degrees[1])

print("Rotating limb 2 bearing..")
modem.transmit(ch.limb2, ch.ack, degrees[2])

print("Rotating dock bearing..")
modem.transmit(ch.dock, ch.ack, degrees[3])

-- Waits until everything has moved
print("Rotating ring bearing..")
modem.transmit(ch.ring, ch.ack, degrees[3])
network.poll(ch.ack, 1)
