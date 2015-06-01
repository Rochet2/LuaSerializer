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
local serialized = SLS.serialize(55, "test", {1,2, y = 66}, nil, true, SLS.ToFunction('print("Hello")'))
print(SLS.deserialize(serialized))
]]

assert(_VERSION == 'Lua 5.1' or _VERSION == 'Lua 5.2', "SLS serializer is coded for lua 5.1 and 5.2")

-- SLS main table
local SLS = {}

-- Enables deserializing functions (uses loadstring or load)
local SLS_ENABLE_FUNCTIONS      = true

-- Enables LZW compression for the serialized data
local SLS_ENABLE_COMPRESSION    = true -- default true

-- Client must have same version (basically same SLS file)
SLS.Version = 0.75
-- ID characters for the serialization
local SLS_True            = 'T'
local SLS_False           = 'F'
local SLS_Nil             = 'N'
local SLS_Table           = 't'
local SLS_Function        = 'f'
local SLS_String          = 's'
local SLS_Number          = 'n'
local SLS_pInf            = 'i'
local SLS_nInf            = 'I'
local SLS_nNan            = 'a'
local SLS_pNan            = 'A'
local SLS_Compressed      = 'C'
local SLS_Uncompressed    = 'U'
local SLS_CodeEscaper     = '~'
local SLS_CodeChar        = '&' -- some really rare character in serialized data
local SLS_TableSep        = SLS_CodeChar..'D'
local SLS_EndData         = SLS_CodeChar..'E'

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
local compressor = SLS_ENABLE_COMPRESSION and require("TLibCompress")

local SLS_ToMsgVal
local SLS_ToRealVal

-- Errors with msg at given level if condition is false
-- level works like on lua error function
local function SLS_assert(cond, msg, level)
    if not cond then
        error("SLS: "..(msg or "SLS assertion failed"), (level or 1)+1)
    end
end

-- Functions for handling converting table to string and from string
-- local s = SLS_Table_tostring(t), local t = SLS_Table_fromstring(s)
-- Does not support circular table relation which will cause stack overflow
local function SLS_Table_tostring( tbl )
    SLS_assert(type(tbl) == "table", "#1 table expected", 2)
    local result = {}
    for k, v in pairs( tbl ) do
        tinsert( result, SLS_ToMsgVal( k ) )
        tinsert( result, SLS_ToMsgVal( v ) )
    end
    return tconcat( result, SLS_TableSep )..SLS_TableSep
end
local function SLS_Table_fromstring( str )
    SLS_assert(type(str) == "string", "#1 string expected", 2)
    local res = {}
    for k, v in gmatch(str, "(.-)"..SLS_TableSep.."(.-)"..SLS_TableSep) do
        local _k, _v = SLS_ToRealVal(k), SLS_ToRealVal(v)
        if _k ~= nil then
            res[_k] = _v
        end
    end
    return res
end

-- Returns true if var is an SLS function table object
local function SLS_IsFunction(var)
    if type(var) ~= "table" then
        return false
    end
    if type(var.F) ~= "string" or not var.SLSF then
        return false
    end
    return true
end

-- Escapes special characters
local function SLS_Encode(str)
    SLS_assert(type(str) == "string", "#1 string expected", 2)
    return (gsub(str, SLS_CodeChar, SLS_CodeChar..SLS_CodeEscaper))
end
-- Unescapes special characters
local function SLS_Decode(str)
    SLS_assert(type(str) == "string", "#1 string expected", 2)
    return (gsub(str, SLS_CodeChar..SLS_CodeEscaper, SLS_CodeChar))
end


-- Converts table to parameter
local function SLS_ToTable(tbl)
    SLS_assert(type(tbl) == "table", "#1 table expected", 2)
    return SLS_Table..SLS_Table_tostring(tbl)
end
-- Returns string parameter
local function SLS_ToString(val)
    SLS_assert(type(val) == "string", "#1 string expected", 2)
    return SLS_String..val
end
-- Returns number parameter
local function SLS_ToNumber(val)
    val = tonumber(val)
    SLS_assert(val, "#1 number expected", 2)

    if val == math.huge then      -- test for +inf
        return SLS_pInf
    elseif val == -math.huge then -- test for -inf
        return SLS_nInf
    elseif val ~= val then        -- test for nan and -nan
        if find(tostring(val), '-', 1, true) == 1 then
            return SLS_nNan
        end
        return SLS_pNan
    end
    return SLS_Number..tostring(val)
end
-- Converts boolean to parameter
local function SLS_ToBoolean(bool)
    if bool then
        return SLS_True
    else
        return SLS_False
    end
end
-- Returns nil parameter
local function SLS_ToNil()
    return SLS_Nil
end

-- Converts a value to string using special characters to represent the value if needed
function SLS_ToMsgVal(val)
    local ret
    local Type = type(val)
    if Type == "string" then
        ret = SLS_ToString(val)
    elseif Type == "number" then
        ret = SLS_ToNumber(val)
    elseif Type == "boolean" then
        ret = SLS_ToBoolean(val)
    elseif Type == "nil" then
        ret = SLS_ToNil()
    elseif Type == "function" then
        error("#1 Cant pass function, use SLS_ToFunction(FuncAsString) to pass a function parameter", 2)
        return
    elseif Type == "table" then
        if SLS_IsFunction(val) then
            if not SLS_ENABLE_FUNCTIONS then
                error("functions are not enabled to be serializable")
                return
            else
                ret = SLS_Function..SLS_Table_tostring(val)
            end
        else
            ret = SLS_ToTable(val)
        end
    end
    if not ret then
        error("#1 Invalid value type ".. Type)
    end
    return SLS_Encode(ret)
end

-- Converts a string value from a message to the actual value it represents
function SLS_ToRealVal(val)
    SLS_assert(type(val) == "string", "#1 string expected", 2)

    local Type, data = match(SLS_Decode(val), "(.)(.*)")
    if not Type or not data then
        return nil
    elseif Type == SLS_Nil then
        return nil
    elseif Type == SLS_True then
        return true
    elseif Type == SLS_False then
        return false
    elseif Type == SLS_String then
        return data
    elseif Type == SLS_Number then
        return tonumber(data)
    elseif Type == SLS_pInf then
        return math.huge
    elseif Type == SLS_nInf then
        return -math.huge
    elseif Type == SLS_pNan then
        return -(0/0)
    elseif Type == SLS_nNan then
        return 0/0
    elseif Type == SLS_Function then
        if not SLS_ENABLE_FUNCTIONS then
            error("functions are not enabled to be serializable")
            return nil
        end
        local tbl = SLS_Table_fromstring(data)
        if not SLS_IsFunction(tbl) then
            return nil
        end
        local func, err = loadstring(tbl.F)
        SLS_assert(func, err, 2)
        if tbl.R then
            -- RetRealFunc was true
            func = func()
        end
        return func
    elseif Type == SLS_Table then
        return SLS_Table_fromstring(data)
    end

    return nil -- val
end

-- Allow using a string that contains the function contents:
-- Converts a string to an SLS function parameter
-- Note that all parameters passed to function will be accessible with ...
-- If RetRealFunc is true then when the string is executed it returns a function to actually use as function
function SLS.ToFunction(FuncAsString, RetRealFunc)
    SLS_assert(type(FuncAsString) == "string", "#1 string expected", 2)
    return {F = FuncAsString, R = RetRealFunc, SLSF = true}
end

-- Takes in a string of serialized data and returns the values in it
function SLS.serialize(...)
    -- convert values into string form
    local n = select('#', ...)
    local serializeddata = {...}
    for i = 1, n do
        serializeddata[i] = SLS_ToMsgVal(serializeddata[i])
    end
    --
    serializeddata = tconcat(serializeddata, SLS_EndData)..SLS_EndData
    if SLS_ENABLE_COMPRESSION then
        serializeddata = SLS_Compressed..assert(compressor.CompressLZW(serializeddata))
    else
        serializeddata = SLS_Uncompressed..serializeddata
    end
    return serializeddata
end

-- Takes in a string of serialized data and returns the values in it
function SLS.deserialize(serializeddata)
    SLS_assert(type(serializeddata) == 'string', "#1 string expected", 2)

    -- check if data is compressed and uncompress if needed
    local compression, serializeddata = sub(serializeddata, 1, 1), sub(serializeddata, 2)
    if compression == SLS_Compressed then
        serializeddata = assert(compressor.DecompressLZW(serializeddata))
    end

    -- parse all data and convert it to real values
    local res = {}
    local i = 1
    for data in gmatch(serializeddata, "(.-)"..SLS_EndData) do
        -- tinsert is not used here since it ignores nil values
        res[i] = SLS_ToRealVal(data)
        i = i+1
    end

    return unpack(res, 1, i-1)
end

return SLS
