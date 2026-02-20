--[[
	템플릿 설정과 소스 경로, 템플릿 서브모듈 파일 이름을 관리하는 모듈입니다.
]]

local Config = {
	BaseTemplateName = "base",
	TemplatesRootName = "templates",
	ProjectConfigFileName = "sb_setup_configs.toml",
	TemplateConfigFileName = "template.toml",
	TemplateSubmoduleFileName = "template.gitmodules",
	TemplatePesdeFileName = "pesde-packages.toml",
	TemplateGitignoreFileName = "template.gitignore",
	TemplateScriptsFileName = "setup-scripts.toml",
}

return Config
