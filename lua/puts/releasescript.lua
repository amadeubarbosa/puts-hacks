local array = require "table"
local utils = require "puts.utils"

local repopath, name, version, output = ...

local out = assert(io.open(output, "w"))
local repository = assert(utils.loadrepo(repopath))

local desc = assert(repository.catalog[name.."-"..version], "desc not found")

local function confirmvalue(message, value)
	io.write(message,": [",value,"] ")
	local answer = io.read()
	if answer ~= "" then value = answer end
	return value
end

local function versiononsvn(version)
	local res = {}
	local pos = 1
	repeat
		local first, last = string.find(version, "%d+%.", pos)
		if first ~= nil then
			res[#res+1] = string.format("%02d", tonumber(string.sub(version, first, last)))
			pos = last+1
		else
			break
		end
	until false
	local first, last = string.find(version, "%d+", pos)
	if first ~= nil then
		res[#res+1] = string.format("%02d", tonumber(string.sub(version, first, last)))
		pos = last+1
	end
	return array.concat(res, "_")..string.sub(version, pos)
end

local function replacefield(contents, field, value)
	return assert(string.gsub(contents,
		field.."%s*=%s*[^\n]+\n",
		field.." = "..value.."\n"))
end

local function makenewdesc(desc, version, url, deps)
	local file = assert(io.open(repopath.."/"..desc.name.."-"..desc.version..".desc"))
	local contents = file:read("*a")
	file:close()
	contents = replacefield(contents, "version", '"'..version..'"')
	if url ~= nil then
		contents = replacefield(contents, "url", 'SVNREPURL.."'..string.gsub(url, "^http://subversion%.tecgraf%.puc%-rio%.br/engdist", "")..'"')
	else
		local supername = utils.breakid(desc.subpackage_of)
		local superver = deps[supername]
		if superver == version then
			replacement = '"'..supername..' == "..version'
		else
			replacement = '"'..supername..' == '..superver..'"'
		end
		contents = replacefield(contents, 'subpackage_of', replacement)
		deps[supername] = nil
	end
	contents = assert(string.gsub(contents, "dependencies%s*=%s*(%b{})", function (depsdesc)
		return "dependencies = "..assert(string.gsub(depsdesc, '"(.-)%s*==%s*.-",', function (name)
			local ver = deps[name]
			if ver ~= nil then
				deps[name] = nil
				return '"'..name..' == '..ver..'",'
			end
		end))
	end))
	if next(deps) ~= nil then
		error("dependency '"..next(deps).."' of "..desc.name.." was not replaced!")
	end
	local newfile = repopath.."/"..desc.name.."-"..version..".desc"
	local file = io.open(newfile, "r")
	if file ~= nil then
		file:close()
		error("descriptor '"..newfile.."' already exists!")
	end
	local file = assert(io.open(newfile, "w"))
	file:write(contents)
	file:close()
end

local function geturl(desc)
	local url = desc.url
	if url == nil and desc.subpackage_of ~= nil then
		local name, version = utils.breakid(desc.subpackage_of)
		local found = repository.catalog[name.."-"..version]
		if found ~= nil then
			url = found.url
		end
	end
	return url
end

local function checkversion(name, version, history)
	if string.match(version, "snapshot$") then
		local id = name.."-"..version
		if history == nil then history = {} end
		if history[id] == nil then
			local desc = repository.catalog[id]
			for otherid, otherdesc in pairs(repository.catalog) do
				local otherurl = geturl(otherdesc)
				if otherdesc.name == name
				and string.find(otherdesc.version, "snapshot$") == nil
				and otherdesc.version ~= version
				and otherurl ~= nil then
					local svncmd = "svn diff --summarize "..geturl(desc).." "..otherurl
					local diff = assert(io.popen(svncmd):read("*a"))
					if diff == "" then
						if string.find(confirmvalue(otherid.." uses the same SVN repository of "..id..". Use it instead?", "yes"), "y") then
							history[id] = otherdesc.version
							return history[id]
						end
					end
				end
			end
			local newdeps = {}
			for depid, info in pairs(repository.dependencies[id]) do
				newdeps[info.name] = checkversion(info.name, info.version, history)
			end
			print("Current release descriptos of "..name)
			os.execute("ls -1 "..repopath.."/"..name.."*.desc")
			local newver
			for i = 0, 1/0 do
				newver = string.gsub(version, "snapshot$", "."..i)
				if repository.catalog[name.."-"..newver] == nil then
					break
				end
			end
			while true do
				local selected = confirmvalue("Enter the release for "..id, newver)
				local otherdesc = repository.catalog[name.."-"..selected]
				if otherdesc ~= nil then
					print("Exisiting release "..name.."-"..selected.." has the following differences:")
					local url = geturl(desc)
					local otherurl = geturl(otherdesc)
					local svncmd = "svn mergeinfo --show-revs=eligible "..url.." "..otherurl
					local revs = {}
					for rev in string.gmatch(assert(io.popen(svncmd):read("*a")), "r(%d+)") do
						revs[#revs+1] = rev
					end
					for index, rev in ipairs(revs) do
						os.execute("svn log -r"..rev.." "..url)
						local msg = "Show differences ("..index.."/"..#revs..")? (yes|no|stop)"
						local asw = confirmvalue(msg, "no")
						if string.find(asw, "s") ~= nil then
							break
						elseif string.find(asw, "y") ~= nil then
							os.execute("svn diff -c"..rev.." "..url)
						end
					end
					local msg = "Use this release anyway?"
					if string.find(confirmvalue(msg, "no"), "y") ~= nil then
						history[id] = selected
						return history[id]
					end
				else
					newver = selected
					break
				end
			end
			local url = desc.url
			if url ~= nil then
				local base = string.match(url, "(.-)/trunk$")
				          or string.match(url, "(.-)/branches/")
				local tagsurl = base.."/tags/"
				print("Current release tags of "..name)
				os.execute("svn list "..tagsurl)
				newsvn = versiononsvn(newver)
				newsvn = confirmvalue("Enter the new tag for "..name.."-"..newver, newsvn)
				out:write("svn copy -m 'Relase tag of version ",newver,"' \\\n  ",url," \\\n  ",tagsurl..newsvn,"\n")
				url = tagsurl..newsvn
			end
			makenewdesc(desc, newver, url, newdeps)
			history[id] = newver
		end
		return history[id]
	end
end

checkversion(name, version)
