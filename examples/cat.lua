local reader = require("../FusedReader").fromPathsRaw(...)
print(reader:readAll())
reader:close()