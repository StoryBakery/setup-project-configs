--[[
	프로젝트 pre-commit 훅을 설치하는 스크립트입니다.
]]

local Process = require("@lune/process")

type PreCommitCommand = {
	Command: string,
	Args: { string },
}

local function isCommandAvailable(command: string, args: { string }): boolean
	local okExec, resultOrErr = pcall(Process.exec, command, args, { capture = true })
	if not okExec then
		return false
	end

	local result = resultOrErr
	return result.ok == true
end

local function getCommandOutput(result): string
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

local function findPreCommitCommand(): PreCommitCommand?
	if isCommandAvailable("pre-commit", { "--version" }) then
		return {
			Command = "pre-commit",
			Args = {},
		}
	end

	if isCommandAvailable("py", { "-m", "pre_commit", "--version" }) then
		return {
			Command = "py",
			Args = { "-m", "pre_commit" },
		}
	end

	if isCommandAvailable("python", { "-m", "pre_commit", "--version" }) then
		return {
			Command = "python",
			Args = { "-m", "pre_commit" },
		}
	end

	if isCommandAvailable("python3", { "-m", "pre_commit", "--version" }) then
		return {
			Command = "python3",
			Args = { "-m", "pre_commit" },
		}
	end

	return nil
end

local function runPreCommit(commandInfo: PreCommitCommand, args: { string }): (boolean, string?)
	local commandArgs: { string } = {}
	for _, value in commandInfo.Args do
		table.insert(commandArgs, value)
	end

	for _, value in args do
		table.insert(commandArgs, value)
	end

	local okExec, resultOrErr =
		pcall(Process.exec, commandInfo.Command, commandArgs, { capture = true })
	if not okExec then
		return false, tostring(resultOrErr)
	end

	local result = resultOrErr
	if not result.ok then
		return false, getCommandOutput(result)
	end

	return true, nil
end

if not isCommandAvailable("git", { "--version" }) then
	print("[Setup] Git is not available. Skipping pre-commit hook installation.")
	Process.exit(0)
end

if not isGitRepository() then
	print("[Setup] Not a Git repository. Skipping pre-commit hook installation.")
	Process.exit(0)
end

local preCommitCommand = findPreCommitCommand()
if preCommitCommand == nil then
	print("[Setup] pre-commit is not installed. Skipping hook installation.")
	print("[Setup] Install: pipx install pre-commit")
	print("[Setup] or: py -m pip install --user pre-commit")
	Process.exit(0)
end

local okInstall, installError = runPreCommit(
	preCommitCommand,
	{ "install", "--install-hooks", "--hook-type", "pre-commit" }
)
if not okInstall then
	print(`[Setup] Failed to install pre-commit hook: {installError}`)
	Process.exit(0)
end

print("[Setup] pre-commit hook is installed.")
Process.exit(0)
