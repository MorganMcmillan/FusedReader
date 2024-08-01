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
  "Parsing hex numbers",
  function()
    local f = x.file("num.txt","0xfeed")
    local num = f:read"n"
    x.assertEq(num, 0xfeed)
    f:seek("set")
    local fused = FusedReader.fromStreams(f)
    num = fused:read"n"
    x.assertEq(num, 0xfeed)
    fused:close()
    fused:addStreams(x.file("num1","0xfe"), x.file("num2","ed"))
    x.assertEq(num, 0xfeed)
    fused:close()
  end,
  "Parsing decimal numbers",
  function()
    local f = x.file("num.txt","420")
    local num = f:read"n"
    x.assertEq(num, 420)
    f:seek("set")
    local fused = FusedReader.fromStreams(f)
    num = fused:read"n"
    x.assertEq(num, 420)
    fused:close()
    fused = FusedReader.fromStreams(x.file("num1","420"), x.file("num2","69"), x.file("num3","666"))
    num = fused:read"n"
    x.assertEq(num, 42069666)
    fused:close()
  end,
}