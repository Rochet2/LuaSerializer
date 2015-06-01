# LuaSerializer
LuaSerializer is a pure lua serializer that does not use loadstring or pcall for table deserialization. Works with Lua 5.1 and 5.2.  
Backlink: https://github.com/Rochet2/LuaSerializer

#Limitations
- Tables with cycles can not be serialized.
- Metatables are not serialized.
- Userdata can not be serialized
- All serialized functions must be in string from and converted to LuaSerializer form using LuaSerializer.ToFunction due to differences in lua 5.1 and 5.2 bytecode (this was used across them). You may also try to use Lua's string.dump function and serialize the result string.

#Serializing
LuaSerializer serializes data into a string and is able to then deserialize the data without using loadstring (safely).  
Each serialized value takes minimum of 2 to 3 characters extra space.
Tables take min 2 to 3 characters extra space per value and 3 characters for the table.  
LuaSerializer is capable of serializing:
- nil
- bool
- string
- number including nan and inf
- function (see limitations)
- tables with no unserializable data and no cycles

#API
```lua
local LuaSerializer = require("LuaSerializer")

-- serializer version
print(LuaSerializer.Version)
-- takes in a string of serialized data and returns the values in it
-- SLS.serialize(...)
-- takes in values and returns a string with them serialized
-- SLS.deserialize(serializeddata)

local serialized = SLS.serialize(55, "test", {1,2, y = 66}, nil, true, SLS.ToFunction('print("Hello")'))
print(SLS.deserialize(serialized))
-- prints:
-- 55      test    table: 491A9920 nil     true    function: 4A3893C0
```

#Included dependencies
You do not need to get these, they are already included
- Compression for string data: https://love2d.org/wiki/TLTools

#Special thanks
- Kenuvis < [Gate](http://www.ac-web.org/forums/showthread.php?148415-LUA-Gate-Project), [ElunaGate](https://github.com/ElunaLuaEngine/ElunaGate) >
- Laurea (alexeng) < https://github.com/Alexeng >
- Lua contributors < http://www.lua.org/ >
