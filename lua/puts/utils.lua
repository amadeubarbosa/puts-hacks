local table = require "loop.table"
local lfs = require "lfs"

local envmeta = {
	__index = function(self, key)
		return _ENV[key] or ""
	end,
}
local function loaddesc(path)
	local env = setmetatable({SVNREPURL="http://subversion.tecgraf.puc-rio.br/engdist"}, envmeta)
	env.INSTALL = env
	env.config = env
	pcall(assert(loadfile(path, nil, env)))
	setmetatable(env, nil)
	env.INSTALL = nil
	env.config = nil
	return env
end

local function breakid(id)
	return id:match("^%s*([^=<>!~]-)%s*[=<>!~]+%s*(.-)%s*$")
end

local module = { breakid = breakid }

function module.loadrepo(repopath)
	local catalog = {}
	local referees = table.memoize(function () return {} end)
	local dependencies = table.memoize(function () return {} end)

	for file in lfs.dir(repopath) do
		if file:match("%.desc$") then
			local desc = loaddesc(repopath.."/"..file)
			local id = desc.name..'-'..desc.version
			if id..'.desc' == file then
				catalog[id] = desc
			else
				print("ERROR: wrong name or version: "..file)
			end
		end
	end

	for id, desc in pairs(catalog) do
		local deps = desc.dependencies or {}
		deps[#deps+1] = desc.subpackage_of
		for _, dep in ipairs(deps) do
			local name, version = breakid(dep)
			if name == nil then
				print("ERROR: illegal dependency on descritor '"..id.."': "..dep)
			else
				local depid = name.."-"..version
				if catalog[depid] == nil then
					print("ERROR: missing dependency on descritor '"..id.."': "..depid)
				end
				referees[depid][id] = true
				dependencies[id][depid] = {name=name,version=version}
			end
		end
	end

	return {
		catalog = catalog,
		referees = referees,
		dependencies = dependencies,
	}
end

return module
