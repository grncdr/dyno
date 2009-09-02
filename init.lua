local client = client
local mouse = mouse
local pairs = pairs
local ipairs = ipairs
local type = type
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
-- 1 == select the new clients tags without deselecting anything
-- 2 == select only the new clients tags
-- 3 == select only the first of the new clients tags
-- 4 == select only the last of the new clients tags
-- else == do not alter the selected tags at all
visibility_strategy = 3

-- Whether to retag windows when their name changes.
-- Can be useful for retagging terminals when you are using them for different
-- tasks, but it can be flickery
tag_on_rename = true

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

function maketag( name, s )
	local tags = tags[s]
	tags[#tags + 1] = tag({ name = name })
	tags[#tags].screen = s
	if layouts[name] ~= nil then
		awful.layout.set(layouts[name][1], tags[#tags])
	elseif layouts['default'] ~= nil then
		awful.layout.set(layouts['default'][1], tags[#tags])
	else
		awful.layout.set(layouts[1], tags[#tags])
	end
	return tags[#tags]
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
			end
		end)
	end)
end

