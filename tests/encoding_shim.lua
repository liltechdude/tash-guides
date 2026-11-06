-- Offline stand-in for the client's C_EncodingUtil (DecodeBase64, DecompressString,
-- DeserializeCBOR) so QuestieDB's baked metadata can be decoded under LuaJIT.

local ffi = require("ffi")
local bit = require("bit")

ffi.cdef[[
typedef struct z_stream_s {
  const unsigned char *next_in; unsigned int avail_in; unsigned long total_in;
  unsigned char *next_out; unsigned int avail_out; unsigned long total_out;
  const char *msg; void *state; void *zalloc; void *zfree; void *opaque;
  int data_type; unsigned long adler; unsigned long reserved;
} z_stream;
const char *zlibVersion(void);
int inflateInit2_(z_stream *strm, int windowBits, const char *version, int stream_size);
int inflate(z_stream *strm, int flush);
int inflateEnd(z_stream *strm);
]]
local z = ffi.load("z")

local function inflate(data, windowBits)
    local strm = ffi.new("z_stream")
    if z.inflateInit2_(strm, windowBits, z.zlibVersion(), ffi.sizeof("z_stream")) ~= 0 then return nil end
    local inbuf = ffi.new("unsigned char[?]", #data)
    ffi.copy(inbuf, data, #data)
    strm.next_in, strm.avail_in = inbuf, #data
    local out, chunk = {}, 65536
    local buf = ffi.new("unsigned char[?]", chunk)
    while true do
        strm.next_out, strm.avail_out = buf, chunk
        local rc = z.inflate(strm, 0)
        out[#out + 1] = ffi.string(buf, chunk - strm.avail_out)
        if rc == 1 then break end           -- Z_STREAM_END
        if rc ~= 0 then z.inflateEnd(strm) return nil end
        if strm.avail_in == 0 and strm.avail_out ~= 0 then break end
    end
    z.inflateEnd(strm)
    return table.concat(out)
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local dec = {}
for i = 1, 64 do dec[B64:byte(i)] = i - 1 end
dec[("-"):byte()] = 62
dec[("_"):byte()] = 63

local function decodeBase64(s)
    local out, acc, n = {}, 0, 0
    for i = 1, #s do
        local v = dec[s:byte(i)]
        if v then
            acc = bit.bor(bit.lshift(acc, 6), v)
            n = n + 6
            if n >= 8 then
                n = n - 8
                out[#out + 1] = string.char(bit.band(bit.rshift(acc, n), 0xFF))
            end
        end
    end
    return table.concat(out)
end

-- Minimal CBOR decoder (RFC 8949 major types 0-7; maps -> Lua tables).
local function cbor(s)
    local pos = 1
    local function u8() local b = s:byte(pos); pos = pos + 1; return b end
    local function uint(n)
        local v = 0
        for _ = 1, n do v = v * 256 + u8() end
        return v
    end
    local function arg(info)
        if info < 24 then return info end
        if info == 24 then return uint(1) end
        if info == 25 then return uint(2) end
        if info == 26 then return uint(4) end
        if info == 27 then return uint(8) end
        return nil -- indefinite
    end
    local item
    local BREAK = {}
    function item()
        local ib = u8()
        local major, info = bit.rshift(ib, 5), bit.band(ib, 31)
        if major == 0 then return arg(info)
        elseif major == 1 then return -1 - arg(info)
        elseif major == 2 or major == 3 then
            local n = arg(info)
            if n == nil then
                local parts = {}
                while true do
                    local p = item()
                    if p == BREAK then break end
                    parts[#parts + 1] = p
                end
                return table.concat(parts)
            end
            local str = s:sub(pos, pos + n - 1)
            pos = pos + n
            return str
        elseif major == 4 then
            local n, t = arg(info), {}
            if n == nil then
                while true do local v = item(); if v == BREAK then break end t[#t + 1] = v end
            else
                for i = 1, n do t[i] = item() end
            end
            return t
        elseif major == 5 then
            local n, t = arg(info), {}
            if n == nil then
                while true do
                    local k = item(); if k == BREAK then break end
                    t[k] = item()
                end
            else
                for _ = 1, n do local k = item(); t[k] = item() end
            end
            return t
        elseif major == 6 then
            arg(info)
            return item()
        else
            if info == 20 then return false
            elseif info == 21 then return true
            elseif info == 22 or info == 23 then return nil
            elseif info == 25 then
                local h = uint(2)
                local sign = bit.band(h, 0x8000) ~= 0 and -1 or 1
                local e, m = bit.band(bit.rshift(h, 10), 0x1f), bit.band(h, 0x3ff)
                if e == 0 then return sign * m * 2 ^ -24 end
                if e == 31 then return m == 0 and sign * math.huge or 0 / 0 end
                return sign * (1 + m / 1024) * 2 ^ (e - 15)
            elseif info == 26 then
                local b = ffi.new("uint8_t[4]")
                for i = 3, 0, -1 do b[i] = u8() end
                return ffi.cast("float*", b)[0]
            elseif info == 27 then
                local b = ffi.new("uint8_t[8]")
                for i = 7, 0, -1 do b[i] = u8() end
                return ffi.cast("double*", b)[0]
            elseif info == 31 then return BREAK
            end
            return nil
        end
    end
    return item()
end

_G.C_EncodingUtil = {
    DecodeBase64 = decodeBase64,
    DecompressString = function(data)
        return inflate(data, 15 + 32) or inflate(data, -15)
    end,
    DeserializeCBOR = cbor,
}
_G.Enum = _G.Enum or {}
_G.Enum.CompressionMethod = _G.Enum.CompressionMethod or { Deflate = 0, Zlib = 1, Gzip = 2 }
