-- Axia Livewire R/UDP Dissector
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
rudp_protocol = Proto("LW-RUDP", "Livewire R/UDP Protocol")

-- Create fields
rudp_header = ProtoField.uint32("rudp.header", "Header", base.HEX)
rudp_sequence = ProtoField.uint32("rudp.sequence", "Sequence Number", base.DEC)

rudp_protocol.fields = {
    rudp_header,
    rudp_sequence
}

-- Get fields
local udp_dst_port = Field.new("udp.dstport")

-- Add child protocol dissectors
local child_dissectors = DissectorTable.new("lw-rudp.port")

-- Decode functions
function decode_header(buffer, tree)
    tree:add(rudp_header, buffer(0, 4))
    tree:add(rudp_sequence, buffer(4, 4))
end

-- Protocol dissector function
function rudp_protocol.dissector(buffer, pinfo, tree)
    local length = buffer:len()
    if length == 0 then
        return
    end

    pinfo.cols.protocol = rudp_protocol.name

    local subtree = tree:add(rudp_protocol, buffer(0, 16), "Livewire R/UDP Protocol")

    decode_header(buffer, subtree)

    local dissector = child_dissectors:get_dissector(udp_dst_port().value)
    if dissector ~= nil then
        dissector:call(buffer(16):tvb(), pinfo, tree)
    end
end

-- Set dissector
local udp_port = DissectorTable.get("udp.port")

udp_port:add(2055, rudp_protocol)
udp_port:add(2060, rudp_protocol)
udp_port:add(4000, rudp_protocol)
udp_port:add(4001, rudp_protocol)
