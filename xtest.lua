local abs, floor, error, type, tostring, pairs, unpack = math.abs, math.floor, error, type, tostring, pairs, unpack or table.unpack
local mkdir = fs and fs.makeDir or function (dir) os.execute("mkdir ".. dir) end
local xtest = {}

--- Converts a value to a string for printing.
--- Adds quotation marks around string values
---@param s any
---@return string
local function stringify(s, indentation)
  indentation = indentation or 0
  --TODO: Serialize tables to make them printable
  if type(s) == "string" then
    local formatted = ("%q"):format(s):gsub("\\\n", "\\n")
    return formatted
  end
  return tostring(s)
end

---Fails an assertion with the given message and level
---A failed assertion takes the following form:
---`assertion <sAssertionMessage> failed:`
---`<sMainMessage>`
---@param sMainMessage? string
---@param sAssertionMessage? string
---@param nLevel? number
local function fail(sMainMessage, sAssertionMessage, nLevel)
  --Level is set to three so the error points back to the user's test file
  error("assertion " .. (sAssertionMessage and (sAssertionMessage .. " ") or "") .. "failed" ..
    (sMainMessage and ":\n" .. sMainMessage or "!") .. "\n",
    nLevel or 3)
end

---@class (exact) TestSettings
---@field continue? boolean should the tests continue after failure
---@field printLabel? boolean should each test print its label
---@field printResults? boolean should results be printed

---@type TestSettings
local DEFAULT_TEST_SETTINGS = {
  continue = false,
  printLabel = true,
  printResults = true,
}

---Runs each test sequencially
---@param tests (function|string)[] the array of test functions and test labels
---@param testSettings? TestSettings the settings used, defaukts to `DEFAULT_TEST_SETTINGS`
---@param printFn? fun(...:string) the function to use for printing, defaults to `print`
---@return boolean success, table results
function xtest.run(tests, testSettings, printFn)
  if type(tests) ~= "table" then error("Tests must be a table of functions and label strings") end

  local print = printFn or print

  -- Load test settings
  if testSettings then
    for k, v in pairs(DEFAULT_TEST_SETTINGS) do
      if testSettings[k] == nil then
        testSettings[k] = v
      end
    end
  else
    testSettings = DEFAULT_TEST_SETTINGS
  end

  -- This is used instead of i so we only count the amount of functions that have been run
  local testNumber = 0
  local passed, failed = 0, 0
  local label = nil

  local startTime = os.clock()
  for i = 1, #tests do
    local test = tests[i]

    if type(test) == "string" then
      if testSettings.printLabel then
        -- Set the label of the current test
        -- Appending it as a new line if there was already one
        label = label and (label .. '\n' .. test) or test
      end
    elseif type(test) == "function" then
      testNumber = testNumber + 1
      if testSettings.printLabel then
        print("Test #" .. testNumber .. " : " .. (label or "") .. "\n")
        label = nil
      end

      local ok, message = pcall(test)
      if ok then
        passed = passed + 1
        if testSettings.printLabel then print "Passed!\n" end
      else
        failed = failed + 1
        if testSettings.printLabel then print "Failed!\n" end
        if testSettings.printLabel then print(message) end
        if not testSettings.continue then break end
      end
    else
      error(
        "Tests should only contain a string label or a function, but instead got " ..
        test .. " of type" .. type(test) .. " at index " .. i ..
        ".", 1)
    end
  end

  local timeTaken = os.clock() - startTime
  local results = { passed = passed, failed = failed, total = testNumber, timeTaken = timeTaken }
  if testSettings.printResults then
    print(("Test results:\n\tpassed: %s\n\tfailed: %s\n\ttotal: %s\n\ttime taken: %f seconds"):format(passed, failed,
      testNumber, timeTaken))
  end
  return failed == 0, results
end

-- Basic assertions

---Asserts the given condition is true, and fails with a message if it is not
---@param cond any
---@param message? string
---@return any cond
function xtest.assert(cond, message)
  if not cond then fail(message) end
  return cond
end

---Asserts the given condition is false, and fails with a message if it is not
---@param cond any
---@param message? string
---@return any cond
function xtest.assertNot(cond, message)
  if cond then fail(message) end
  return cond
end

-- Equality assertions

---Asserts that `left` expression is equal to `right` expression
---@param left any
---@param right any
---@return any left
---@return any right
function xtest.assertEq(left, right)
  if left ~= right then fail("left = " .. stringify(left) .. ",\nright = " .. stringify(right), "'left == right'") end
  return left, right
end

---Asserts that `left` table is shallowly equal to `right` table, meaning that both have the same keys with the same values
---@param left table
---@param right table
---@return any left
---@return any right
function xtest.assertShallowEq(left, right)
  for k, v in pairs(left) do
    if right[k] ~= v then
      fail("left[" .. stringify(k) .. "] = " .. v .. ",\nright[" .. stringify(k) .. "] = " .. right[k],
        "'left is shallowly equal to right'")
    end
  end
  return left, right
end

-- Checks if two tables are deeply equal
local function deepEquals(left, right)
  for k, v in pairs(left) do
    local v2 = right[k]
    if type(v) == "table" and type(v2) == "table" then
      if v ~= v2 and not deepEquals(v, v2) then
        return false
      end
    else
      if v ~= v2 then
        return false
      end
    end
  end
  return true
end

---Asserts that `left` table is deeply equal to `right` table, meaning that both have the same keys with the same values, and all subtables meet the same conditions
---@param left table
---@param right table
---@return any left
---@return any right
function xtest.assertDeepEq(left, right)
  if not deepEquals(left, right) then
    fail("left = " .. stringify(left) .. ",\nright = " .. stringify(right), "'left is deeply equal to right'")
  end
  return left, right
end

---Asserts that `left` expression is not equal to `right` expression
---@param left any
---@param right any
---@return any left
---@return any right
function xtest.assertNe(left, right)
  if left == right then fail("left = " .. stringify(left) .. ",\nright = " .. stringify(right), "'left ~= right'") end
  return left, right
end

---Asserts that `left` table is not shallowly equal to `right` table, meaning that both do not have all the same keys with the same values
---@param left table
---@param right table
---@return any left
---@return any right
function xtest.assertShallowNe(left, right)
  local isEqual = true
  for k, v in pairs(left) do
    if right[k] ~= v then
      isEqual = false
      break
    end
  end
  if isEqual then
    fail("left = " .. stringify(left) .. ",\nright = " .. stringify(right), "'left is not shallowly equal to right'")
  end
  return left, right
end

---Asserts that `left` table is not deeply equal to `right` table, meaning that both do not have all the same keys with the same values, and all subtables meet the same conditions
---@param left table
---@param right table
---@return any left
---@return any right
function xtest.assertDeepNe(left, right)
  if deepEquals(left, right) then
    fail("left = " .. stringify(left) .. ",\nright = " .. stringify(right), "'left is not deeply equal to right'")
  end
  return left, right
end

-- Arithmetic assertions

---Asserts that two numbers are approximately equal based on a margin
---@param left number
---@param right number
---@return any left
---@return any right
function xtest.assertApproxEq(left, right, margin)
  margin = margin or (2 ^ -52) -- Machine epsilon
  if abs(left - right) <= margin then
    fail("left = " .. left .. ",\nright = " .. right .. "\nmargin = " .. margin, "'left is approximately equal to right'")
  end
  return left, right
end
xtest.assertApproximatlyEq = xtest.assertApproxEq
xtest.assertApproxEqual = xtest.assertApproxEq
xtest.assertApproximatlyEqual = xtest.assertApproxEq

---Asserts that `left` expression is less than `right` expression
---@param left number
---@param right number
---@return number left
---@return number right
function xtest.assertLt(left, right)
  if left >= right then fail("left = " .. tostring(left) .. ",\nright = " .. tostring(right), "'left < right'") end
  return left, right
end
xtest.assertLess = xtest.assertLt
xtest.assertLessThan = xtest.assertLt

---Asserts that `left` expression is greater than `right` expression
---@param left number
---@param right number
---@return number left
---@return number right
function xtest.assertGt(left, right)
  if left <= right then fail("left = " .. tostring(left) .. ",\nright = " .. tostring(right), "'left > right'") end
  return left, right
end

xtest.assertGreater = xtest.assertGt
xtest.assertGreaterThan = xtest.assertGt

---Asserts that `left` expression is less than or equal to `right` expression
---@param left number
---@param right number
---@return number left
---@return number right
function xtest.assertLe(left, right)
  if left > right then fail("left = " .. tostring(left) .. ",\nright = " .. tostring(right), "'left <= right'") end
  return left, right
end

xtest.assertLessOrEqual = xtest.assertLe
xtest.assertLessThanOrEqual = xtest.assertLe

---Asserts that `left` expression is greater than or equal to `right` expression
---@param left number
---@param right number
---@return number left
---@return number right
function xtest.assertGe(left, right)
  if left < right then fail("left = " .. tostring(left) .. ",\nright = " .. tostring(right), "'left >= right'") end
  return left, right
end

xtest.assertGreaterOrEqual = xtest.assertGe
xtest.assertGreaterThanOrEqual = xtest.assertGe

-- Type assertions

---Asserts that `value` is of type `nil`
---@param value any
---@return any value
function xtest.assertNil(value)
  if value ~= nil then
    fail('type(value) = "' .. type(value) .. '"\nvalue = ' .. stringify(value),
      "'type(value) == \"nil\"'")
  end
  return value
end

---Asserts that `value` is not of type `nil`
---@param value any
---@return any value
function xtest.assertNotNil(value)
  if value == nil then
    fail('type(value) = "nil"\nvalue = nil', "'type(value) ~= \"nil\"'")
  end
  return value
end

---Asserts that `value` is of type `number`
---@param value any
---@return number value
function xtest.assertNumber(value)
  if type(value) ~= "number" then
    fail('type(value) = "' .. type(value) .. '"\nvalue = ' .. stringify(value),
      "'type(value) == \"number\"'")
  end
  return value
end

---Asserts that `value` is of type `number` and is an integer
---@param value any
---@return integer value
function xtest.assertInteger(value)
  if type(value) ~= "number" then
    fail('type(value) = "' .. type(value) .. '"\nvalue = ' .. stringify(value),
      "'type(value) == \"number\"'")
  end
  if floor(value) ~= value then fail("value = " .. value, "'value is integer'") end
  return value
end

---Asserts that `value` is of type `string`
---@param value any
---@return string value
function xtest.assertString(value)
  if type(value) ~= "string" then
    fail('type(value) = "' .. type(value) .. '"\nvalue = ' .. stringify(value),
      "'type(value) == \"string\"'")
  end
  return value
end

---Asserts that `value` is of type `boolean`
---@param value any
---@return boolean value
function xtest.assertBoolean(value)
  if type(value) ~= "boolean" then
    fail('type(value) = "' .. type(value) .. '"\nvalue = ' .. stringify(value),
      "'type(value) == \"boolean\"'")
  end
  return value
end

---Asserts that `value` is `true`
---@param value any
---@return boolean value
function xtest.assertTrue(value)
  if value ~= true then fail("value = " .. stringify(value), "'value == true'") end
  return value
end

---Asserts that `value` is `false`
---@param value any
---@return boolean value
function xtest.assertFalse(value)
  if value ~= false then fail("value = " .. stringify(value), "'value == false'") end
  return value
end

---Asserts that `value` is of type `table`
---@param value any
---@return table value
function xtest.assertTable(value)
  if type(value) ~= "table" then
    fail('type(value) = "' .. type(value) .. '"\nvalue = ' .. stringify(value),
      "'type(value) == \"table\"'")
  end
  return value
end

---Asserts that `value` is of type `function`
---@param value any
---@return function value
function xtest.assertFunction(value)
  if type(value) ~= "function" then
    fail('type(value) = "' .. type(value) .. '"\nvalue = ' .. stringify(value),
      "'type(value) == \"function\"'")
  end
  return value
end

---Asserts that `value` is of type `thread`
---@param value any
---@return thread value
function xtest.assertThread(value)
  if type(value) ~= "thread" then
    fail('type(value) = "' .. type(value) .. '"\nvalue = ' .. stringify(value),
      "'type(value) == \"thread\"'")
  end
  return value
end

---Asserts that `value` is of type `userdata`
---@param value any
---@return userdata value
function xtest.assertUserdata(value)
  if type(value) ~= "userdata" then
    fail('type(value) = "' .. type(value) .. '"\nvalue = ' .. stringify(value),
      "'type(value) == \"userdata\"'")
  end
  return value
end

---Asserts that a value is of a given type
---@param value any
---@param sType "nil" | "number" | "string" | "boolean" | "table" | "function" | "thread" | "userdata"
---@return any value
function xtest.assertType(value, sType)
  local ty = type(value)
  if ty ~= sType then fail("value = " .. stringify(value) .. "\ntype = " .. ty, "'type(value) == " .. sType .. "'") end
  return value
end

---Asserts that a value is not of a given type
---@param value any
---@param sType "nil" | "number" | "string" | "boolean" | "table" | "function" | "thread" | "userdata"
---@return any value
function xtest.assertNotType(value, sType)
  if type(value) == sType then
    fail("value = " .. stringify(value) .. "\ntype = " .. sType,
      "'type(value) ~= " .. sType .. "'")
  end
  return value
end

-- Error checking assertions

---Asserts that a function does not throw an error when called
function xtest.assertOk(fun, ...)
  local result = { pcall(fun, ...) }
  if not result[1] then fail(result[2], "'function does not throw error'") end
  return unpack(result, 2)
end

---Asserts that a function trows any error when called
function xtest.assertError(fun, ...)
  local result = { pcall(fun, ...) }
  if result[1] then fail(result[2], "'function throws error'") end
  return unpack(result, 2)
end

xtest.assertNotOk = xtest.assertError
xtest.assertNotError = xtest.assertOk

-- Computercraft helper assertions

---Asserts that the code is running in CC
function xtest.assertCC()
  if not _CC_DEFAULT_SETTINGS then fail("Not running in CC", "'Running in CC'") end
end

---Asserts that the code is running on a turtle
function xtest.assertTurtle()
  if not turtle then fail("Not running on turtle", "'turtle'") end
end

---Asserts that the code is running on a Turtle
function xtest.assertPocket()
  if not pocket then fail("Not running on pocket computer", "'pocket computer'") end
end

---Asserts that the code is running on a normal computer
function xtest.assertComputer()
  if pocket or turtle then fail("Not running on a normal computer", "'computer'") end
end

---Asserts that the code is running on an advanced computer
function xtest.assertAdvanced()
  if not shell.openTab then fail("Not running on advanced computer", "'advanced computer'") end
end

---Asserts that an item is in the inventory
---@param item string
---@return number index
function xtest.assertHasItem(item)
  for i = 1, 16 do
    turtle.select(i)
    local detail = turtle.getItemDetail()
    if detail then
      if detail.name == item then
        return i
      end
    end
  end
  fail("No item " .. item .. " in inventory", "'Has " .. item .. " in inventory'")
end

---Asserts that an item is in the inventory and has at least `count` of it
---@param item string
---@param count number
---@return number[] indexes
function xtest.assertHasItemCount(item, count)
  local indexes = {}
  for i = 1, 16 do
    turtle.select(i)
    local detail = turtle.getItemDetail()
    if detail then
      if detail.name == item then
        indexes[#indexes + 1] = i
        count = count - detail.count
        if count <= 0 then
          return indexes
        end
      end
    end
  end
  fail("No item " .. item .. " with count " .. count .. " in inventory",
    "'Has " .. count .. item .. "'s items in inventory'")
end

---Asserts that a peripheral is attached
---@param name string
function xtest.assertPeripheral(name)
  if not peripheral.find(name) then fail("Peripheral " .. name .. "is not attached", "'Peripheral  " .. name .. " '") end
end

---Asserts that a peripheral is attached on a side
---@param side "bottom" | "top" | "left" | "right" | "front" | "back"
function xtest.assertPeripheralOnSide(side)
  if not peripheral.isPresent(side) then
    fail("No peripheral on side" .. side .. "is attached", side .. " peripheral present'")
  end
end

---Asserts that rednet is open
function xtest.assertRednetIsOpen()
  if not rednet.isOpen() then fail("No connections on Rednet are currently open", "'rednet.isOpen()'") end
end

-- Helper functions

--- Creates a file to be used for testing
--- The file is located in the directory `xtestfiles` relative to the current working directory
---@param name string the name of the file
---@param contents? string the contents of the file
---@param preventReplace? boolean prevents overwriting an existing file's contents
---@return file*
function xtest.file(name, contents, preventReplace)
  pcall(mkdir, "xtestfiles")
  local f = assert(io.open("xtestfiles/" .. name, contents and "w+" or "r+"))
  local size = f:seek("end")
  if size == 0 then
    f:write("")
    f:flush()
  end
  f:seek("set")
  if not preventReplace and contents then
    f:write(contents)
    f:flush()
    f:seek("set")
  end
  return f
end

return xtest
