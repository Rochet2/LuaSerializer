--[[
    Copyright (C) 2014-  Rochet2 <https://github.com/Rochet2>

    This program is free software you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program if not, write to the Free Software Foundation, Inc.,
    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
]]

--[[
Usage:
local serialized = LuaSerializer.serialize(55, "test", {1,2, y = 66}, nil, true, LuaSerializer.ToFunction('print("Hello")'))
print(LuaSerializer.deserialize(serialized))
]]

assert(_VERSION == 'Lua 5.1' or _VERSION == 'Lua 5.2', "LuaSerializer serializer is coded for lua 5.1 and 5.2")

-- LuaSerializer main table
local LuaSerializer = {}

-- Enables deserializing functions (uses loadstring or load)
local LuaSerializer_ENABLE_FUNCTIONS      = true

-- Enables LZW compression for the serialized data
local LuaSerializer_ENABLE_COMPRESSION    = true -- default true

-- Client must have same version (basically same LuaSerializer file)
LuaSerializer.Version = 0.75
-- ID characters for the serialization
local LuaSerializer_True            = 'T'
local LuaSerializer_False           = 'F'
local LuaSerializer_Nil             = 'N'
local LuaSerializer_Table           = 't'
local LuaSerializer_Function        = 'f'
local LuaSerializer_String          = 's'
local LuaSerializer_Number          = 'n'
local LuaSerializer_pInf            = 'i'
local LuaSerializer_nInf            = 'I'
local LuaSerializer_nNan            = 'a'
local LuaSerializer_pNan            = 'A'
local LuaSerializer_Compressed      = 'C'
local LuaSerializer_Uncompressed    = 'U'
local LuaSerializer_CodeEscaper     = '~'
local LuaSerializer_CodeChar        = '&' -- some really rare character in serialized data
local LuaSerializer_TableSep        = LuaSerializer_CodeChar..'D'
local LuaSerializer_EndData         = LuaSerializer_CodeChar..'E'

local assert = assert
local type = type
local tostring = tostring
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs
local sub = string.sub
local gsub = string.gsub
local gmatch = string.gmatch
local match = string.match
local find = string.find
local len = string.len
local tinsert = table.insert
local tconcat = table.concat
local format = string.format
local byte = string.byte
local char = string.char
local ceil = math.ceil
-- Some lua compatibility between 5.1 and 5.2
local unpack = unpack or table.unpack
local loadstring = loadstring or load
local maxn = table.maxn or function(t) local n = 0 for k, _ in pairs(t) do if type(k) == 'number' and k > n then n = k end end return n end

-- This is not required for serializing, but it will help you keep your data smaller
local compressor = LuaSerializer_ENABLE_COMPRESSION and require("TLibCompress")

local LuaSerializer_ToMsgVal
local LuaSerializer_ToRealVal

-- Errors with msg at given level if condition is false
-- level works like on lua error function
local function LuaSerializer_assert(cond, msg, level)
    if not cond then
        error("LuaSerializer: "..(msg or "LuaSerializer assertion failed"), (level or 1)+1)
    end
end

-- Functions for handling converting table to string and from string
-- local s = LuaSerializer_Table_tostring(t), local t = LuaSerializer_Table_fromstring(s)
-- Does not support circular table relation which will cause stack overflow
local function LuaSerializer_Table_tostring( tbl )
    LuaSerializer_assert(type(tbl) == "table", "#1 table expected", 2)
    local result = {}
    for k, v in pairs( tbl ) do
        tinsert( result, LuaSerializer_ToMsgVal( k ) )
        tinsert( result, LuaSerializer_ToMsgVal( v ) )
    end
    return tconcat( result, LuaSerializer_TableSep )..LuaSerializer_TableSep
end
local function LuaSerializer_Table_fromstring( str )
    LuaSerializer_assert(type(str) == "string", "#1 string expected", 2)
    local res = {}
    for k, v in gmatch(str, "(.-)"..LuaSerializer_TableSep.."(.-)"..LuaSerializer_TableSep) do
        local _k, _v = LuaSerializer_ToRealVal(k), LuaSerializer_ToRealVal(v)
        if _k ~= nil then
            res[_k] = _v
        end
    end
    return res
end

-- Returns true if var is an LuaSerializer function table object
local function LuaSerializer_IsFunction(var)
    if type(var) ~= "table" then
        return false
    end
    if type(var.F) ~= "string" or not var.LuaSerializerF then
        return false
    end
    return true
end

-- Escapes special characters
local function LuaSerializer_Encode(str)
    LuaSerializer_assert(type(str) == "string", "#1 string expected", 2)
    return (gsub(str, LuaSerializer_CodeChar, LuaSerializer_CodeChar..LuaSerializer_CodeEscaper))
end
-- Unescapes special characters
local function LuaSerializer_Decode(str)
    LuaSerializer_assert(type(str) == "string", "#1 string expected", 2)
    return (gsub(str, LuaSerializer_CodeChar..LuaSerializer_CodeEscaper, LuaSerializer_CodeChar))
end


-- Converts table to parameter
local function LuaSerializer_ToTable(tbl)
    LuaSerializer_assert(type(tbl) == "table", "#1 table expected", 2)
    return LuaSerializer_Table..LuaSerializer_Table_tostring(tbl)
end
-- Returns string parameter
local function LuaSerializer_ToString(val)
    LuaSerializer_assert(type(val) == "string", "#1 string expected", 2)
    return LuaSerializer_String..val
end
-- Returns number parameter
local function LuaSerializer_ToNumber(val)
    val = tonumber(val)
    LuaSerializer_assert(val, "#1 number expected", 2)

    if val == math.huge then      -- test for +inf
        return LuaSerializer_pInf
    elseif val == -math.huge then -- test for -inf
        return LuaSerializer_nInf
    elseif val ~= val then        -- test for nan and -nan
        if find(tostring(val), '-', 1, true) == 1 then
            return LuaSerializer_nNan
        end
        return LuaSerializer_pNan
    end
    return LuaSerializer_Number..tostring(val)
end
-- Converts boolean to parameter
local function LuaSerializer_ToBoolean(bool)
    if bool then
        return LuaSerializer_True
    else
        return LuaSerializer_False
    end
end
-- Returns nil parameter
local function LuaSerializer_ToNil()
    return LuaSerializer_Nil
end

-- Converts a value to string using special characters to represent the value if needed
function LuaSerializer_ToMsgVal(val)
    local ret
    local Type = type(val)
    if Type == "string" then
        ret = LuaSerializer_ToString(val)
    elseif Type == "number" then
        ret = LuaSerializer_ToNumber(val)
    elseif Type == "boolean" then
        ret = LuaSerializer_ToBoolean(val)
    elseif Type == "nil" then
        ret = LuaSerializer_ToNil()
    elseif Type == "function" then
        error("#1 Cant pass function, use LuaSerializer_ToFunction(FuncAsString) to pass a function parameter", 2)
        return
    elseif Type == "table" then
        if LuaSerializer_IsFunction(val) then
            if not LuaSerializer_ENABLE_FUNCTIONS then
                error("functions are not enabled to be serializable")
                return
            else
                ret = LuaSerializer_Function..LuaSerializer_Table_tostring(val)
            end
        else
            ret = LuaSerializer_ToTable(val)
        end
    end
    if not ret then
        error("#1 Invalid value type ".. Type)
    end
    return LuaSerializer_Encode(ret)
end

-- Converts a string value from a message to the actual value it represents
function LuaSerializer_ToRealVal(val)
    LuaSerializer_assert(type(val) == "string", "#1 string expected", 2)

    local Type, data = match(LuaSerializer_Decode(val), "(.)(.*)")
    if not Type or not data then
        return nil
    elseif Type == LuaSerializer_Nil then
        return nil
    elseif Type == LuaSerializer_True then
        return true
    elseif Type == LuaSerializer_False then
        return false
    elseif Type == LuaSerializer_String then
        return data
    elseif Type == LuaSerializer_Number then
        return tonumber(data)
    elseif Type == LuaSerializer_pInf then
        return math.huge
    elseif Type == LuaSerializer_nInf then
        return -math.huge
    elseif Type == LuaSerializer_pNan then
        return -(0/0)
    elseif Type == LuaSerializer_nNan then
        return 0/0
    elseif Type == LuaSerializer_Function then
        if not LuaSerializer_ENABLE_FUNCTIONS then
            error("functions are not enabled to be serializable")
            return nil
        end
        local tbl = LuaSerializer_Table_fromstring(data)
        if not LuaSerializer_IsFunction(tbl) then
            return nil
        end
        local func, err = loadstring(tbl.F)
        LuaSerializer_assert(func, err, 2)
        if tbl.R then
            -- RetRealFunc was true
            func = func()
        end
        return func
    elseif Type == LuaSerializer_Table then
        return LuaSerializer_Table_fromstring(data)
    end

    return nil -- val
end

-- Allow using a string that contains the function contents:
-- Converts a string to an LuaSerializer function parameter
-- Note that all parameters passed to function will be accessible with ...
-- If RetRealFunc is true then when the string is executed it returns a function to actually use as function
function LuaSerializer.ToFunction(FuncAsString, RetRealFunc)
    LuaSerializer_assert(type(FuncAsString) == "string", "#1 string expected", 2)
    return {F = FuncAsString, R = RetRealFunc, LuaSerializerF = true}
end

-- Takes in values and returns a string with them serialized
function LuaSerializer.serialize(...)
    -- convert values into string form
    local n = select('#', ...)
    local serializeddata = {...}
    for i = 1, n do
        serializeddata[i] = LuaSerializer_ToMsgVal(serializeddata[i])
    end
    --
    serializeddata = tconcat(serializeddata, LuaSerializer_EndData)..LuaSerializer_EndData
    if LuaSerializer_ENABLE_COMPRESSION then
        serializeddata = LuaSerializer_Compressed..assert(compressor.CompressLZW(serializeddata))
    else
        serializeddata = LuaSerializer_Uncompressed..serializeddata
    end
    return serializeddata
end

-- Takes in a string of serialized data and returns the values in it
function LuaSerializer.deserialize(serializeddata)
    LuaSerializer_assert(type(serializeddata) == 'string', "#1 string expected", 2)

    -- check if data is compressed and uncompress if needed
    local compression, serializeddata = sub(serializeddata, 1, 1), sub(serializeddata, 2)
    if compression == LuaSerializer_Compressed then
        serializeddata = assert(compressor.DecompressLZW(serializeddata))
    end

    -- parse all data and convert it to real values
    local res = {}
    local i = 1
    for data in gmatch(serializeddata, "(.-)"..LuaSerializer_EndData) do
        -- tinsert is not used here since it ignores nil values
        res[i] = LuaSerializer_ToRealVal(data)
        i = i+1
    end

    return unpack(res, 1, i-1)
end

return LuaSerializer
