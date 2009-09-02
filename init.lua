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

function retag(c)
	local s = get_screen(c)
	local tags = tags[s]
	local newtags = {}
	local selected = {}
	
	-- check awful.rules.rules to see if anything matches
	for _, r in ipairs(awful.rules.rules) do
		if r.properties.tagname and awful.rules.match(c, r.rule) then
			newtags[#newtags + 1] = r.properties.tagname
			if r.properties.switchtotag then
				selected[r.properties.tagname] = true
			end
		end
	end

	if #newtags == 1 and newtags[1] == 'any' then
		do return end
	end

	-- if no tagnames specified
	if #newtags == 0 then
		if fallback then newtags = { fallback }
		else newtags = { c.class:lower() } end
	end

	local vtags = {}
	-- go through newtags table and replace strings with tag objects
	for i, name in ipairs(newtags) do
		for _, t in ipairs(tags) do
			if t.name == name then
				newtags[i] = t
				break
			end
		end
		if type(newtags[i]) == 'string' and newtags[i] ~= 'any' then
			newtags[i] = maketag( name, s )
			if not selected[name] and show_new_tags then
				vtags[#vtags + 1] = newtags[i]
			end
		end
		if selected[name] ~= nil then vtags[#vtags + 1] = newtags[i] end
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
	local ia, ib = nil
	local retv = true
	for i, name in ipairs(start_tags) do
		if name == a then ia = i end
		if name == b then ib = i end
	end

	if not ia and not ib then
		-- Neither of our tags are listed in start_tags, so search end_tags
		local retv = not retv -- invert the return for cases where we have one tag with an indice and one without
		for i, name in ipairs(end_tags) do
			if name == a then ia = i end
			if name == b then ib = i end
		end
	end

	if ia and ib then retv = (ia < ib) 
	elseif ib and not ia then	retv = not retv	end
	return retv
end

function maketag( name, s )
	local tags = tags[s]
	local idx = nil
	for i, t in ipairs(tags) do
		if tagorder_comparator(name, t.name) then -- Tag we are making should come before this tag
			idx = i
		end
	end

	if idx then
		for i = #tags, idx, -1 do
			tags[i + 1] = tags[i]
		end
	else idx = #tags + 1 end

	tags[idx] = tag({ name = name })
	tags[idx].screen = s
	if layouts[name] ~= nil then
		awful.layout.set(layouts[name][1], tags[idx])
	elseif layouts['default'] ~= nil then
		awful.layout.set(layouts['default'][1], tags[idx])
	else
		awful.layout.set(layouts[1], tags[idx])
	end
	-- table.sort(tags, tagorder_comparator)
	return tags[idx]
end

function cleanup(c)
	local tags = tags[c.screen]
	
	local selected = {}
	for i, t in ipairs(tags) do
		if t.selected then selected[i] = true end
	end

	local removed = {}
	for i, t in ipairs(tags) do
		if del(tags[i]) then
			removed[#removed + 1] = i
		end
	end

	-- If we need to renumber the tags
	local r = 0
	for _, i in ipairs(removed) do
		for n = i - r, #tags do
			tags[n] = tags[n + 1]
		end
		tags[#tags - r] = nil
		r = r + 1
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

