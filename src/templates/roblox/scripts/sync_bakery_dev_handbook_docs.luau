--[[
	bakery-dev-handbook roblox 문서를 스킬 레퍼런스로 동기화하는 스크립트입니다.
]]

local FileSystem = require("@lune/fs")
local Process = require("@lune/process")

local HANDBOOK_REPO_URL = "https://github.com/StoryBakery/bakery-dev-handbook"
local HANDBOOK_REF = "main"
local HANDBOOK_ROOT = ".agents/skills/roblox-scripting/references/bakery-dev-handbook"
local SKILL_GITIGNORE_PATH = ".agents/skills/roblox-scripting/.gitignore"
local SKILL_GITIGNORE_RULE = "/references/bakery-dev-handbook/"
local GUIDE_RELATIVE_PATH = "docs/roblox"
local GUIDE_ROOT = HANDBOOK_ROOT .. "/" .. GUIDE_RELATIVE_PATH

local function joinPath(a: string, b: string): string
	if a == "" or a == "." then
		return b
	end
	if b == "" or b == "." then
		return a
	end
	if a:sub(-1) == "/" then
		return a .. b
	end
	return a .. "/" .. b
end

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

local function runGit(args: { string }, cwd: string?): (boolean, string)
	local options = { capture = true }
	if cwd ~= nil and cwd ~= "" then
		options.cwd = cwd
	end

	local okExec, resultOrErr = pcall(Process.exec, "git", args, options)
	if not okExec then
		return false, tostring(resultOrErr)
	end

	local result = resultOrErr
	if result.ok then
		return true, ""
	end

	local stderr = result.stderr or ""
	if stderr ~= "" then
		return false, stderr
	end

	local stdout = result.stdout or ""
	if stdout ~= "" then
		return false, stdout
	end

	return false, "unknown error"
end

local function hasGit(): boolean
	local okExec, resultOrErr = pcall(Process.exec, "git", { "--version" }, { capture = true })
	if not okExec then
		return false
	end

	local result = resultOrErr
	return result.ok == true
end

local function ensureSparseCheckoutPath(): boolean
	local okInit, initError = runGit({ "sparse-checkout", "init", "--cone" }, HANDBOOK_ROOT)
	if not okInit then
		print(`[Setup] Sparse-checkout is not available. Keeping current checkout: {initError}`)
		return false
	end

	local okSet, setError = runGit({ "sparse-checkout", "set", GUIDE_RELATIVE_PATH }, HANDBOOK_ROOT)
	if not okSet then
		print(`[Setup] Failed to set sparse-checkout path "{GUIDE_RELATIVE_PATH}": {setError}`)
		return false
	end

	return true
end

local function cloneHandbook(): (boolean, string)
	local parentDirectory = getDirectoryName(HANDBOOK_ROOT)
	if parentDirectory ~= "" then
		makeDirectoryRecursive(parentDirectory)
	end

	local okSparseClone, sparseCloneError = runGit({
		"clone",
		"--depth",
		"1",
		"--filter=blob:none",
		"--sparse",
		"--branch",
		HANDBOOK_REF,
		HANDBOOK_REPO_URL,
		HANDBOOK_ROOT,
	}, nil)
	if okSparseClone then
		local okSparseSet, sparseSetError =
			runGit({ "sparse-checkout", "set", GUIDE_RELATIVE_PATH }, HANDBOOK_ROOT)
		if not okSparseSet then
			return false, sparseSetError
		end
		return true, ""
	end

	print(`[Setup] Sparse clone failed. Falling back to regular clone: {sparseCloneError}`)
	local okClone, cloneError = runGit({
		"clone",
		"--depth",
		"1",
		"--branch",
		HANDBOOK_REF,
		HANDBOOK_REPO_URL,
		HANDBOOK_ROOT,
	}, nil)
	if not okClone then
		return false, cloneError
	end

	ensureSparseCheckoutPath()
	return true, ""
end

local function updateHandbook(): (boolean, string)
	ensureSparseCheckoutPath()
	return runGit({ "pull", "--ff-only", "origin", HANDBOOK_REF }, HANDBOOK_ROOT)
end

local function ensureSkillGitignore(): boolean
	local parentDirectory = getDirectoryName(SKILL_GITIGNORE_PATH)
	if parentDirectory ~= "" then
		makeDirectoryRecursive(parentDirectory)
	end

	local content = ""
	if FileSystem.isFile(SKILL_GITIGNORE_PATH) then
		local okRead, contentOrErr = pcall(FileSystem.readFile, SKILL_GITIGNORE_PATH)
		if not okRead then
			print(`[Setup] Failed to read "{SKILL_GITIGNORE_PATH}": {tostring(contentOrErr)}`)
			return false
		end
		content = contentOrErr
	end

	if content:find(SKILL_GITIGNORE_RULE, 1, true) then
		return true
	end

	if content ~= "" and content:sub(-1) ~= "\n" then
		content ..= "\n"
	end
	content ..= SKILL_GITIGNORE_RULE .. "\n"

	local okWrite, writeErr = pcall(function()
		FileSystem.writeFile(SKILL_GITIGNORE_PATH, content)
	end)
	if not okWrite then
		print(`[Setup] Failed to write "{SKILL_GITIGNORE_PATH}": {tostring(writeErr)}`)
		return false
	end

	return true
end

if not hasGit() then
	print("[Setup] Git is not available. Skipping bakery-dev-handbook sync.")
	Process.exit(0)
end

if not ensureSkillGitignore() then
	Process.exit(0)
end

if FileSystem.isFile(HANDBOOK_ROOT) then
	print(`[Setup] Failed to sync bakery-dev-handbook. "{HANDBOOK_ROOT}" is a file.`)
	Process.exit(0)
end

if FileSystem.isDir(HANDBOOK_ROOT) then
	if not FileSystem.isDir(joinPath(HANDBOOK_ROOT, ".git")) then
		print(`[Setup] Skipped bakery-dev-handbook sync. "{HANDBOOK_ROOT}" is not a Git repository.`)
		Process.exit(0)
	end

	print("[Setup] Updating bakery-dev-handbook docs.")
	local okUpdate, updateError = updateHandbook()
	if not okUpdate then
		print(`[Setup] Failed to update bakery-dev-handbook docs: {updateError}`)
		Process.exit(0)
	end

	print("[Setup] Updated bakery-dev-handbook docs.")
else
	print("[Setup] Cloning bakery-dev-handbook docs.")
	local okClone, cloneError = cloneHandbook()
	if not okClone then
		print(`[Setup] Failed to clone bakery-dev-handbook docs: {cloneError}`)
		Process.exit(0)
	end

	print("[Setup] Cloned bakery-dev-handbook docs.")
end

if FileSystem.isDir(GUIDE_ROOT) then
	print("[Setup] bakery-dev-handbook roblox references are ready.")
else
	print("[Setup] bakery-dev-handbook repository is synced, but roblox docs were not found.")
end

Process.exit(0)
