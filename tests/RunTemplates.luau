--[[
	템플릿 조합 테스트를 실행하는 스크립트입니다.
]]

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")

local FileSystemUtils = require("../src/modules/FileSystemUtils")

local function normalizeSourcePath(source: string): string
	local normalized = source
	if normalized:sub(1, 1) == "@" then
		normalized = normalized:sub(2)
	end
	return normalized:gsub("\\", "/")
end

local function resolveRepoRoot(fileSystemUtils): string
	local source = debug.info(1, "s")
	if source == nil or source == "" then
		return "."
	end

	local scriptPath = normalizeSourcePath(source)
	local testsDir = fileSystemUtils.GetDirectoryName(scriptPath)
	if testsDir == "" then
		return "."
	end

	local repoRoot = fileSystemUtils.GetDirectoryName(testsDir)
	if repoRoot == "" then
		return "."
	end

	return repoRoot
end

local function serializeTemplateEntry(entry): (boolean, string?)
	if type(entry) == "string" then
		if entry == "" then
			return false, "Template name is empty."
		end
		return true, `"{entry}"`
	end

	if type(entry) ~= "table" then
		return false, "Template entry must be a string or table."
	end

	local name = entry.Name
	if type(name) ~= "string" or name == "" then
		return false, "Template entry Name is invalid."
	end

	local fields = { `Name = "{name}"` }
	local source = entry.Source
	if source ~= nil then
		if type(source) ~= "string" or source == "" then
			return false, "Template entry Source is invalid."
		end
		table.insert(fields, `Source = "{source}"`)
	end

	local enableScripts = entry.EnableScripts
	if enableScripts ~= nil then
		if type(enableScripts) ~= "boolean" then
			return false, "Template entry EnableScripts is invalid."
		end
		local value = if enableScripts then "true" else "false"
		table.insert(fields, `EnableScripts = {value}`)
	end

	return true, "{ " .. table.concat(fields, ", ") .. " }"
end

local function buildProjectConfigContent(templates: { [number]: any }): (boolean, string?)
	local serialized: { string } = {}
	for _, entry in templates do
		local okSerialize, valueOrErr = serializeTemplateEntry(entry)
		if not okSerialize then
			return false, valueOrErr
		end
		table.insert(serialized, valueOrErr)
	end
	return true, `Templates = [{table.concat(serialized, ", ")}]\n`
end

local function writeProjectConfig(path: string, templates: { [number]: any }, fileSystemUtils): boolean
	local okBuild, contentOrErr = buildProjectConfigContent(templates)
	if not okBuild or contentOrErr == nil then
		local detail = contentOrErr or "unknown"
		print(`[Error] Failed to build config content: {detail}`)
		return false
	end

	local content = contentOrErr
	local okWrite, err = pcall(function()
		FileSystem.writeFile(path, content)
	end)
	if not okWrite then
		print(`[Error] Failed to write config: {tostring(err)}`)
		return false
	end
	return true
end

local function buildTemplateLabel(templates: { [number]: any }): string
	local labels: { string } = {}
	for _, entry in templates do
		if type(entry) == "string" then
			table.insert(labels, entry)
		elseif type(entry) == "table" then
			local name = entry.Name
			if type(name) == "string" and name ~= "" then
				table.insert(labels, name)
			else
				table.insert(labels, "unknown")
			end
		else
			table.insert(labels, "unknown")
		end
	end

	if #labels == 0 then
		return "none"
	end

	return table.concat(labels, ", ")
end

local function runTestCase(
	caseName: string,
	templates: { [number]: any },
	applyScriptPath: string,
	tmpRoot: string,
	index: number,
	fileSystemUtils
): boolean
	local runId = tostring(os.time()) .. "-" .. tostring(index)
	local caseDirName = caseName .. "-" .. runId
	local caseRoot = fileSystemUtils.JoinPath(tmpRoot, caseDirName)
	fileSystemUtils.MakeDirectoryRecursive(caseRoot)

	local configPath = fileSystemUtils.JoinPath(caseRoot, "bakery_project_configs.toml")
	local okWrite = writeProjectConfig(configPath, templates, fileSystemUtils)
	if not okWrite then
		return false
	end

	local templateLabel = buildTemplateLabel(templates)
	print(`[Test] Running \"{caseName}\" with templates: {templateLabel}`)

	local okExec, resultOrErr = pcall(
		Process.exec,
		"lune",
		{ "run", applyScriptPath },
		{ capture = true, cwd = caseRoot }
	)
	if not okExec then
		print(`[Test] Failed to run lune: {tostring(resultOrErr)}`)
		return false
	end

	local result = resultOrErr
	if not result.ok then
		local stdout = result.stdout or ""
		local stderr = result.stderr or ""
		print(`[Test] Case \"{caseName}\" failed.`)
		if stdout ~= "" then
			print(`[Test] stdout: {stdout}`)
		end
		if stderr ~= "" then
			print(`[Test] stderr: {stderr}`)
		end
		return false
	end

	if result.stdout ~= nil and result.stdout ~= "" then
		print(result.stdout)
	end

	return true
end

local repoRoot = resolveRepoRoot(FileSystemUtils)
local testsRoot = FileSystemUtils.JoinPath(repoRoot, "tests")
local tmpRoot = FileSystemUtils.JoinPath(testsRoot, ".tmp")
FileSystemUtils.MakeDirectoryRecursive(tmpRoot)

local applyScriptPath = FileSystemUtils.JoinPath(testsRoot, "ApplyTemplates.luau")
if not FileSystem.isFile(applyScriptPath) then
	print(`[Error] Missing ApplyTemplates script at \"{applyScriptPath}\".`)
	Process.exit(1)
end

local testCases = {
	{
		Name = "base",
		Templates = { "base" },
	},
	{
		Name = "base-disable-scripts",
		Templates = { { Name = "base", EnableScripts = false } },
	},
	{
		Name = "base-disable-scripts-and-non-luau",
		Templates = { { Name = "base", EnableScripts = false }, "non-luau" },
	},
	{
		Name = "non-luau",
		Templates = { "base", "non-luau" },
	},
	{
		Name = "roblox-place",
		Templates = { "base", "roblox-place" },
	},
	{
		Name = "with-bakerywave",
		Templates = { "base", "with-bakerywave" },
	},
	{
		Name = "with-bakery-dev-handbook",
		Templates = { "base", "with-bakery-dev-handbook" },
	},
	{
		Name = "pesde-default-packages",
		Templates = { "base", "pesde-default-packages" },
	},
	{
		Name = "bakerywave-and-handbook",
		Templates = { "base", "with-bakerywave", "with-bakery-dev-handbook" },
	},
	{
		Name = "bakerywave-and-pesde",
		Templates = { "base", "with-bakerywave", "pesde-default-packages" },
	},
	{
		Name = "all-templates",
		Templates = {
			"base",
			"non-luau",
			"roblox-place",
			"with-bakerywave",
			"with-bakery-dev-handbook",
			"pesde-default-packages",
		},
	},
}

local failed = 0
for index, case in testCases do
	local ok = runTestCase(
		case.Name,
		case.Templates,
		applyScriptPath,
		tmpRoot,
		index,
		FileSystemUtils
	)
	if not ok then
		failed += 1
	end
end

if failed > 0 then
	print(`[Test] Failed cases: {failed}`)
	Process.exit(1)
end

print("[Test] All template cases passed.")
Process.exit(0)
