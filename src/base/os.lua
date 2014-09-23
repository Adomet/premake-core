--
-- os.lua
-- Additions to the OS namespace.
-- Copyright (c) 2002-2014 Jason Perkins and the Premake project
--


--
-- Add a path normalization step to the execution command to
-- replace special symbols and any scripted weirdness.
--

	premake.override(os, "execute", function(base, cmd)
		cmd = path.normalize(cmd)
		return base(cmd)
	end)


--
-- Same as os.execute(), but accepts string formatting arguments.
--

	function os.executef(cmd, ...)
		cmd = string.format(cmd, unpack(arg))
		return os.execute(cmd)
	end



--
-- Scan the well-known system locations for a particular library.
--

	local function parse_ld_so_conf(conf_file)
		-- Linux ldconfig file parser to find system library locations
		local first, last
		local dirs = { }
		for line in io.lines(conf_file) do
			-- ignore comments
			first = line:find("#", 1, true)
			if first ~= nil then
				line = line:sub(1, first - 1)
			end

			if line ~= "" then
				-- check for include files
				first, last = line:find("include%s+")
				if first ~= nil then
					-- found include glob
					local include_glob = line:sub(last + 1)
					local includes = os.matchfiles(include_glob)
					for _, v in ipairs(includes) do
						dirs = table.join(dirs, parse_ld_so_conf(v))
					end
				else
					-- found an actual ld path entry
					table.insert(dirs, line)
				end
			end
		end
		return dirs
	end

	function os.findlib(libname)
		local path, formats

		-- assemble a search path, depending on the platform
		if os.is("windows") then
			formats = { "%s.dll", "%s" }
			path = os.getenv("PATH")
		elseif os.is("haiku") then
			formats = { "lib%s.so", "%s.so" }
			path = os.getenv("LIBRARY_PATH")
		else
			if os.is("macosx") then
				formats = { "lib%s.dylib", "%s.dylib" }
				path = os.getenv("DYLD_LIBRARY_PATH")
			else
				formats = { "lib%s.so", "%s.so" }
				path = os.getenv("LD_LIBRARY_PATH") or ""

				for _, v in ipairs(parse_ld_so_conf("/etc/ld.so.conf")) do
					path = path .. ":" .. v
				end
			end

			table.insert(formats, "%s")
			path = path or ""
			if os.is64bit() then
				path = path .. ":/lib64:/usr/lib64/:usr/local/lib64"
			end
			path = path .. ":/lib:/usr/lib:/usr/local/lib"
		end

		for _, fmt in ipairs(formats) do
			local name = string.format(fmt, libname)
			local result = os.pathsearch(name, path)
			if result then return result end
		end
	end



--
-- Retrieve the current operating system ID string.
--

	function os.get()
		return _OPTIONS.os or _OS
	end



--
-- Check the current operating system; may be set with the /os command line flag.
--

	function os.is(id)
		return (os.get():lower() == id:lower())
	end



---
-- Determine if a directory exists on the file system, and that it is a
-- directory and not a file.
--
-- @param p
--    The path to check.
-- @return
--    True if a directory exists at the given path.
---

	premake.override(os, "isdir", function(base, p)
		p = path.normalize(p)
		return base(p)
	end)



---
-- Determine if a file exists on the file system, and that it is a
-- file and not a directory.
--
-- @param p
--    The path to check.
-- @return
--    True if a file exists at the given path.
---

	premake.override(os, "isfile", function(base, p)
		p = path.normalize(p)
		return base(p)
	end)



--
-- Determine if the current system is running a 64-bit architecture.
--

	local _is64bit

	local _64BitHostTypes = {
		"x86_64",
		"ia64",
		"amd64",
		"ppc64",
		"powerpc64",
		"sparc64"
	}

	function os.is64bit()
		-- This can be expensive to compute, so cache and reuse the response
		if _is64bit ~= nil then
			return _is64bit
		end

		_is64bit = false

		-- Call the native code implementation. If this returns true then
		-- we're 64-bit, otherwise do more checking locally
		if (os._is64bit()) then
			_is64bit = true
		else
			-- Identify the system
			local arch
			if _OS == "windows" then
				arch = os.getenv("PROCESSOR_ARCHITECTURE")
			elseif _OS == "macosx" then
				arch = os.outputof("echo $HOSTTYPE")
			else
				arch = os.outputof("uname -m")
			end

			-- Check our known 64-bit identifiers
			arch = arch:lower()
			for _, hosttype in ipairs(_64BitHostTypes) do
				if arch:find(hosttype) then
					_is64bit = true
				end
			end
		end

		return _is64bit
	end



---
-- Locate a file on one of Premake's search paths: 1) the --script command
-- line argument, 2) the PREMAKE_PATH environment variable, 3) relative to
-- the Premake executable.
--
-- @param ...
--    A list of file names for which to search. The first one discovered
--    is the one that will be returned.
-- @return
--    The path to file if found, or nil if not.
---

	function os.locate(...)
		local function find(fname)
			-- is this a direct path to a file?
			if os.isfile(fname) then
				return fname
			end

			-- find it on my paths
			local dir = os.pathsearch(fname, _OPTIONS["scripts"], os.getenv("PREMAKE_PATH"), path.getdirectory(_PREMAKE_COMMAND))
			if dir then
				return path.join(dir, fname)
			end
		end

		for i = 1, select("#",...) do
			local fname = select(i, ...)
			local result = find(fname)
			if result then
				return result
			end
		end
	end



---
-- Perform a wildcard search for files or directories.
--
-- @param mask
--    The file search pattern. Use "*" to match any part of a file or
--    directory name, "**" to recurse into subdirectories.
-- @param matchFiles
--    True to match against files, false to match directories.
-- @param excludeDirs
--    Lua Pattern.
--    If any encountered dir matches this pattern, it will be discarded (both from results and from recursive decent).
--    If it is nil, it will be set to "%..*", to keep backward compatibility.
--    To make it match all dirs, you need to pass un-matchable pattern; we use "a^" for this internally.
-- @param excludeFiles
--    Lua Pattern.
--    If any encountered file matches this pattern, it will be discarded from results.
--    If it is nil, it will be set to "a^" to match no files.
-- @return
--    A table containing the matched file or directory names.
---

	function os.match(mask, matchFiles, excludeDirs, excludeFiles)
		-- patch up exclude masks to default values
		excludeDirs  = excludeDirs  and excludeDirs  or "%..*"
		excludeFiles = excludeFiles and excludeFiles or "a^"

		-- Strip any extraneous weirdness from the mask to ensure a good
		-- match against the paths returned by the OS. I don't know if I've
		-- caught all the possibilities here yet; will add more as I go.

		mask = path.normalize(mask)

		-- strip off any leading directory information to find out
		-- where the search should take place

		local basedir = mask
		local starpos = mask:find("%*")
		if starpos then
			basedir = basedir:sub(1, starpos - 1)
		end
		basedir = path.getdirectory(basedir)
		if basedir == "." then
			basedir = ""
		end

		-- recurse into subdirectories?
		local recurse = mask:find("**", nil, true)

		-- convert mask to a Lua pattern
		mask = path.wildcards(mask)

		local result = {}

		local function matchwalker(basedir)
			local wildcard = path.join(basedir, "*")

			-- retrieve files from OS and test against mask
			local m = os.matchstart(wildcard)
			while os.matchnext(m) do
				local isfile = os.matchisfile(m)
				if (matchFiles and isfile) or (not matchFiles and not isfile) then
					local fname = os.matchname(m)
					if (isfile and not fname:match(excludeFiles)) or (not isfile and not fname:match(excludeDirs)) then
						fname = path.join(basedir, fname)
						if fname:match(mask) == fname then
							table.insert(result, fname)
						end
					end
				end
			end
			os.matchdone(m)

			-- check subdirectories
			if recurse then
				m = os.matchstart(wildcard)
				while os.matchnext(m) do
					if not os.matchisfile(m) then
						local dirname = os.matchname(m)
						-- always exclude phony dirs: . and ..
						if not (dirname == "." or dirname == ".." or dirname:match(excludeDirs)) then
							matchwalker(path.join(basedir, dirname))
						end
					end
				end
				os.matchdone(m)
			end
		end

		matchwalker(basedir)
		return result
	end


---
-- Perform a wildcard search for directories.
--
-- @param mask
--    The search pattern. Use "*" to match any part of a directory
--    name, "**" to recurse into subdirectories.
-- @return
--    A table containing the matched directory names.
---

	function os.matchdirs(mask)
		return os.match(mask, false, "%..*", nil)
	end


---
-- Perform a wildcard search for files.
--
-- @param mask
--    The search pattern. Use "*" to match any part of a file
--    name, "**" to recurse into subdirectories.
-- @return
--    A table containing the matched directory names.
---

	function os.matchfiles(mask)
		return os.match(mask, true, "%..*", nil)
	end


--
-- An overload of the os.mkdir() function, which will create any missing
-- subdirectories along the path.
--

	local builtin_mkdir = os.mkdir
	function os.mkdir(p)
		p = path.normalize(p)

		local dir = iif(p:startswith("/"), "/", "")
		for part in p:gmatch("[^/]+") do
			dir = dir .. part

			if (part ~= "" and not path.isabsolute(part) and not os.isdir(dir)) then
				local ok, err = builtin_mkdir(dir)
				if (not ok) then
					return nil, err
				end
			end

			dir = dir .. "/"
		end

		return true
	end


--
-- Run a shell command and return the output.
--

	function os.outputof(cmd)
		cmd = path.normalize(cmd)

		local pipe = io.popen(cmd)
		local result = pipe:read('*a')
		pipe:close()

		return result
	end


--
-- @brief An overloaded os.remove() that will be able to handle list of files,
--        as well as wildcards for files. Uses the syntax os.matchfiles() for
--        matching pattern wildcards.
--
-- @param f A file, a wildcard, or a list of files or wildcards to be removed
--
-- @return true on success, false and an appropriate error message on error
--
-- @example     ok, err = os.remove{"**.bak", "**.log"}
--              if not ok then
--                  error(err)
--              end
--

	local builtin_remove = os.remove
	function os.remove(f)
		-- in case of string, just match files
		if type(f) == "string" then
			local p = os.matchfiles(f)
			for _, v in pairs(p) do
				local ok, err = builtin_remove(v)
				if not ok then
					return ok, err
				end
			end
		-- in case of table, match files for every table entry
		elseif type(f) == "table" then
			for _, v in pairs(f) do
				local ok, err = os.remove(v)
				if not ok then
					return ok, err
				end
			end
		end
	end


--
-- Remove a directory, along with any contained files or subdirectories.
--

	local builtin_rmdir = os.rmdir
	function os.rmdir(p)
		-- recursively remove subdirectories: exclude no dirs apart builtin . and ..
		local dirs = os.match(p .. "/*", false, "a^", nil)
		for _, dname in ipairs(dirs) do
			if not (dname:endswith("/.") or dname:endswith("/..")) then
				os.rmdir(dname)
			end
		end

		-- remove any files
		local files = os.matchfiles(p .. "/*")
		for _, fname in ipairs(files) do
			os.remove(fname)
		end

		-- remove this directory
		builtin_rmdir(p)
	end


---
-- Return information about a file.
---

	premake.override(os, "stat", function(base, p)
		p = path.normalize(p)
		return base(p)
	end)



--
-- Generate a UUID.
--

	os._uuids = {}

	local builtin_uuid = os.uuid
	function os.uuid(name)
		local id = builtin_uuid(name)
		if name then
			if os._uuids[id] and os._uuids[id] ~= name then
				premake.warnOnce(id, "UUID clash between %s and %s", os._uuids[id], name)
			end
			os._uuids[id] = name
		end
		return id
	end
