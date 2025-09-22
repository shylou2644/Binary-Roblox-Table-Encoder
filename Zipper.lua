local Zipper = {}

local FLOAT64 = 1
local STRING = 2
local DICTIONARY = 3
local PACKED_TABLE = 4
local TRUE = 5
local FALSE = 6
local NIL = 7
local POINTER = 8

local b_writef64 = buffer.writef64
local b_writeu16 = buffer.writeu16
local b_writeu8 = buffer.writeu8
local b_writestring = buffer.writestring

local b_readf64 = buffer.readf64
local b_readu16 = buffer.readu16
local b_readu8 = buffer.readu8
local b_readstring = buffer.readstring

Zipper.Pack = function(value)
	local encode
	
	local stream = buffer.create(4_000_000)
	local i_stream = 0
	
	local function isPackedArray(t)
		if type(t) ~= "table" then return false end
		local count = 0
		for k, _ in t do
			if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
				return false
			end
			count = count + 1
		end
		
		return count == #t
	end
	
	local function buildBlob(value, blob, blobPointers, seenValues)
		local linearArray = isPackedArray(value)
		
		if typeof(value) ~= "table" then
			if value == true or value == false or value == nil or blobPointers[value] then
				return
			end
			
			if seenValues[value] then
				local blobIndex = #blob + 1
				blob[blobIndex] = value
				blobPointers[value] = blobIndex
			else
				seenValues[value] = true
			end
			return
		end
		
		if seenValues[value] then
			error("recursive tables cannot be serialized")
		end
		
		seenValues[value] = true
		
		for i, v in value do
			if typeof(v) == "table" then
				buildBlob(v, blob, blobPointers, seenValues)
			else
				buildBlob(v, blob, blobPointers, seenValues)
			end
			
			if linearArray then
				continue
			end
			
			if typeof(i) ~= "table" then
				buildBlob(i, blob, blobPointers, seenValues)
			end
		end
	end

	local function encodeFloat64(value)
		b_writef64(stream, i_stream, value)
		i_stream += 8
	end

	local function encodeString(value)
		local len = #value
		if len > 65535 then
			error("string is too large to encode")
		end
		b_writeu16(stream, i_stream, len)
		b_writestring(stream, i_stream + 2, value)
		i_stream += len + 2
	end

	local function encodeDictionary(table, blobPointers)
		local entries = 0
		local headerIndex = i_stream
		i_stream += 2

		for index, value in table do
			encode(index, blobPointers)
			encode(value, blobPointers)

			entries += 1
		end
		
		b_writeu16(stream, headerIndex, entries)
	end
	
	local function encodePackedTable(table, blobPointers)
		local entries = 0
		local headerIndex = i_stream
		i_stream += 2

		for index, value in table do
			encode(value, blobPointers)
			entries += 1
		end

		b_writeu16(stream, headerIndex, entries)
	end
	
	encode = function(value, blobPointers)
		
		if blobPointers and value ~= true and value ~= false and value ~= nil then
			local pointer = blobPointers[value]
			if pointer then
				b_writeu8(stream, i_stream, POINTER)
				b_writeu16(stream, i_stream+1, pointer)
				i_stream += 3
				return
			end
		end
		
		if typeof(value) == "number" then
			b_writeu8(stream, i_stream, FLOAT64)
			i_stream += 1
			encodeFloat64(value)
		elseif typeof(value) == "string" then
			b_writeu8(stream, i_stream, STRING)
			i_stream += 1
			encodeString(value)
		elseif typeof(value) == "table" then
			if isPackedArray(value) then
				b_writeu8(stream, i_stream, PACKED_TABLE)
				i_stream += 1
				encodePackedTable(value, blobPointers)
			else
				b_writeu8(stream, i_stream, DICTIONARY)
				i_stream += 1
				encodeDictionary(value, blobPointers)
			end
		elseif value == true then
			b_writeu8(stream, i_stream, TRUE)
			i_stream += 1
		elseif value == false then
			b_writeu8(stream, i_stream, FALSE)
			i_stream += 1
		elseif typeof(value) ~= "nil" then
			error(`unable to serialize type {typeof(value)}`)
		else
			b_writeu8(stream, i_stream, NIL)
			i_stream += 1
		end
	end
	
	local blob, blobPointers = {}, {}
	buildBlob(value, blob, blobPointers, {})
	
	encode(blob)
	encode(value, blobPointers)
	
	local slice = buffer.create(i_stream)
	buffer.copy(slice, 0, stream, 0, i_stream)
	
	return slice
end

Zipper.Unpack = function(stream : buffer)
	local decode
	local i_stream = 0
	local blob
	
	local function decodeFloat64()
		local value = b_readf64(stream, i_stream)
		i_stream += 8
		return value
	end
	
	local function decodeString()
		local length = b_readu16(stream, i_stream)
		local value = b_readstring(stream, i_stream + 2, length)
		i_stream += length + 2
		return value
	end
	
	local function decodeDictionary()
		local length = b_readu16(stream, i_stream)
		i_stream += 2
		
		local dict = {}
		
		for i = 1, length do
			local index = decode()
			local value = decode()
			
			dict[index] = value
		end
		
		return dict
	end
	
	local function decodePackedTable()
		local length = b_readu16(stream, i_stream)
		i_stream += 2

		local _table = {}

		for i = 1, length do
			_table[#_table+1] = decode()
		end
		
		return _table
	end
	
	decode = function()
		local dataTypeId = b_readu8(stream, i_stream)
		i_stream += 1
		
		if dataTypeId == FLOAT64 then
			return decodeFloat64()
		elseif dataTypeId == STRING then
			return decodeString()
		elseif dataTypeId == DICTIONARY then
			return decodeDictionary()
		elseif dataTypeId == PACKED_TABLE then
			return decodePackedTable()
		elseif dataTypeId == TRUE then
			return true
		elseif dataTypeId == FALSE then
			return false
		elseif dataTypeId == NIL then
			return nil
		elseif dataTypeId == POINTER then
			local pointer = b_readu16(stream, i_stream)
			i_stream += 2
			return blob[pointer]
		end
	end
	
	blob = decode()
	
	return decode()
end

return Zipper
