--[[
	템플릿 설치를 테스트 환경에서 실행하는 스크립트입니다.
]]

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")

local Config = require("../src/cores/Config")
local FileSystemUtils = require("../src/cores/FileSystemUtils")
local Installer = require("../src/cores/Installer")
local ManagedBlock = require("../src/cores/ManagedBlock")
local TomlParser = require("../src/cores/TomlParser")

local function normalizeSourcePath(source: string): string
	local normalized = source
	if normalized:sub(1, 1) == "@" then
		normalized = normalized:sub(2)
	end
	return normalized:gsub("\\", "/")
end

local function isAbsolutePath(path: string): boolean
	if path:sub(1, 1) == "/" then
		return true
	end
	if path:match("^[A-Za-z]:[\\/]") then
		return true
	end
	return false
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

local function removeDirectoryRecursive(path: string, fileSystemUtils): boolean
	if not FileSystem.isDir(path) then
		return true
	end

	local okRead, entriesOrErr = pcall(FileSystem.readDir, path)
	if not okRead or entriesOrErr == nil then
		local detail = tostring(entriesOrErr)
		print(`[Error] Failed to read directory "{path}": {detail}`)
		return false
	end

	for _, entryName in entriesOrErr do
		local entryPath = fileSystemUtils.JoinPath(path, entryName)
		if FileSystem.isDir(entryPath) then
			local okRemoveChild = removeDirectoryRecursive(entryPath, fileSystemUtils)
			if not okRemoveChild then
				return false
			end
		else
			local okRemoveFile, err = pcall(FileSystem.removeFile, entryPath)
			if not okRemoveFile then
				print(`[Error] Failed to remove file "{entryPath}": {tostring(err)}`)
				return false
			end
		end
	end

	local okRemoveDir, err = pcall(FileSystem.removeDir, path)
	if not okRemoveDir then
		print(`[Error] Failed to remove directory "{path}": {tostring(err)}`)
		return false
	end

	return true
end

local function printInstallError(installError)
	local codeLabel = installError.Code or "Unknown"
	print(`[Error] Install failed ({codeLabel}).`)

	local pathLabel = installError.Path
	if pathLabel ~= nil and pathLabel ~= "" then
		print(`[Error] Path: {pathLabel}`)
	end

	local templateName = installError.TemplateName
	if templateName ~= nil and templateName ~= "" then
		print(`[Error] Template: {templateName}`)
	end

	local detail = installError.Detail
	if detail ~= nil and detail ~= "" then
		print(`[Error] Detail: {detail}`)
	end

	local lineLabel = installError.Line
	if lineLabel ~= nil then
		print(`[Error] Line: {lineLabel}`)
	end

	local lineText = installError.LineText
	if lineText ~= nil and lineText ~= "" then
		print(`[Error] LineText: {lineText}`)
	end
end

local function hasTemplate(templates, name: string): boolean
	if type(templates) ~= "table" then
		return false
	end

	for _, entry in templates do
		if type(entry) == "string" then
			if entry == name then
				return true
			end
		elseif type(entry) == "table" then
			if entry.Name == name then
				return true
			end
		end
	end

	return false
end

local function isTemplateScriptsDisabled(templates, name: string): boolean
	if type(templates) ~= "table" then
		return false
	end

	for _, entry in templates do
		if type(entry) == "table" and entry.Name == name and entry.EnableScripts == false then
			return true
		end
	end

	return false
end

local function hasTemplateName(templateNames: { string }, name: string): boolean
	for _, templateName in templateNames do
		if templateName == name then
			return true
		end
	end

	return false
end

local function runWorker(): number
	local okConfig, configData = TomlParser.ReadFile(Config.ProjectConfigFileName)
	if not okConfig then
		print("[Error] Missing sb_setup_configs.toml for test run.")
		return 1
	end

	local okInstall, installResult =
		Installer.Install(Config, FileSystemUtils, TomlParser, ManagedBlock)
	if not okInstall then
		printInstallError(installResult)
		return 1
	end

	local templateNames = installResult.TemplateNames or {}
	local templateLabel = "none"
	if #templateNames > 0 then
		templateLabel = table.concat(templateNames, ", ")
	end
	print(`[Test] Templates applied: {templateLabel}`)

	if not hasTemplateName(templateNames, "base") then
		print('[Error] Expected base template to be applied automatically.')
		return 1
	end

	local pesdePackages = installResult.PesdePackages or {}
	if #pesdePackages > 0 then
		print(`[Test] Pesde packages: {#pesdePackages}`)
	end

	local scripts = installResult.Scripts or {}
	if #scripts > 0 then
		print(`[Test] Setup scripts: {#scripts}`)
	end
	if not FileSystem.isFile(".gitignore") then
		print("[Error] Expected .gitignore but it was not created.")
		return 1
	end
	if FileSystem.isFile("template.gitignore") then
		print("[Error] template.gitignore should not be copied to project root.")
		return 1
	end

	if isTemplateScriptsDisabled(configData.Templates, "base")
		and not hasTemplate(configData.Templates, "pesde-default-packages") then
		if #scripts > 0 then
			print("[Error] Expected setup scripts to be disabled for base template.")
			return 1
		end
	end

	local submodules = installResult.Submodules or {}
	if #submodules > 0 then
		print(`[Test] Submodules: {#submodules}`)
	end

	return 0
end

local function runLauncher(): number
	local repoRoot = resolveRepoRoot(FileSystemUtils)
	local tmpRoot = FileSystemUtils.JoinPath(repoRoot, "tests/.tmp")
	FileSystemUtils.MakeDirectoryRecursive(tmpRoot)

	local runId = tostring(os.time()) .. "-apply-templates"
	local caseRoot = FileSystemUtils.JoinPath(tmpRoot, runId)
	FileSystemUtils.MakeDirectoryRecursive(caseRoot)

	local sourceConfigPath = FileSystemUtils.JoinPath(repoRoot, Config.ProjectConfigFileName)
	if not FileSystem.isFile(sourceConfigPath) then
		print('[Error] Missing sb_setup_configs.toml for test run.')
		removeDirectoryRecursive(caseRoot, FileSystemUtils)
		return 1
	end

	local destinationConfigPath = FileSystemUtils.JoinPath(caseRoot, Config.ProjectConfigFileName)
	local okCopyConfig, copyConfigErr = pcall(function()
		FileSystemUtils.CopyFile(sourceConfigPath, destinationConfigPath)
	end)
	if not okCopyConfig then
		print(`[Error] Failed to copy test config: {tostring(copyConfigErr)}`)
		removeDirectoryRecursive(caseRoot, FileSystemUtils)
		return 1
	end

	local source = debug.info(1, "s")
	local scriptPath = if type(source) == "string" then normalizeSourcePath(source) else ""
	if scriptPath == "" then
		scriptPath = "tests/ApplyTemplates.luau"
	end
	if not isAbsolutePath(scriptPath) then
		scriptPath = FileSystemUtils.JoinPath(repoRoot, scriptPath)
	end

	local okExec, resultOrErr = pcall(
		Process.exec,
		"lune",
		{ "run", scriptPath, "--worker" },
		{ capture = true, cwd = caseRoot }
	)
	if not okExec then
		print(`[Error] Failed to run apply test worker: {tostring(resultOrErr)}`)
		removeDirectoryRecursive(caseRoot, FileSystemUtils)
		return 1
	end

	local result = resultOrErr
	local stdout = result.stdout or ""
	if stdout ~= "" then
		print(stdout)
	end

	local stderr = result.stderr or ""
	if stderr ~= "" then
		print(stderr)
	end

	local exitCode = if result.ok then 0 else 1
	local okCleanup = removeDirectoryRecursive(caseRoot, FileSystemUtils)
	if not okCleanup then
		return 1
	end

	return exitCode
end

if Process.args[1] == "--worker" then
	Process.exit(runWorker())
end

Process.exit(runLauncher())
