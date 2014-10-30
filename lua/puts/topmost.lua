local utils = require "puts.utils"

local repopath = ...
local repository = assert(utils.loadrepo(repopath))
local topmost = {}

print("Topmost Packages:")
for id in pairs(repository.catalog) do
	if rawget(repository.referees, id) == nil then
		print("  "..id)
	end
end
