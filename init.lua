local table = table
local pairs = pairs
local ipairs = ipairs
local type = type

local client = client
local mouse = mouse
local screen = screen
local tags = tags
local tag = tag
local layouts = layouts
local awful = require('awful')
require('awful.rules')
require('naughty')
local print = function(msg)
	naughty.notify({title="Dyno says", text=msg, timeout=0})
end

module('dyno')

-- {{{ CONFIGURATION

-- Determine the behaviour when a client does not match to any tag	name.
-- This can be a tagname (string) that will be used as the 'fallback' tag, or
-- it can be set to false to auto-generate tags based on the clients class name
fallback = false

-- Whether to automatically select newly created tags
show_new_tags = true

-- Whether we should always switch tags, regardless of the switchtotag property
-- You should leave this alone unless you want to end update all your awful
-- rules or spend a lot of time looking at the desktop
always_switch = true

-- The strategy used to decide which tags to display when mapping a new client
-- select the newly matched tags without deselecting anything
VS_APPEND = 1
-- select only the newly matched tags
VS_NEW_ALL = 2
-- select only the first of the newly matched tags
VS_NEW_FIRST = 3
-- select only the last of the newly matched tags
VS_NEW_LAST = 4
-- select only the matching tag with the least clients (this is often the
-- most specific tag to the client)
VS_SMALLEST = 5
visibility_strategy = VS_SMALLEST

-- Should we retag windows when their name changes?
-- Can be useful for retagging terminals when you are using them for different
-- tasks, set it true to automatically retag all clients on name-changes, or 
-- an awful matching rule to automatically retag only matching clients
tag_on_rename = { class = "XTerm" }

-- These two tables determine tag order, with any un-matched tags being 
-- sandwiched in the middle. Do not put the same tagname in both tables!
start_tags = {'code', 'web', }
end_tags = { 'ssh', 'sys', 'term' }

-- END CONFIGURATION }}}

-- Small utility function that will always return a screen #
local function get_screen(obj)
	return (obj and obj.screen) or mouse.screen or 1
end

local function tagnames( c )
  local names = {}
  local select_these = {}
	-- find matches
	for _, r in ipairs(awful.rules.rules) do
		if r.properties.tagname and awful.rules.match(c, r.rule) then
			if r.properties.exclusive then
				names = {r.properties.tagname}
				select_these = {}
				if always_switch or r.properties.switchtotag then 
					select_these[r.properties.tagname] = true
				end
				break
			end
			if always_switch or r.properties.switchtotag then
				select_these[r.properties.tagname] = true
			end
			names[#names + 1] = r.properties.tagname
		end
	end
  return names, select_these
end

local function tagorder_comparator( a, b )
	local a = a.name
	local b = b.name
	local ia, ib
	local retv = true
	for i, name in ipairs(start_tags) do
		if name == a then ia = i 
		elseif name == b then ib = i end
	end

	if not ia and not ib then 
		-- invert the return so that end_tags come after unspecified tags
		retv = not retv 
		for i, name in ipairs(end_tags) do
			if name == a then ia = i end
			if name == b then ib = i end
		end
	end 
	-- both tags found in same table, order according to indices
	if ia and ib then retv = (ia < ib) 
	-- neither tag found in either table, order alphabetically
	elseif not ia and not ib then retv = (a < b) 
	-- found first tag and not the second, invert the return (false for start_tag, true for end_tag)
	elseif ib and not ia then retv = not retv 
	end
	return retv
end

local function maketag( name, s )
	local tags = tags[s]
	local t = tag({ name = name }) 

	if 		 layouts[name] 			then awful.layout.set(layouts[name][1], t)
	elseif layouts['default'] then awful.layout.set(layouts['default'][1], t)
	else 	 awful.layout.set(layouts[1], t) end

	table.insert(tags, t)
	table.sort(tags, tagorder_comparator)
	screen[s]:tags(tags)
	return t
end

local function cleanup()
	for s = 1, #tags do
		local tags = tags[s]
		
		local selected = {}

		local removed = {}
		for i, t in ipairs(tags) do
			local clients = t:clients()
			local it_should_go = true
			if #clients > 0 then
				for i, c in ipairs(clients) do
					if not c.sticky then 
						it_should_go = false
						break
					end
				end
			end

			if it_should_go then
				-- remove tag
				t.screen = nil
				table.remove(tags, i)
			end
		end

		if not awful.tag.selected(s) then
			awful.tag.history.restore()
		end
	end
end

local function del(t)
	-- return if tag not empty (except sticky)
	return true
end


-- Meat of the module, takes a client as it's argument and sets it's tags 
-- according to the tagname property in any matching awful rule
function tagtables(c)
	local s = get_screen(c)
	local newtags, selected = tagnames(c)

	-- If only match is 'any' tag, then don't retag the client
	if #newtags == 1 and newtags[1] == 'any' then
		return 
	end

	-- If no matches were found, check the fallback strategy
	if #newtags == 0 then
		if fallback then newtags = { fallback } --Use the defined fallback tagname
		else newtags = { c.class:lower() } end --Generate tags based on window class
	end

	local vtags = {}
	-- go through newtags table and replace strings with tag objects
	for i, name in ipairs(newtags) do
		-- Don't do anything for the 'any' tag
		if name == 'any' then break end

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
		
		-- Add the tags in selected to vtags
		if selected[name] then vtags[#vtags + 1] = newtags[i] end
	end
  return newtags, vtags
end

-- Set the visible tags according to the selected visibility strategy
local function settags(s, vtags)
	local want
  if visibility_strategy == VS_APPEND then
    want = awful.util.table.join(awful.tag.selectedlist(s), vtags)
  elseif visibility_strategy == VS_NEW_ALL then
    want = vtags
  elseif visibility_strategy == VS_NEW_FIRST then
    want = {vtags[1]}
  elseif visibility_strategy == VS_NEW_LAST then
    want = {vtags[#vtags]}
	elseif visibility_strategy == VS_SMALLEST then
		local min = vtags[1]
		for i, tag in ipairs(vtags) do
			if #tag:clients() < #min:clients() then min = tag end
		end
		want = {min}
  end
	awful.tag.viewmore(want, s)
end

function manage(c)
  local tags, vtags = tagtables(c)
	-- Check if tags actually changed
	for _, new_tag in ipairs(tags) do
		local found = false
		for _, old_tag in ipairs(c:tags()) do
			if new_tag == old_tag then 
				found = true 
				break
			end
		end

		if not found then 
			c:tags(tags)
			settags(get_screen(c), vtags)
			local stags = awful.tag.selectedlist(s)
			if #stags == 0 then print("No visible tags after managing client <b>'" .. c.name ..
				"'</b>\nEither add 'switchtotag = true' to (most of) your awful rules, \nor set 'always_switch' back to true in dyno/init.lua")
			end
			break
		end
	end
end

client.add_signal("manage", manage)

client.add_signal("unmanage", function(c)
	prev_names[c] = nil
	cleanup()
end)

if tag_on_rename then
	prev_names = {}
	client.add_signal("manage", function(c)
		c:add_signal("property::name", function(c)
      if tag_on_rename ~= true and not awful.rules.match(c, tag_on_rename) then return end
			local f = client.focus
			prev_names[c] = c.name
			manage(c)
			cleanup()
			-- Restore focus
			client.focus = f
		end)
	end)
end
-- vim: foldmethod=marker:filetype=lua:tabstop=2:encoding=utf-8:textwidth=80
