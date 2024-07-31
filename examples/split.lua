local FusedReader = require("../FusedReader")
local arg = {...}
local pattern = "[^".. arg[1] .."]+"

local reader = FusedReader.new()
for i=2,#arg do
  reader:addStream(assert(io.open(arg[i], "rb")))
end

local line = reader:readLine()
while line ~= nil do
  for word in line:gmatch(pattern) do
    print(word)
  end
  line = reader:readLine()
end