--------------------------------------------------------------------------------
-- nugsSuite
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsSuite  -  Serialize.lua
-- Turning a settings table into a string somebody can paste to a guildmate, and
-- back again.
--
-- The important decision in this file is that the reader is a hand-written parser
-- and NOT loadstring. An import string arrives from another player, and running it
-- as Lua would hand that player arbitrary code execution inside the client. The
-- parser below accepts exactly what the writer above it emits - nil, booleans,
-- numbers, quoted strings and tables of those - and rejects everything else, so a
-- hostile string can at worst fail to load.
--
-- The wire format is:  nugs1!<checksum>!<base64 of the serialized table>
-- Base64 so the payload survives a copy-paste through any edit box without
-- newlines or quotes mangling it, and a checksum so a truncated paste is caught
-- before it is merged into anybody's settings rather than after.
--
-- No compression. It was considered and dropped: profiles are exported as a diff
-- against each addon's defaults (see Profiles.lua), which cuts far more than any
-- compressor would, and a hand-rolled LZW is a lot of risk to carry for a string
-- that is already short enough to paste.
--------------------------------------------------------------------------------
local ADDON_NAME, NSU = ...

local S = {}
NSU.Serialize = S

local FORMAT_TAG = "nugs1"
local MAX_INPUT  = 200000   -- refuse absurd pastes before doing any work
local MAX_DEPTH  = 32       -- both writer and reader, so neither can blow the stack

--------------------------------------------------------------------------------
-- Writer
--------------------------------------------------------------------------------
local function EscapeString(s)
    local out = s:gsub("[%z\1-\31\\\"\127-\255]", function(c)
        if c == "\\" then return "\\\\" end
        if c == "\"" then return "\\\"" end
        -- %03.0f rather than %03d. This client's Lua has no integer type at all,
        -- and a stricter one refuses to format a float with %d - the float
        -- conversion is the one spelling that means the same thing in both.
        return string.format("\\%03.0f", c:byte())
    end)
    return out
end

local IDENT = "^[%a_][%w_]*$"

local function Write(value, out, depth)
    if depth > MAX_DEPTH then error("table nested too deeply to export") end
    local t = type(value)

    if value == nil then
        out[#out + 1] = "nil"
    elseif t == "boolean" then
        out[#out + 1] = value and "true" or "false"
    elseif t == "number" then
        -- %.14g keeps every value these addons store (colours, scales, sizes)
        -- round-tripping exactly, without printing 17 digits of float noise.
        if value ~= value or value == math.huge or value == -math.huge then
            error("cannot export a non-finite number")
        end
        out[#out + 1] = string.format("%.14g", value)
    elseif t == "string" then
        out[#out + 1] = "\"" .. EscapeString(value) .. "\""
    elseif t == "table" then
        out[#out + 1] = "{"
        local first = true
        -- Array part positionally, so lists of colours do not pay for their keys.
        local n = #value
        for i = 1, n do
            if not first then out[#out + 1] = "," end
            Write(value[i], out, depth + 1)
            first = false
        end
        -- Then everything else, sorted, so the same settings always produce the
        -- same string and two exports can be compared by eye.
        local keys = {}
        for k in pairs(value) do
            local skip = (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k))
            if not skip then
                if type(k) ~= "string" and type(k) ~= "number" then
                    error("cannot export a table key of type " .. type(k))
                end
                keys[#keys + 1] = k
            end
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return tostring(a) < tostring(b) end
            return type(a) == "number"
        end)
        for _, k in ipairs(keys) do
            if not first then out[#out + 1] = "," end
            if type(k) == "string" and k:match(IDENT) then
                out[#out + 1] = k .. "="
            else
                out[#out + 1] = "["
                Write(k, out, depth + 1)
                out[#out + 1] = "]="
            end
            Write(value[k], out, depth + 1)
            first = false
        end
        out[#out + 1] = "}"
    else
        error("cannot export a value of type " .. t)
    end
end

--------------------------------------------------------------------------------
-- Reader
--------------------------------------------------------------------------------
local Reader = {}
Reader.__index = Reader

local function NewReader(s)
    return setmetatable({ s = s, pos = 1, len = #s }, Reader)
end

function Reader:Fail(what)
    error("malformed profile string at character " .. self.pos .. " (expected " .. what .. ")", 0)
end

function Reader:Peek()
    if self.pos > self.len then return nil end
    return self.s:sub(self.pos, self.pos)
end

function Reader:Take(c)
    if self:Peek() ~= c then self:Fail("'" .. c .. "'") end
    self.pos = self.pos + 1
end

function Reader:ReadString()
    self:Take("\"")
    local buf = {}
    while true do
        local c = self:Peek()
        if c == nil then self:Fail("closing quote") end
        self.pos = self.pos + 1
        if c == "\"" then break end
        if c == "\\" then
            local e = self:Peek()
            if e == nil then self:Fail("escape sequence") end
            if e == "\\" or e == "\"" then
                buf[#buf + 1] = e
                self.pos = self.pos + 1
            else
                local digits = self.s:sub(self.pos, self.pos + 2)
                local n = digits:match("^(%d%d%d)$")
                if not n then self:Fail("a three digit escape") end
                n = tonumber(n)
                if n > 255 then self:Fail("a byte value") end
                buf[#buf + 1] = string.char(n)
                self.pos = self.pos + 3
            end
        else
            buf[#buf + 1] = c
        end
    end
    return table.concat(buf)
end

function Reader:ReadNumber()
    local _, stop, text = self.s:find("^(%-?%d+%.?%d*[eE]?[%+%-]?%d*)", self.pos)
    if not text then self:Fail("a number") end
    local n = tonumber(text)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then self:Fail("a finite number") end
    self.pos = stop + 1
    return n
end

function Reader:ReadValue(depth)
    if depth > MAX_DEPTH then self:Fail("a shallower table") end
    local c = self:Peek()
    if c == nil then self:Fail("a value") end

    if c == "\"" then
        return self:ReadString()
    elseif c == "{" then
        return self:ReadTable(depth)
    elseif c == "-" or c:match("%d") then
        return self:ReadNumber()
    elseif self.s:sub(self.pos, self.pos + 3) == "true" then
        self.pos = self.pos + 4
        return true
    elseif self.s:sub(self.pos, self.pos + 4) == "false" then
        self.pos = self.pos + 5
        return false
    elseif self.s:sub(self.pos, self.pos + 2) == "nil" then
        self.pos = self.pos + 3
        return nil
    end
    self:Fail("a value")
end

function Reader:ReadTable(depth)
    self:Take("{")
    local t = {}
    local arrayIndex = 0
    if self:Peek() == "}" then
        self.pos = self.pos + 1
        return t
    end
    while true do
        local c = self:Peek()
        if c == nil then self:Fail("closing brace") end

        local key
        if c == "[" then
            self.pos = self.pos + 1
            key = self:ReadValue(depth + 1)
            if key == nil then self:Fail("a key") end
            self:Take("]")
            self:Take("=")
        else
            -- A bare identifier followed by '=' is a key; anything else is a
            -- positional array entry.
            local _, stop, ident = self.s:find("^([%a_][%w_]*)", self.pos)
            if ident and self.s:sub(stop + 1, stop + 1) == "="
               and ident ~= "true" and ident ~= "false" and ident ~= "nil" then
                key = ident
                self.pos = stop + 2
            end
        end

        local value = self:ReadValue(depth + 1)
        if key ~= nil then
            t[key] = value
        else
            arrayIndex = arrayIndex + 1
            t[arrayIndex] = value
        end

        local n = self:Peek()
        if n == "," then
            self.pos = self.pos + 1
        elseif n == "}" then
            self.pos = self.pos + 1
            return t
        else
            self:Fail("',' or '}'")
        end
    end
end

--------------------------------------------------------------------------------
-- Base64
--------------------------------------------------------------------------------
-- Done with arithmetic rather than the bit library so this file has no dependency
-- on anything the client might rename between expansions.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64 do B64_INDEX[B64:sub(i, i)] = i - 1 end

local function Base64Encode(data)
    local out = {}
    local len = #data
    local i = 1
    while i + 2 <= len do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + b * 256 + c
        out[#out + 1] = B64:sub(math.floor(n / 262144) + 1, math.floor(n / 262144) + 1)
        out[#out + 1] = B64:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        out[#out + 1] = B64:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
        out[#out + 1] = B64:sub(n % 64 + 1, n % 64 + 1)
        i = i + 3
    end
    local remaining = len - i + 1
    if remaining == 1 then
        local a = data:byte(i)
        local n = a * 16
        out[#out + 1] = B64:sub(math.floor(n / 64) + 1, math.floor(n / 64) + 1)
        out[#out + 1] = B64:sub(n % 64 + 1, n % 64 + 1)
        out[#out + 1] = "=="
    elseif remaining == 2 then
        local a, b = data:byte(i, i + 1)
        local n = (a * 256 + b) * 4
        out[#out + 1] = B64:sub(math.floor(n / 4096) + 1, math.floor(n / 4096) + 1)
        out[#out + 1] = B64:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
        out[#out + 1] = B64:sub(n % 64 + 1, n % 64 + 1)
        out[#out + 1] = "="
    end
    return table.concat(out)
end

local function Base64Decode(text)
    text = text:gsub("%s", "")
    local padding = 0
    text = text:gsub("=+$", function(p) padding = #p return "" end)
    if padding > 2 then error("malformed profile string (bad padding)", 0) end

    local out = {}
    local acc, bits = 0, 0
    for i = 1, #text do
        local v = B64_INDEX[text:sub(i, i)]
        if v == nil then error("malformed profile string (unexpected character)", 0) end
        acc = acc * 64 + v
        bits = bits + 6
        if bits >= 8 then
            bits = bits - 8
            local divisor = 2 ^ bits
            local byte = math.floor(acc / divisor)
            acc = acc - byte * divisor
            out[#out + 1] = string.char(byte)
        end
    end
    return table.concat(out)
end

--------------------------------------------------------------------------------
-- Checksum
--------------------------------------------------------------------------------
-- A djb2 variant kept under 2^53 at every step so it stays exact in a double and
-- needs no bit library. This guards against a truncated or edited paste, not
-- against a determined forger - the parser is what makes a hostile string safe.
local function Checksum(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 4294967291
    end
    -- Printed as decimal through the float conversion, for the same portability
    -- reason as the escape above: %x demands an integer type this Lua does not have.
    return string.format("%.0f", h)
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------
function S.Encode(tbl)
    local out = {}
    local ok, err = pcall(Write, tbl, out, 1)
    if not ok then return nil, tostring(err) end
    local body = table.concat(out)
    return FORMAT_TAG .. "!" .. Checksum(body) .. "!" .. Base64Encode(body)
end

function S.Decode(text)
    if type(text) ~= "string" then return nil, "nothing to import" end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil, "nothing to import" end
    if #text > MAX_INPUT then return nil, "that string is too long to be a nugs profile" end

    local tag, sum, payload = text:match("^(%w+)!(%d+)!(.+)$")
    if not tag then
        return nil, "that does not look like a nugs profile string"
    end
    if tag ~= FORMAT_TAG then
        return nil, "that profile was made by a different version of nugsSuite (" .. tag .. ")"
    end

    local ok, body = pcall(Base64Decode, payload)
    if not ok then return nil, tostring(body) end

    if Checksum(body) ~= sum then
        return nil, "that profile string is damaged or incomplete - copy the whole thing and try again"
    end

    local reader = NewReader(body)
    local parsed
    ok, parsed = pcall(function()
        local v = reader:ReadValue(1)
        -- Trailing junk means the string was tampered with, not merely truncated.
        if reader.pos <= reader.len then reader:Fail("end of data") end
        return v
    end)
    if not ok then return nil, tostring(parsed) end
    if type(parsed) ~= "table" then return nil, "that profile string does not contain any settings" end
    return parsed
end
