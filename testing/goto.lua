package.path = package.path .. ";/?.lua"
local channels = require("protocols.channels")
local network = require("protocols.network")
local calculate = require("protocols.calculate")
local args = { ... }

local arm_id = os.getComputerID()
local arm_channel = channels.ARM_BASE + arm_id
local ch = {
	ring = channels.BEARING_BASE + arm_id * 5 + channels.BEARING_RING_OFFSET,
	limb1 = channels.BEARING_BASE + arm_id * 5 + channels.BEARING_LIMB1_OFFSET,
	limb2 = channels.BEARING_BASE + arm_id * 5 + channels.BEARING_LIMB2_OFFSET,
	dock = channels.BEARING_BASE + arm_id * 5 + channels.BEARING_DOCK_OFFSET,
	ack = channels.BEARING_BASE + arm_id * 5 + channels.BEARING_ACK_OFFSET,
}

local modem = peripheral.find("modem") or error("No modem", 0)
modem.open(arm_channel)
modem.open(ch.ack)

-- TODO: Fully implement controller
-- TODO: Initial angle for manipulator when idle, implement system
-- to change angles when already at a select location at calculate.
-- Maybe use constant values that change?

local raw = network.poll(arm_channel, 1)

print("Found ship.. ")
local data = calculate.angles(calculate.process(raw))

if not data.possible then
	print("! Ship cannot be safely docked, please align dock to the arm's center !")
	modem.transmit(raw.channel, arm_channel, false)
	goto skip
end

modem.transmit(raw.channel, arm_channel, true)

print("Rotating ring bearing..")
modem.transmit(ch.ring, ch.ack, data.center_pivot)
network.poll(ch.ack, 1)

print("Rotating limb 2 and dock bearing..")
modem.transmit(ch.limb2, ch.ack, data.limb2_angle)

modem.transmit(ch.dock, ch.ack, data.dock_pivot)

print("Rotating limb 1 bearing..")
modem.transmit(ch.limb1, ch.ack, data.limb1_angle)

-- Go back if "b'"
if args[1] == "b" then
	for _, bearing in pairs(data) do
		if type(bearing) ~= "boolean" then
			bearing.dir = -bearing.dir
		end
	end

	print("Going back to resting position..")

	print("Rotating limb 1 bearing..")
	modem.transmit(ch.limb1, ch.ack, data.limb1_angle)
	print("Rotating limb 2 and dock bearing..")
	modem.transmit(ch.limb2, ch.ack, data.limb2_angle)
	modem.transmit(ch.dock, ch.ack, data.dock_pivot)
	network.poll(ch.ack, 1)

	-- Waits until every bearing has moved
	print("Rotating ring bearing..")
	modem.transmit(ch.ring, ch.ack, data.center_pivot)
	network.poll(ch.ack, 1)
end
::skip::
print("Waiting..")
