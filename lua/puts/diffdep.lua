local array = require "table"
local utils = require "puts.utils"

local repopath, oldid, newid = ...

local repository = assert(utils.loadrepo(repopath))

local olddesc = assert(repository.catalog[oldid], "old desc not found")
local newdesc = assert(repository.catalog[newid], "new desc not found")

local function depmap(deps)
	local map = {}
	for depid, info in pairs(deps) do
		map[info.name] = repository.catalog[depid]
	end
	return map
end

local function geturl(desc)
	return desc.url or repository.catalog[desc.subpackage_of:gsub("%s*[=<>!~]+%s*", "-")].url
end


local olddeps = depmap(repository.dependencies[oldid])
local newdeps = depmap(repository.dependencies[newid])

for name, olddep in pairs(olddeps) do
	local newdep = newdeps[name]
	local svncmd = "svn mergeinfo --show-revs=eligible "..geturl(newdep).." "..geturl(olddep)
	local eligible = assert(io.popen(svncmd):read("*a"))
	if eligible == "" and olddep.version ~= newdep.version then
		print("dependency "..name.." is the same for both versions")
	end
end