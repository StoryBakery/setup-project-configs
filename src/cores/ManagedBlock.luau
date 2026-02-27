--[[
	매직패턴 블록을 병합하는 모듈입니다.
]]

local function trim(value: string): string
	return value:match("^%s*(.-)%s*$")
end

local function splitLines(text: string): { string }
	local normalized = text:gsub("\r\n", "\n")
	normalized = normalized:gsub("\r", "\n")
	if normalized == "" then
		return {}
	end

	local lines: { string } = {}
	local startIndex = 1

	while true do
		local nextIndex = normalized:find("\n", startIndex, true)
		if not nextIndex then
			table.insert(lines, normalized:sub(startIndex))
			break
		end

		table.insert(lines, normalized:sub(startIndex, nextIndex - 1))
		startIndex = nextIndex + 1
	end

	return lines
end

local function cleanupMarkerPayload(payload: string): string
	local cleaned = trim(payload)
	return trim(cleaned)
end

local function parseMarker(line: string, marker: string): (string?, string?)
	local loweredLine = line:lower()
	local markerTag = marker:lower() .. " "
	local startIndex = loweredLine:find(markerTag, 1, true)
	if startIndex == nil then
		return nil, nil
	end

	local payload = cleanupMarkerPayload(line:sub(startIndex + #markerTag))
	local blockId, remainder = payload:match("^([^%s]+)%s*(.*)$")
	if blockId == nil then
		return nil, nil
	end

	blockId = trim(blockId)
	if blockId == "" then
		return nil, nil
	end

	local lowerBlockId = blockId:lower()
	if not lowerBlockId:find("sb%-setup:", 1, false) then
		return nil, nil
	end

	local mode = remainder:match("mode%s*:%s*([^%s%]]+)")
	if mode == nil then
		mode = remainder:match("mode%s*=%s*([^%s%]]+)")
	end

	if mode ~= nil then
		mode = trim(mode)
		if mode == "" then
			mode = nil
		end
	end

	return blockId, mode
end

local function parseBlocks(lines: { string })
	local blocksById: { [string]: any } = {}
	local order: { string } = {}
	local index = 1

	while index <= #lines do
		local startLine = lines[index]
		local blockId, mode = parseMarker(startLine, "BEGIN")
		if blockId then
			local contentLines: { string } = {}
			local endIndex = nil
			local scanIndex = index + 1

			while scanIndex <= #lines do
				local endId = parseMarker(lines[scanIndex], "END")
				if endId == blockId then
					endIndex = scanIndex
					break
				end
				table.insert(contentLines, lines[scanIndex])
				scanIndex += 1
			end

			if endIndex then
				if blocksById[blockId] == nil then
					blocksById[blockId] = {
						Id = blockId,
						StartIndex = index,
						EndIndex = endIndex,
						StartLine = startLine,
						EndLine = lines[endIndex],
						Lines = contentLines,
						Mode = mode,
					}
					table.insert(order, blockId)
				end
				index = endIndex + 1
			else
				index += 1
			end
		else
			index += 1
		end
	end

	return blocksById, order
end

local function endsWithLines(source: { string }, suffix: { string }): boolean
	if #suffix == 0 then
		return true
	end
	if #source < #suffix then
		return false
	end

	local offset = #source - #suffix
	for i = 1, #suffix do
		if source[offset + i] ~= suffix[i] then
			return false
		end
	end

	return true
end

local function parseTemplate(text: string)
	local lines = splitLines(text)
	local blocksById, order = parseBlocks(lines)
	return {
		Lines = lines,
		Blocks = blocksById,
		Order = order,
		HasBlocks = #order > 0,
	}
end

local function merge(destinationText: string, templateInfo)
	local destinationLines = splitLines(destinationText)
	local destinationBlocks, _ = parseBlocks(destinationLines)

	local updates: { [string]: any } = {}
	for _, blockId in templateInfo.Order do
		local templateBlock = templateInfo.Blocks[blockId]
		local mode = templateBlock.Mode
		if mode ~= "append" and mode ~= "remove" then
			mode = "replace"
		end

		local destinationBlock = destinationBlocks[blockId]
		if mode == "remove" then
			if destinationBlock then
				updates[blockId] = { Action = "remove" }
			end
		elseif destinationBlock then
			local mergedLines: { string } = {}
			if mode == "append" then
				if endsWithLines(destinationBlock.Lines, templateBlock.Lines) then
					mergedLines = destinationBlock.Lines
				else
					for _, line in destinationBlock.Lines do
						table.insert(mergedLines, line)
					end
					for _, line in templateBlock.Lines do
						table.insert(mergedLines, line)
					end
				end
			else
				mergedLines = templateBlock.Lines
			end

			updates[blockId] = {
				Action = "update",
				Lines = mergedLines,
				StartLine = if mode == "append" then destinationBlock.StartLine else templateBlock.StartLine,
				EndLine = if mode == "append" then destinationBlock.EndLine else templateBlock.EndLine,
			}
		else
			updates[blockId] = {
				Action = "insert",
				Lines = templateBlock.Lines,
				StartLine = templateBlock.StartLine,
				EndLine = templateBlock.EndLine,
			}
		end
	end

	local blocksByStartIndex: { [number]: any } = {}
	for _, block in destinationBlocks do
		blocksByStartIndex[block.StartIndex] = block
	end

	local mergedLines: { string } = {}
	local index = 1
	while index <= #destinationLines do
		local block = blocksByStartIndex[index]
		if block then
			local update = updates[block.Id]
			if update and update.Action == "remove" then
				index = block.EndIndex + 1
			else
				local contentLines = block.Lines
				local startLine = block.StartLine
				local endLine = block.EndLine
				if update and update.Action == "update" then
					contentLines = update.Lines
					startLine = update.StartLine
					endLine = update.EndLine
				end

				table.insert(mergedLines, startLine)
				for _, line in contentLines do
					table.insert(mergedLines, line)
				end
				table.insert(mergedLines, endLine)
				index = block.EndIndex + 1
			end
		else
			table.insert(mergedLines, destinationLines[index])
			index += 1
		end
	end

	for _, blockId in templateInfo.Order do
		local update = updates[blockId]
		if update and update.Action == "insert" then
			table.insert(mergedLines, update.StartLine)
			for _, line in update.Lines do
				table.insert(mergedLines, line)
			end
			table.insert(mergedLines, update.EndLine)
		end
	end

	return table.concat(mergedLines, "\n")
end

local ManagedBlock = {
	ParseTemplate = parseTemplate,
	Merge = merge,
}

return ManagedBlock
