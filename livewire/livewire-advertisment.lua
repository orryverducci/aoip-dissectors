-- Axia Livewire CMsg2 Dissector
-- Developed by Orry Verducci (orry@orryverducci.co.uk)
-- 
-- Based on research by Nick Prater (https://github.com/nick-prater/read_lw_sources)
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
advertisment_protocol = Proto("LW-ADVT", "Livewire Advertisment")

-- Create fields
advt_message_type = ProtoField.string("advt.message_type", "Message Type", base.ASCII)
advt_protocol_version = ProtoField.uint16("advt.proto_version", "Protocol Version", base.DEC)
advt_type = ProtoField.uint8("advt.type", "Advertisment Type", base.DEC)
advt_version = ProtoField.uint32("advt.version", "Advertisment Version", base.DEC)
advt_hardware_id = ProtoField.uint32("advt.hwid", "Hardware ID", base.DEC)
advt_ip_address = ProtoField.ipv4("advt.ip_address", "IP Address")
advt_udp_port = ProtoField.uint16("advt.udp_port", "Advertisment UDP Port", base.DEC)
advt_sources = ProtoField.uint16("advt.sources", "Number of Sources", base.DEC)
advt_device_name = ProtoField.string("advt.device_name", "Device Name", base.ASCII)
advt_source_ch = ProtoField.uint32("advt.source_ch", "Source Livewire Channel", base.DEC)
advt_source_sharable = ProtoField.bool("advt.source_sharable", "Sharable")
advt_source_multicast_ip = ProtoField.ipv4("advt.source_multicast_ip", "Multicast IP Address")
advt_source_backfeed_ip = ProtoField.ipv4("advt.source_backfeed_ip", "Backfeed Multicast IP Address")
advt_source_name = ProtoField.string("gpio.source_name", "Source Name", base.ASCII)


advertisment_protocol.fields = {
    advt_message_type,
    advt_protocol_version,
    advt_type,
    advt_version,
    advt_hardware_id,
    advt_ip_address,
    advt_udp_port,
    advt_sources,
    advt_device_name,
    advt_source_ch,
    advt_source_sharable,
    advt_source_multicast_ip,
    advt_source_backfeed_ip,
    advt_source_name
}

-- Helper functions
local function get_message_type(msg_id)
    local type = "Unknown"

    if msg_id == "NEST" then
        type = "Nested advertisment"
    elseif msg_id == "READ" then
        type = "Request for advertisment"
    end
  
    return type
end

local function get_advertisment_type(value)
    local type = "Unknown"

	if value == 1 then
        result = "Full advertisment"
    elseif value == 2 then
        result = "Short advertisment"
	end

	return result
end

local function get_ip_from_hw_id(hwid)
	return math.floor(hwid / 256) .. "." .. hwid % 256
end

local function decode_device_info(data, buffer, tree)
    local subtree = tree:add(advertisment_protocol, buffer, "Device Information")

    for i, message in ipairs(data["messages"]) do
        if message["key"]:string() == "ADVV" then
            subtree:add(advt_version, message["value"])
        elseif message["key"]:string() == "HWID" then
            subtree:add(advt_hardware_id, message["value"]):append_text(" (" .. get_ip_from_hw_id(message["value"]:uint()) .. ")")
        elseif message["key"]:string() == "INIP" then
            subtree:add(advt_ip_address, message["value"])
        elseif message["key"]:string() == "UDPC" then
            subtree:add(advt_udp_port, message["value"])
        elseif message["key"]:string() == "NUMS" then
            subtree:add(advt_sources, message["value"])
        elseif message["key"]:string() == "ATRN" then
            subtree:add(advt_device_name, message["value"])
        end
    end
end

local function decode_source_info(index, data, buffer, tree)
    local subtree = tree:add(advertisment_protocol, buffer, "Source " .. index)

    for i, message in ipairs(data["messages"]) do
        if message["key"]:string() == "PSID" then
            subtree:add(advt_source_ch, message["value"])
        elseif message["key"]:string() == "SHAB" then
            subtree:add(advt_source_sharable, message["value"])
        elseif message["key"]:string() == "FSID" then
            subtree:add(advt_source_multicast_ip, message["value"])
        elseif message["key"]:string() == "BSID" then
            subtree:add(advt_source_backfeed_ip, message["value"])
        elseif message["key"]:string() == "PSNM" then
            subtree:add(advt_source_name, message["value"])
        end
    end
end

-- Protocol dissector function
function advertisment_protocol.dissector(buffer, pinfo, tree)
    pinfo.cols.protocol = advertisment_protocol.name

    local subtree = tree:add(advertisment_protocol, buffer(), "Livewire Advertisment")

    subtree:add(advt_message_type, cmsg2_data["id"], get_message_type(cmsg2_data["id"]:string()))

    -- Iterate over each item
    for i, message in ipairs(cmsg2_data["messages"]) do
        if message["key"]:string() == "PVER" then
            subtree:add(advt_protocol_version, message["value"])
        elseif message["key"]:string() == "ADVT" then
            subtree:add(advt_type, message["value"]):append_text(" (" .. get_advertisment_type(message["value"]:uint()) .. ")")
        elseif message["key"]:string() == "TERM" then
            decode_device_info(message["value"], message["full"], subtree)
        elseif message["key"](0, 1):string() == "S" then
            decode_source_info(tonumber(message["key"](1):string()), message["value"], message["full"], subtree)
        end
    end
end

-- Set dissector
function advertisment_protocol.init()
    local cmsg2_port = DissectorTable.get("lw-cmsg2.port")

    cmsg2_port:add(4000, advertisment_protocol)
    cmsg2_port:add(4001, advertisment_protocol)
end
