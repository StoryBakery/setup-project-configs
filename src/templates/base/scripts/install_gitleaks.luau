--[[
	gitleaks 설치를 시도하고 결과를 출력하는 스크립트입니다.
]]

local Process = require("@lune/process")

type InstallAttempt = {
	Name: string,
	Command: string,
	Args: { string },
}

local INSTALL_ATTEMPTS: { InstallAttempt } = {
	{
		Name = "go",
		Command = "go",
		Args = { "install", "github.com/gitleaks/gitleaks/v8@latest" },
	},
	{
		Name = "brew",
		Command = "brew",
		Args = { "install", "gitleaks" },
	},
	{
		Name = "scoop",
		Command = "scoop",
		Args = { "install", "gitleaks" },
	},
	{
		Name = "choco",
		Command = "choco",
		Args = { "install", "gitleaks", "-y" },
	},
	{
		Name = "winget",
		Command = "winget",
		Args = {
			"install",
			"--id",
			"Gitleaks.Gitleaks",
			"-e",
			"--accept-package-agreements",
			"--accept-source-agreements",
		},
	},
}

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

local function runInstallCommand(attempt: InstallAttempt): (boolean, string?)
	local okExec, resultOrErr = pcall(
		Process.exec,
		attempt.Command,
		attempt.Args,
		{ capture = true }
	)
	if not okExec then
		return false, tostring(resultOrErr)
	end

	local result = resultOrErr
	if not result.ok then
		return false, buildErrorMessage(result)
	end

	return true, nil
end

if isCommandAvailable("gitleaks") then
	print("[Setup] gitleaks is already installed.")
	Process.exit(0)
end

for _, attempt in INSTALL_ATTEMPTS do
	if isCommandAvailable(attempt.Command) then
		print(`[Setup] Installing gitleaks via {attempt.Name}.`)
		local okInstall, installError = runInstallCommand(attempt)
		if okInstall then
			if isCommandAvailable("gitleaks") then
				print(`[Setup] gitleaks installed via {attempt.Name}.`)
			else
				print(
					`[Setup] Install command finished via {attempt.Name}, but gitleaks is not on PATH yet.`
				)
			end
			Process.exit(0)
		end

		print(`[Setup] Failed to install gitleaks via {attempt.Name}: {installError}`)
	end
end

print("[Setup] Skipped gitleaks install. No supported package manager was found.")
print("[Setup] Install gitleaks manually if your project requires secret scanning.")
Process.exit(0)
