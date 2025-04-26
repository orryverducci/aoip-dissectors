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
cmsg2_protocol = Proto("LW-CMSG2", "Livewire CMsg2 Protocol")

-- Create fields
cmsg2_message_id = ProtoField.string("cmsg2.message_id", "Message ID", base.ASCII)
cmsg2_description = ProtoField.string("cmsg2.message_description", "Message Description")
cmsg2_count = ProtoField.uint16("cmsg2.count", "Item Count", base.DEC)
cmsg2_key = ProtoField.uint32("cmsg2.key", "Key", base.HEX)
cmsg2_data_type = ProtoField.uint8("cmsg2.data_type", "Data Type", base.DEC)
cmsg2_message_size = ProtoField.uint16("cmsg2.size", "Message Size", base.DEC)
cmsg2_value_byte = ProtoField.uint8("cmsg2.value", "Value", base.DEC)
cmsg2_value_byte_array = ProtoField.bytes("cmsg2.value", "Value", base.SPACE)
cmsg2_value_int16 = ProtoField.uint16("cmsg2.value", "Value", base.DEC)
cmsg2_value_int32 = ProtoField.int32("cmsg2.value", "Value", base.DEC)
cmsg2_value_int64 = ProtoField.int64("cmsg2.value", "Value", base.DEC)
cmsg2_value_string = ProtoField.string("cmsg2.value", "Value", base.ASCII)
cmsg2_value_array_count = ProtoField.uint16("cmsg2.array_count", "Array Item Count", base.DEC)

cmsg2_protocol.fields = {
    cmsg2_message_id,
    cmsg2_description,
    cmsg2_count,
    cmsg2_key,
    cmsg2_data_type,
    cmsg2_message_size,
    cmsg2_value_byte,
    cmsg2_value_byte_array,
    cmsg2_value_int16,
    cmsg2_value_int32,
    cmsg2_value_int64,
    cmsg2_value_string,
    cmsg2_value_array_count
}

-- Get fields
local udp_dst_port = Field.new("udp.dstport")

-- Add child protocol dissectors
local child_dissectors = DissectorTable.new("lw-cmsg2.port")
cmsg2_data = {}

-- Decode functions
function decode_group(buffer, tree, data)
    local msg_id = buffer(0, 4)
    local msg_description = get_message_description(msg_id:string())
    tree:add(cmsg2_message_id, msg_id)
    tree:add(cmsg2_description, msg_id, msg_description)

    local count = buffer(4, 2)
    tree:add(cmsg2_count, count)

    data["id"] = msg_id
    data["messages"] = {}

    local buffer_position = 6;

    for i = 1, count:uint(), 1
    do
        data["messages"][i] = {}
        local message_data = data["messages"][i]

        local key = buffer(buffer_position, 4)
        local data_type = buffer(buffer_position + 4, 1)
        local data_type_description = get_data_type_description(data_type:uint())
        local data_length = decode_data_length(buffer(buffer_position + 5), data_type:uint())

        message_data["full"] = buffer(buffer_position, data_length + 5)
        message_data["key"] = key
        message_data["type"] = data_type

        local key_string = key:string()

        local subtree = tree:add(cmsg2_protocol, message_data["full"], "Message " .. tostring(i))
        if string.len(key_string) > 0 then
            subtree:add(cmsg2_key, key):append_text(" (" .. key_string .. ")")
        else
            subtree:add(cmsg2_key, key)
        end
        subtree:add(cmsg2_data_type, buffer(buffer_position + 4, 1)):append_text(" (" .. data_type_description .. ")")

        if data_length > 0 then
            decode_data(buffer(buffer_position + 5, data_length), data_type:uint(), subtree, message_data)
        end

        buffer_position = buffer_position + 5 + data_length
    end
end

function decode_data_length(buffer, data_type)
    local length = 0

    if data_type == 1 then
        length = 4
    elseif data_type == 2
        or data_type == 3
        or data_type == 6 then
        local count = buffer(0, 2):uint()
        length = 2 + count
    elseif data_type == 4 then
        local count = buffer(0, 2):uint()
        length = 2 + (count * 2)
    elseif data_type == 5 then
        local count = buffer(0, 2):uint()
        length = 2 + (count * 4)
    elseif data_type == 7 then
        length = 1
    elseif data_type == 8 then
        length = 2
    elseif data_type == 9 then
        length = 8
    end
  
    return length
end

function decode_data(buffer, data_type, tree, data)
    if data_type == 1 then
        decode_data_int32(buffer, tree, data)
    elseif data_type == 2 then
        decode_data_string(buffer, tree, data)
    elseif data_type == 3
        or data_type == 4
        or data_type == 5 then
        decode_data_byte_array(buffer, tree, data)
    elseif data_type == 6 then
        decode_nested(buffer, tree, data)
    elseif data_type == 7 then
        decode_data_byte(buffer, tree, data)
    elseif data_type == 8 then
        decode_data_int16(buffer, tree, data)
    elseif data_type == 9 then
        decode_data_int64(buffer, tree, data)
    end
end

function decode_data_byte(buffer, tree, data)
    data["value"] = buffer(0, 1)
    tree:add(cmsg2_value_byte, buffer(0, 1))
end

function decode_data_byte_array(buffer, tree, data)
    data["count"] = buffer(0, 2)
    data["value"] = buffer(2)
    tree:add(cmsg2_value_array_count, buffer(0, 2))
    tree:add(cmsg2_value_byte_array, buffer(2))
end

function decode_data_int16(buffer, tree, data)
    data["value"] = buffer(0, 2)
    tree:add(cmsg2_value_int16, buffer(0, 2))
end

function decode_data_int32(buffer, tree, data)
    data["value"] = buffer(0, 4)
    tree:add(cmsg2_value_int32, buffer(0, 4))
end

function decode_data_int64(buffer, tree, data)
    data["value"] = buffer(0, 8)
    tree:add(cmsg2_value_int64, buffer(0, 8))
end

function decode_data_string(buffer, tree, data)
    data["value"] = buffer(2)
    tree:add(cmsg2_value_string, buffer(2))
end

function decode_nested(buffer, tree, data)
    data["value"] = {}
    tree:add(cmsg2_message_size, buffer(0, 2))
    decode_group(buffer(2), tree, data["value"])
end

-- Helper functions
function get_message_description(msg_id)
    local description = "Unknown"

    if msg_id == "WRNI" then
        description = "Write value - returning the indication is not requested"
    elseif msg_id == "WRIN" then
        description = "Write value - returning the indication is requested"
    elseif msg_id == "READ" then
        description = "Request to read indication"
    elseif msg_id == "INDI" then
        description = "Indication"
    elseif msg_id == "STAT" then
        description = "Status"
    elseif msg_id == "NEST" then
        description = "Container for nested messages"
    end
  
    return description
end

function get_data_type_description(value)
    local data_type = "Unknown"

    if value == 0 then
        data_type = "None"
    elseif value == 1 then
        data_type = "32 bit integer"
    elseif value == 2 then
        data_type = "String"
    elseif value == 3 then
        data_type = "Byte array"
    elseif value == 4 then
        data_type = "Array of 2 byte words"
    elseif value == 5 then
        data_type = "Array of 4 byte words"
    elseif value == 6 then
        data_type = "Nested messages"
    elseif value == 7 then
        data_type = "Byte"
    elseif value == 8 then
        data_type = "16 bit unsigned integer"
    elseif value == 9 then
        data_type = "64 bit integer"
    end
  
    return data_type
end

-- Protocol dissector function
function cmsg2_protocol.dissector(buffer, pinfo, tree)
    local length = buffer:len()
    if length == 0 then
        return
    end

    pinfo.cols.protocol = cmsg2_protocol.name

    local subtree = tree:add(cmsg2_protocol, buffer(), "Livewire CMsg2 Protocol")

    decode_group(buffer, subtree, cmsg2_data)

    local dissector = child_dissectors:get_dissector(udp_dst_port().value)
    if dissector ~= nil then
        dissector:call(buffer():tvb(), pinfo, tree)
    end
end

-- Set dissector
function cmsg2_protocol.init()
    local rudp_port = DissectorTable.get("lw-rudp.port")

    rudp_port:add(2055, cmsg2_protocol)
    rudp_port:add(2060, cmsg2_protocol)
    rudp_port:add(4000, cmsg2_protocol)
    rudp_port:add(4001, cmsg2_protocol)
end
