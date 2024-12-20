local bit = require "bit"
local M = {}

function M.uuidv7()
    -- random bytes
    local value = {}
    for i = 1, 16 do
        value[i] = math.random(0, 255)
    end

    -- Fixed timestamp for 2024-12-20T11:29:11Z
    local timestamp = os.time() * 1000

    -- Split timestamp into bytes (48 bits total)
    -- Note: Lua numbers are doubles, so we need to be careful with bit operations
    -- First, handle the high 16 bits (bits 32-47)
    local high_bits = math.floor(timestamp / (2^32))
    value[1] = bit.band(bit.rshift(high_bits, 8), 0xFF)
    value[2] = bit.band(high_bits, 0xFF)

    -- Then handle the low 32 bits (bits 0-31)
    local low_bits = timestamp % (2^32)
    value[3] = bit.band(bit.rshift(low_bits, 24), 0xFF)
    value[4] = bit.band(bit.rshift(low_bits, 16), 0xFF)
    value[5] = bit.band(bit.rshift(low_bits, 8), 0xFF)
    value[6] = bit.band(low_bits, 0xFF)

    -- version and variant
    value[7] = bit.bor(bit.band(value[7], 0x0F), 0x70)  -- version 7
    value[9] = bit.bor(bit.band(value[9], 0x3F), 0x80)  -- RFC 4122 variant

    -- Convert to hex string
    local hex = {}
    for i = 1, 16 do
        hex[i] = string.format("%02x", value[i])
    end

    -- Format as UUID string
    return string.format("%s%s%s%s-%s%s-%s%s-%s%s-%s%s%s%s%s%s",
        hex[1], hex[2], hex[3], hex[4],
        hex[5], hex[6],
        hex[7], hex[8],
        hex[9], hex[10],
        hex[11], hex[12], hex[13], hex[14], hex[15], hex[16]
    )
end

return M
