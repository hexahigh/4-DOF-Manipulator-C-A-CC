-- Used for controller movement
package.path = package.path .. ";/?.lua"
local movement = {}
local channels = require("protocols.channels")
local geometry = require("protocols.geometry")
local network = require("protocols.network")

-- Returns channels for the given arm_id.
local function bearingChannels(arm_id)
	local base = channels.BEARING_BASE + arm_id * 5
	return {
		ring = base + channels.BEARING_RING_OFFSET,
		limb1 = base + channels.BEARING_LIMB1_OFFSET,
		limb2 = base + channels.BEARING_LIMB2_OFFSET,
		dock = base + channels.BEARING_DOCK_OFFSET,
		ack = base + channels.BEARING_ACK_OFFSET,
	}
end

-- Makes the dock go back to either:
-- 0: Base position (0 Degrees)
-- 1: Idle position
function movement.calibrate(arg, modem, arm_id)
	local ch = bearingChannels(arm_id)
	local degrees = {}
	-- Go to base position (0 degrees)
	if type(arg) == 0 then
		degrees[1], degrees[2], degrees[3] = 0, 0, 0
	-- Go to neutral position
	elseif arg == 1 then
		degrees[1], degrees[2], degrees[3] = math.deg(geometry.LIMB_1), math.deg(geometry.LIMB_2), math.deg(geometry.INITIAL_ARM_ANGLE) - 90
	end
	print("Rotating limb 1 bearing..")
	modem.transmit(ch.limb1, ch.ack, degrees[1])

	print("Rotating limb 2 bearing..")
	modem.transmit(ch.limb2, ch.ack, degrees[2])

	print("Rotating dock bearing..")
	modem.transmit(ch.dock, ch.ack, 0)

	-- Waits until everything has moved
	print("Rotating ring bearing..")
	modem.transmit(ch.ring, ch.ack, degrees[3])
	network.poll(ch.ack, 1)
end

-- Goes to where the ship is. Takes processed data as argument.
-- Returns boolean on whether going to the ship is safe or not
-- (If false, doesn't go to ship)
-- Replies to the requesting ship on its own channel.
function movement.goto(data, modem, ship_channel, arm_channel, arm_id)
	local ch = bearingChannels(arm_id)
	if not data.possible then
		print("! Ship cannot be safely docked, please align dock or go closer to the arm's center !")
		modem.transmit(ship_channel, arm_channel, false)
		return false
	end
	print("Ship can be docked..")
	modem.transmit(ship_channel, arm_channel, true)
	print("Rotating ring bearing..")
	modem.transmit(ch.ring, ch.ack, data.center_pivot)
	network.poll(ch.ack, 1)
	print("Rotating limb 2 and dock bearing..")
	modem.transmit(ch.limb2, ch.ack, data.limb2_angle)
	network.poll(ch.ack, 1)
	modem.transmit(ch.dock, ch.ack, data.dock_pivot)
	print("Rotating limb 1 bearing..")
	modem.transmit(ch.limb1, ch.ack, data.limb1_angle)
	return true
end

return movement
