local reader = require("../FusedReader.lua").fromPaths(...)
print(reader:readAll())
reader:close()