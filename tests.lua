local x = require("xtest")
local FusedReader = require("FusedReader")

x.run{
  "Concatenates files",
  function()
    local hello = x.file("hello.txt","Hello")
    local world = x.file("world.txt"," world!")

    local fused = FusedReader.fromStreams(hello, world)
    x.assertEq(fused:readAll(), "Hello world!")
    fused:close()

    fused = FusedReader.fromStreams(x.file"hello.txt", x.file"world.txt")
    x.assertEq(fused:readAll(), "Hello world!")
    fused:close()
  end,
  "Parsing numbers",
  function()
    local f = x.file("num.txt","0xfeed")
    local num = f:read"*n"
    x.assertEq(num, 0xfeed)
    f:close()
  end
}