local FusedReader = require("../FusedReader")
local arg = {...}

local reader = FusedReader.new()
for i=1,#arg do
  reader:addStream(assert(io.open(arg[i], "rb")))
end

local line = reader:readLine()
while line ~= nil do
  for word in line:gmatch"%S+" do
    print(word)
  end
  line = reader:readLine()
end