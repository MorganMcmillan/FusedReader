local concat,setmetatable,getmetatable = table.concat,setmetatable,getmetatable

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
function FusedReader.fromStreams(...)
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
    reader:addStream(assert(io.open(paths[i], "rb")))
  end
  return reader
end

function FusedReader:nextStream()
  if self.currentStream then self.currentStream:close() end
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
    local stream = self.streams[i]
    pcall(stream.close,stream)
  end
  self.streams = {}
  self.sizes = {}
  self.currentStream = nil
  self.currentSize = 0
  self.currentIndex = 0
end

--- Reads from the current stream.
---@param ... "n"|"a"|"l"|"L"|integer
---@return ... string|number|nil
function FusedReader:read(...)
  if not self.currentStream then return end
  local readModes = {...}

  if #readModes == 0 then
    return self:readLine()
  end

  local outputs = {}

  for i=1,#readModes do
    local readMode = readModes[i]
    if type(readMode) == "number" then
      outputs[#outputs + 1] = self:readBytes(readMode)
    elseif readMode == "n" then
      outputs[#outputs + 1] = self:readNumber()
    elseif readMode == "a" then
      outputs[#outputs + 1] = self:readAll()
    elseif readMode == "l" then
      outputs[#outputs + 1] = self:readLine()
    elseif readMode == "L" then
      outputs[#outputs + 1] = self:readLine(true)
    end
  end

  return unpack(outputs)
end

--- Reads characters that match a patter
---@param pat string|function
---@return string|nil
function FusedReader:readWhile(pat)
  if not self.currentStream then return end
  local buffer = {}
  local char
  if type(pat) == "string" then
    while true do
      char = self:readBytes(1)
      if not char then break end
      if char:match(pat) then
        buffer[#buffer + 1] = char
      else
        break
      end
    end
  else
    while true do
      char = self:readBytes(1)
      if not char then break end
      if pat(char) then
        buffer[#buffer + 1] = char
      else
        break
      end
    end
  end
  if #buffer == 0 then return end
  return concat(buffer)
end

function FusedReader:readBytes(count)
  if not self.currentStream then return end
  local buffer = {}
  while count > 0 do
    local bytes = self.currentStream:read(count) or ""
    count = count - #bytes
    buffer[#buffer + 1] = bytes
    if self:isCurrentEOF() then self:nextStream() end
    if self:isFinished() then break end
  end
  return concat(buffer)
end

--- Reads a number from the current stream.
--- The number can be in hex, octal, or binary, depending on it's prefix.
--- Returns nil if no number could be read.
---@return number|nil
function FusedReader:readNumber()
  if not self.currentStream then return end
  local buf = self:readBytes(1)
  if buf == "0" then
    local prefix = self:readBytes(1)
    if prefix == "x" or prefix == "X" then
      local hex = self:readWhile("%x")
      return hex and tonumber(hex, 16)
    elseif prefix == "o" or prefix == "O" then
      local oct = self:readWhile("[0-7]")
      return oct and tonumber(oct, 8)
    elseif prefix == "b" or prefix == "B" then
      local bin = self:readWhile("[01]")
      return bin and tonumber(bin, 2)
    end
  elseif tonumber(buf) then
    return tonumber(buf .. (self:readWhile("[0-9]") or ""))
  end
end

function FusedReader:readAll()
  if not self.currentStream then return end
  local buffer = {}
  while not self:isFinished() do
    local text = self.currentStream:read("a")
    if text then
      buffer[#buffer + 1] = text
    end
    self:nextStream()
  end
  return concat(buffer)
end

function FusedReader:readLine(keepEOL)
  if not self.currentStream then return end
  local line = self.currentStream:read(keepEOL and "L" or "l")
  if self:isCurrentEOF() then self:nextStream() end
  return line
end

--TODO: add `seek`

return FusedReader
