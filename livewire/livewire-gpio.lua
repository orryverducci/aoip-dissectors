-- Axia Livewire CMsg2 Dissector
-- Developed by Orry Verducci (orry@orryverducci.co.uk)
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
-- documentation files (the “Software”), to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
-- and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in all copies or substantial portions
-- of the Software.
-- 
-- THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
-- TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
-- THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
-- CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

-- Create protocol
gpio_protocol = Proto("LW-GPIO", "Livewire GPIO")

-- Create fields
gpio_message_type = ProtoField.string("gpio.message_type", "Message Type", base.ASCII)
gpio_count = ProtoField.uint16("gpio.count", "Item Count", base.DEC)
gpio_lw_channel = ProtoField.uint16("gpio.lw_channel", "Livewire Channel", base.DEC)
gpio_pin_type = ProtoField.string("gpio.pin_type", "Pin Type", base.ASCII)
gpio_pin_number = ProtoField.uint8("gpio.pin_number", "Pin Number", base.DEC)
gpio_state = ProtoField.string("gpio.state", "State", base.ASCII)
gpio_pulse_duration = ProtoField.uint8("gpio.pulse_duration", "Pulse Duration", base.DEC)

gpio_protocol.fields = {
    gpio_message_type,
    gpio_count,
    gpio_lw_channel,
    gpio_pin_type,
    gpio_pin_number,
    gpio_state,
    gpio_pulse_duration
}

-- Helper functions
function get_message_type(msg_id)
    local type = "Unknown"

    if msg_id == "WRNI" then
        type = "Write GPIO value"
    elseif msg_id == "READ" then
        type = "Request for GPIO value"
    elseif msg_id == "INDI" then
        type = "GPIO value"
    end
  
    return type
end

function get_ip_from_lw_channel(channel)
	return "239.192." .. math.floor(channel / 256) .. "." .. channel % 256
end

function get_pin_type(circuit)
	local result

	circuit = bit.band(circuit, 0x0F)  -- bitwise AND the circuit number because Fusion is inserting an F at the MSB

	if circuit < 9 then
        result = "GPO"
	else
        result = "GPI"
	end

	return result
end

function get_pin_number(circuit)
	local result

	circuit = bit.band(circuit, 0x0F)  -- bitwise AND the circuit number because Fusion is inserting an F at the MSB

	if circuit < 9 then
        result = 9 - circuit
	else
        result = 14 - circuit
	end

	return result
end

function get_state(value)
    local state = "Unknown"

    if value > 192 then
        state = "Pulse Low"
    elseif value == 192 then
        state = "Low"
    elseif value > 128 then
        state = "Pulse High"
    elseif value == 128 then
        state = "High"
    elseif value < 96 and value > 64 then
        state = "Pulse Low"
    elseif value == 64 then
        state = "Low"
    elseif value < 32 and value > 1 then
        state = "Pulse High"
    elseif value == 1 then      -- Special case due to GPI devices (LW library) not following protocol
        state = "Low"
    elseif value == 0 then
        state = "High" 
    end
  
    return state
end

function get_pulse_duration(value)
    local duration = 0

    if value > 192 then
        duration = (value - 192) * 10
    elseif value < 192 and value > 128 then 
        duration = (value - 128) * 10
    elseif value < 96 and value > 64 then
        duration = (value - 64) * 250
    elseif (value < 32 and value > 1) then
        duration = value * 250
    end
  
    return duration
end

-- Protocol dissector function
function gpio_protocol.dissector(buffer, pinfo, tree)
    pinfo.cols.protocol = gpio_protocol.name

    local subtree = tree:add(gpio_protocol, buffer(), "Livewire GPIO")

    subtree:add(gpio_message_type, cmsg2_data["id"], get_message_type(cmsg2_data["id"]:string()))

    -- Iterate over each item and add it to the tree and summary
    local summary = cmsg2_data["id"]:string()
    local previous_lw_channel = nil

    for i, message in ipairs(cmsg2_data["messages"]) do
        local lw_channel = message["key"](1, 2)
        local pin = message["key"](3, 1)
        local value = message["value"](0, 1)

        if pin:uint() == 0xFF then      -- Auxillary data packets, which are not yet supported
            goto continue
        end

        if lw_channel:uint() == 65535 and previous_lw_channel ~= nil then     -- If 0xFFFF reuse the previous Livewire channel
            lw_channel = previous_lw_channel
        elseif lw_channel:uint() ~= 65535 then
            previous_lw_channel = lw_channel
        end

        local pin_type = get_pin_type(pin:uint())
        local pin_number = get_pin_number(pin:uint())
        local state = get_state(value:uint())
        local pulse_duration = get_pulse_duration(value:uint())

        local msg_tree = subtree:add(gpio_protocol, message["full"], "GPIO Message " .. tostring(i))
        msg_tree:add(gpio_lw_channel, lw_channel):append_text(" (" .. get_ip_from_lw_channel(lw_channel:uint()) .. ")")
        msg_tree:add(gpio_pin_type, pin, pin_type)
        msg_tree:add(gpio_pin_number, pin, pin_number)

        summary = summary .. " - " .. lw_channel:uint() .. " " .. pin_type .. " pin " .. pin_number

        if (cmsg2_data["id"]:string()) ~= "READ" then
            msg_tree:add(gpio_state, value, state)
            summary = summary .. " " .. state

            if pulse_duration ~= 0 then
                msg_tree:add(gpio_pulse_duration, value, pulse_duration):append_text("ms")
                summary = summary .. " " .. pulse_duration .. "ms"
            end
        end

        ::continue::
    end

    -- Set the packet info to the summary
    pinfo.cols.info = summary
end

-- Set dissector
function gpio_protocol.init()
    local cmsg2_port = DissectorTable.get("lw-cmsg2.port")

    cmsg2_port:add(2055, gpio_protocol)
    cmsg2_port:add(2060, gpio_protocol)
end
