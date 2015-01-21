local array = require "table"
local utils = require "puts.utils"

local repopath, outpath = ...

local repository = assert(utils.loadrepo(repopath))
local buildout = assert(io.open("build_"..outpath..".bat", "w"))
local downout = assert(io.open("download_"..outpath..".bat", "w"))

buildout:write[[
@echo off

set TECMAKEPLAT=%1
set BUILDDIR=%2

if "%TECMAKEPLAT%"=="" (
	echo Missing argument! Please provide the compilation method.
	echo Ex: vc9, dll9, vc10 ...
	goto USAGE
)
if "%BUILDDIR%"=="" (
	echo Missing argument! Please provide the build directory
	goto USAGE
)

]]

downout:write[[
@echo off

set BUILDDIR=%1

if "%BUILDDIR%"=="" (
	echo Missing argument! Please provide the build directory
	goto USAGE
)
]]

local function outpackbuild(id, built)
	local desc = assert(repository.catalog[id], "unknown package: "..id)
	local dirs = {[desc.name] = "../../"..id}
	local deps = rawget(repository.dependencies, id)
	if deps ~= nil then
		for dep, info in pairs(deps) do
			dirs[info.name] = "../../"..outpackbuild(dep, built)
		end
	end
	local dir = built[id]
	if dir == nil then
		dir = desc.subpackage_of
		if dir == nil then
			dir = id
		else
			local name, version = utils.breakid(dir)
			dir = name.."-"..version
		end
		local url = desc.url
		if url ~= nil then
			if url:match("^git") then
				downout:write("git clone "..url.." %BUILDDIR%\\"..id.."\n")
			elseif url:match("^https?://subversion%.tecgraf%.puc%-rio%.br/engdist") then
				downout:write("svn co "..url.." %BUILDDIR%\\"..id.."\n")
			end
		end
		local builddesc = desc.build
		if builddesc ~= nil and builddesc.type == "tecmake" then
			local vars = ""
			local varlist = builddesc.variables
			if varlist ~= nil then
				local list = {}
				for name, value in pairs(varlist) do
					list[#list+1] = name.."="..value:gsub("%%directory%(([^)]+)%)%%", dirs)
				end
				if #list > 0 then vars = '"'..array.concat(list, '" "')..'" ' end
			end
			local tecmf = builddesc.Windows or builddesc.mf
			buildout:write('cd %BUILDDIR%\\'..dir..'\\'..(builddesc.src or "src").."\n")
			buildout:write('if %ERRORLEVEL% neq 0 ( goto END )\n')
			if tecmf == nil then
				buildout:write('call tecmake %TECMAKEPLAT% '..vars..'"NO_DEPEND=Yes" %3\n')
				buildout:write('if %ERRORLEVEL% neq 0 ( goto END )\n\n')
			else
				for _, mf in ipairs(tecmf) do
					buildout:write('call tecmake %TECMAKEPLAT% '..vars..'"NO_DEPEND=Yes" "MF='..mf:gsub(' ', '" "')..'" %3\n')
					buildout:write('if %ERRORLEVEL% neq 0 ( goto END )\n\n')
				end
			end
		else
			print("WARN: no tecmake build info for '"..id.."'")
		end
		built[id] = dir
	end
	return dir
end

local built = {}
for index = 3, select("#", ...) do
	outpackbuild(select(index, ...), built)
end

buildout:write([[
goto END

:USAGE

echo Ex: ]]..outpath..[[.bat dll10 C:\Temp\OpenBus\Build

:END

cd %~dp0
exit /B
]])

downout:write([[
goto END

:USAGE

echo Ex: ]]..outpath..[[.bat C:\Temp\OpenBus\Build

:END

cd %~dp0
exit /B
]])

buildout:close()
downout:close()
