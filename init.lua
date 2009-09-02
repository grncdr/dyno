local table = table
local pairs = pairs
local ipairs = ipairs
local type = type

local client = client
local mouse = mouse
local screen = screen
local tags = tags
local tag = tag
local layouts = config.layouts
local awful = require('awful')

require('awful.rules')

-- These are for debugging, to be removed
local tostring = tostring
local print = print

module('dyno')

-- This can be a tag name (string) or tag object or false for auto-generated tag names
fallback = false

-- Whether to automatically select newly created tags
show_new_tags = true

-- The strategy used for deciding which tags to display after mapping a new client
-- 1 == select the newly matched tags without deselecting anything
-- 2 == select only the newly matched tags
-- 3 == select only the first of the newly matched tags
-- 4 == select only the last of the newly matched tags
-- else == do not alter the selected tags at all
visibility_strategy = 4

-- Whether to retag windows when their name changes.
-- Can be useful for retagging terminals when you are using them for different
-- tasks, but it can be flickery
tag_on_rename = true

-- These two tables determine tag order, with any un-matched tags being sandwiched in the middle
-- Do not put the same tag in both tables, it will probably break
start_tags = {'code', 'web', 'ssh' }
end_tags = {'sys', 'term'}


local function get_screen(obj)
	return (obj and obj.screen) or mouse.screen or 1
end

-- Meat of the module, takes a client as it's argument and sets it's tags according to the tagname property in any matching awful rule
function retag(c)
	local s = get_screen(c)
	local newtags = {}
	local selected = {}
	
	-- find matches
	for _, r in ipairs(awful.rules.rules) do
		if r.properties.tagname and awful.rules.match(c, r.rule) then
			newtags[#newtags + 1] = r.properties.tagname
			if r.properties.switchtotag then
				selected[r.properties.tagname] = true
			end
		end
	end

	-- If only match is 'any' tag, then don't retag the client
	if #newtags == 1 and newtags[1] == 'any' then
		do return end
	end

	-- If no matches were found, check the fallback strategy
	if #newtags == 0 then
		if fallback then newtags = { fallback } -- Use the defined fallback tagname
		else newtags = { c.class:lower() } end -- We are generating tags based on window class
	end

	local vtags = {}
	-- go through newtags table and replace strings with tag objects
	for i, name in ipairs(newtags) do
		-- Don't do anything for the 'any' tag
		if name == 'any' then do break end end

		-- Search tags on screen for existing matches
		for _, t in ipairs(screen[s]:tags()) do
			if t.name == name then
				newtags[i] = t
				break
			end
		end
		
		-- Didn't find an existing matching tag, so make one
		if type(newtags[i]) == 'string' then
			newtags[i] = maketag( name, s )
			-- The check to selected[name] is necessary to avoid adding the tag to vtags 2x
			if show_new_tags and not selected[name] then
				vtags[#vtags + 1] = newtags[i]
			end
		end
		-- Add the 
		if selected[name] then vtags[#vtags + 1] = newtags[i] end
	end
	c:tags(newtags)

	if #vtags ~= 0 then
		if visibility_strategy == 1 then
			for _, t in ipairs(vtags) do t.selected = true end
		elseif visibility_strategy == 2 then
			awful.tag.viewmore(vtags, s)
		elseif visibility_strategy == 3 then
			awful.tag.viewonly(vtags[1])
		elseif visibility_strategy == 4 then
			awful.tag.viewonly(vtags[#vtags])
		end
end
end

function tagorder_comparator( a, b )
	local a = a.name
	local b = b.name
	local ia, ib
  local retv = true
	for i, name in ipairs(start_tags) do
		if name == a then ia = i 
    elseif name == b then ib = i end
	end

	if not ia and not ib then
		-- Neither of our tags are listed in start_tags, so search end_tags
		local retv = not retv -- invert the return so that end_tags come last
		for i, name in ipairs(end_tags) do
			if name == a then ia = i end
			if name == b then ib = i end
		end
	end

	if ia and ib then retv = (ia < ib) -- both tags found in same table, order according to indices
  elseif not ia and not ib then retv = (a < b) -- neither tag found in either table, order alphabetically
	elseif ib and not ia then retv = not retv -- found first tag and not the second, invert the return (false for start_tag, true for end_tag)
  end
	return retv
end

function maketag( name, s )
	local tags = tags[s]
	local idx = nil
	local t = tag({ name = name }) 
	-- t.screen = s

--	for i, t in ipairs(tags) do
--		if tagorder_comparator(name, t.name) then -- Tag we are making should come before this tag
--			idx = i
--		end
--	end
--	if not idx then idx = #tags + 1 end 

	if 		 layouts[name] 		  then awful.layout.set(layouts[name][1], t)
	elseif layouts['default'] then awful.layout.set(layouts['default'][1], t)
	else 	 awful.layout.set(layouts[1], t) end
	table.insert(tags, t)
  table.sort(tags, tagorder_comparator)
	screen[s]:tags(tags)
	return t
end

function cleanup(c)
	local tags = tags[c.screen]
	
	local selected = {}
	for i, t in ipairs(tags) do
		if t.selected then selected[i] = true end
	end

	local removed = {}
	for i, t in ipairs(tags) do
		if del(t) then
			table.remove(tags, i)
		end
	end
end

function del(t)
  -- return if tag not empty (except sticky)
  local clients = t:clients()
	if #clients > 0 then
  	for i, c in ipairs(clients) do
    	if not c.sticky then 
				do return false end 
			end
  	end
	end

  -- remove tag
  t.screen = nil
	return true
end

client.add_signal("manage", retag)
client.add_signal("unmanage", cleanup)
if tag_on_rename then
	local last_rename = ""
	client.add_signal("manage", function(c)
		c:add_signal("property::name", function(c)
			if c.name ~= last_rename then
				last_rename = c.name
				retag(c)
				cleanup(c)
			end
		end)
	end)
end
-- vim: foldmethod=marker:filetype=lua:expandtab:shiftwidth=2:tabstop=2:softtabstop=2:encoding=utf-8:textwidth=80
