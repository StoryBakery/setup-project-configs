--[[
	프로젝트 Git hooks 경로를 설정하는 스크립트입니다.
]]

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")

local HOOKS_PATH = ".githooks"
local PRE_COMMIT_HOOK_PATH = HOOKS_PATH .. "/pre-commit"
local LOCAL_PRE_COMMIT_HOOK_PATH = HOOKS_PATH .. "/pre-commit.local"
local LEGACY_PRE_COMMIT_HOOK_PATH = ".git/hooks/pre-commit"

local function getDirectoryName(path: string): string
	return (path:match("^(.*)/[^/]+$")) or ""
end

local function makeDirectoryRecursive(path: string)
	if path == "" or path == "." then
		return
	end
	if FileSystem.isDir(path) then
		return
	end

	local parentPath = getDirectoryName(path)
	if parentPath ~= "" and not FileSystem.isDir(parentPath) then
		makeDirectoryRecursive(parentPath)
	end

	local okWrite = pcall(function()
		FileSystem.writeDir(path)
	end)
	if not okWrite and not FileSystem.isDir(path) then
		FileSystem.writeDir(path)
	end
end

local function isCommandAvailable(command: string): boolean
	local okExec, resultOrErr = pcall(Process.exec, command, { "--version" }, { capture = true })
	if not okExec then
		return false
	end

	local result = resultOrErr
	return result.ok == true
end

local function buildErrorMessage(result): string
	local stderr = result.stderr or ""
	if stderr ~= "" then
		return stderr
	end

	local stdout = result.stdout or ""
	if stdout ~= "" then
		return stdout
	end

	return "unknown error"
end

local function runGit(args: { string }): (boolean, string?)
	local okExec, resultOrErr = pcall(Process.exec, "git", args, { capture = true })
	if not okExec then
		return false, tostring(resultOrErr)
	end

	local result = resultOrErr
	if not result.ok then
		return false, buildErrorMessage(result)
	end

	return true, nil
end

local function copyFile(sourcePath: string, destinationPath: string): (boolean, string?)
	local okRead, contentOrErr = pcall(FileSystem.readFile, sourcePath)
	if not okRead then
		return false, tostring(contentOrErr)
	end

	local parentPath = getDirectoryName(destinationPath)
	if parentPath ~= "" then
		makeDirectoryRecursive(parentPath)
	end

	local okWrite, writeErr = pcall(function()
		FileSystem.writeFile(destinationPath, contentOrErr)
	end)
	if not okWrite then
		return false, tostring(writeErr)
	end

	return true, nil
end

local function isGitRepository(): boolean
	local okExec, resultOrErr = pcall(
		Process.exec,
		"git",
		{ "rev-parse", "--is-inside-work-tree" },
		{ capture = true }
	)
	if not okExec then
		return false
	end

	local result = resultOrErr
	if not result.ok then
		return false
	end

	local stdout = result.stdout or ""
	return stdout:find("true", 1, true) ~= nil
end

local function ensureHookIsExecutable(hookPath: string)
	if Process.env.OS == "Windows_NT" then
		return
	end

	if not isCommandAvailable("chmod") then
		return
	end

	local okExec, resultOrErr = pcall(
		Process.exec,
		"chmod",
		{ "+x", hookPath },
		{ capture = true }
	)
	if not okExec then
		print(`[Setup] Failed to mark "{hookPath}" as executable: {tostring(resultOrErr)}`)
		return
	end

	local result = resultOrErr
	if not result.ok then
		print(`[Setup] Failed to mark "{hookPath}" as executable: {buildErrorMessage(result)}`)
	end
end

local function migrateLegacyPreCommitHook()
	if not FileSystem.isFile(LEGACY_PRE_COMMIT_HOOK_PATH) then
		return
	end

	if FileSystem.isFile(LOCAL_PRE_COMMIT_HOOK_PATH) then
		ensureHookIsExecutable(LOCAL_PRE_COMMIT_HOOK_PATH)
		return
	end

	local okCopy, copyError = copyFile(LEGACY_PRE_COMMIT_HOOK_PATH, LOCAL_PRE_COMMIT_HOOK_PATH)
	if not okCopy then
		print(
			`[Setup] Failed to migrate legacy pre-commit hook "{LEGACY_PRE_COMMIT_HOOK_PATH}": {copyError}`
		)
		return
	end

	ensureHookIsExecutable(LOCAL_PRE_COMMIT_HOOK_PATH)
	print(
		`[Setup] Migrated legacy pre-commit hook to "{LOCAL_PRE_COMMIT_HOOK_PATH}".`
	)
end

if not isCommandAvailable("git") then
	print("[Setup] Git is not available. Skipping hook setup.")
	Process.exit(0)
end

if not isGitRepository() then
	print("[Setup] Not a Git repository. Skipping hook setup.")
	Process.exit(0)
end

if not FileSystem.isFile(PRE_COMMIT_HOOK_PATH) then
	print(`[Setup] Missing pre-commit hook "{PRE_COMMIT_HOOK_PATH}".`)
	Process.exit(0)
end

migrateLegacyPreCommitHook()

local okConfig, configError = runGit({ "config", "--local", "core.hooksPath", HOOKS_PATH })
if not okConfig then
	print(`[Setup] Failed to configure core.hooksPath: {configError}`)
	Process.exit(0)
end

ensureHookIsExecutable(PRE_COMMIT_HOOK_PATH)
if FileSystem.isFile(LOCAL_PRE_COMMIT_HOOK_PATH) then
	ensureHookIsExecutable(LOCAL_PRE_COMMIT_HOOK_PATH)
end

print(`[Setup] Git hooks path is configured: "{HOOKS_PATH}".`)
Process.exit(0)
