---@class FusedReader
---@field streams Stream[]
---@field sizes integer[]
---@field currentIndex integer
---@field currentStream Stream
---@field currentSize integer
local FusedReader = {}

---@class Stream
---@field read function
---@field seek function
---@field close function

---Returns true if the file is a CC file.
---@param file table a file object returned by `fs.open`
---@return boolean isCCFile
local function isCCFile(file)
	return not not file.readAll -- only CC files have this method
end

-- A compatibility layer for ComputerCraft files. CC files use dot syntax instead of colon syntax.
local FileCompatWrapper = {}

---@param file table a file object returned by `fs.open`
---@return Stream stream the compatible stream 
local function makeCompatFile(file)
	return setmetatable({file = file}, {__index = FileCompatWrapper}) 
end

function FileCompatWrapper:read(...) return self.file.read(...) end

function FileCompatWrapper:seek(whence, offset)
	return self.file.seek(whence, offset)
end

function FileCompatWrapper:close()
	self.file.close()
end

---Returns the size of the stream, in bytes.
---@param stream Stream
---@return integer size
local function getStreamSize(stream)
  local size = stream:seek("end")
  stream:seek("set")
  return size
end

function FusedReader.new()
  return setmetatable({
    streams = {},
    sizes = {},
    currentIndex = 1,
    currentStream = nil,
    currentSize = 0,
  }, {__index = FusedReader})
end

---Adds a single stream to the reader.
---@param stream Stream
function FusedReader:addStream(stream)
  local len = #self.streams
  assert(stream.read and stream.seek and stream.close, "invalid stream: #" .. len + 1)
  local size = getStreamSize(stream)
  -- set as first stream if none
  if len == 0 then
    self.currentStream = stream
    self.currentSize = size
  end
  self.streams[len+1] = stream
  self.sizes[len+1] = size
end

---Adds multiple streams to the reader.
---@param ... Stream|Stream[]|FusedReader
function FusedReader:addStreams(...)
  local streams = {...}
  for i=1,#streams do
    local stream = streams[i]
    if type(stream) == "table" then self:addStreams(stream) end

    if getmetatable(stream).__index == FusedReader then
      self:addStreams(stream.streams)
      return
    end

    if isCCFile(stream) then stream = makeCompatFile(stream) end
    self:addStream(stream)
  end
end

FusedReader.pushStreams = FusedReader.addStreams

--- Creates a new reader from multiple streams.
---@param ... Stream|Stream[]
---@return FusedReader
function FusedReader.FromStreams(...)
  local reader = FusedReader.new()
  reader:addStreams(...)
  return reader
end

--- Opens multiple files and adds them to the reader without doing globbing.
--- This function throws if `io.open` fails.
---@param ... string the paths to each file.
function FusedReader.fromPathsRaw(...)
  local reader = FusedReader.new()
  local paths = {...}
  for i=1,#paths do
    local path = paths[i]
    reader:addStreams(assert(io.open(path, "rb")))
  end
end

function FusedReader:nextStream()
  self.currentStream.close()
  local index = self.currentIndex + 1
  self.currentStream = self.streams[index]
  self.currentSize = self.sizes[index]
  self.currentIndex = index
end

function FusedReader:isCurrentEOF()
  return self.currentStream:seek() == self.currentSize
end

function FusedReader:isFinished()
  if self.currentIndex > #self.streams then
    return true
  end
  return false
end

--- Closes the reader and all underlying streams.
function FusedReader:close()
  for i=1,#self.streams do
    self.streams[i]:close()
  end
end

--- Reads from the current stream.
---@param ... "n"|"a"|"l"|"L"|integer
---@return ... string|nil
function FusedReader:read(...)
  local readModes = {...}

  if #readModes == 0 then
    return self:readLine()
  end

  for i=1,#readModes do
    local readMode = readModes[i]
    if type(readMode) == "number" then
      return self:readBytes(readMode)
    elseif readMode == "a" then
      return self:readAll()
    elseif readMode == "l" then
      return self:readLine()
    elseif readMode == "L" then
      return self:readLine(true)
    end
  end
end

function FusedReader:readBytes(count)
  local buffer = {}
  local bytes = ""
  while #bytes < count do
    bytes = bytes .. (self.currentStream:read(count) or "")
    if self:isCurrentEOF() then self:nextStream() end
    if self:isFinished() then break end
  end
  return bytes
end

function FusedReader:readAll()
  local buffer = {}
  while not self:isFinished() do
    local text = self.currentStream:read("a")
    if text then
      buffer[#buffer + 1] = text
    end
    self:nextStream()
  end
  return table.concat(buffer,"\n")
end

function FusedReader:readLine(keepEOL)
  local line = self.currentStream:read(keepEOL and "L" or "l")
  if self:isCurrentEOF() then self:nextStream() end
  return line
end

return FusedReader