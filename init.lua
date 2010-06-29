-- {{{ INCLUDES
local table = table
local pairs = pairs
local ipairs = ipairs
local type = type

local G = getfenv(1)
local client = client
local mouse = mouse
local screen = screen
local tags = tags
local tag = tag
local layouts = layouts
local awful = require('awful')
require('awful.rules')
require('awful.util')
require('naughty')
local print = function(msg)
	naughty.notify({title="Dyno says", text=msg, timeout=0})
end
-- }}}

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

-- Map a specific tag name (and any client that matches it) to a given screen
tag_to_screen = {
	web = 1, term = 2, email = 1, code = 2
}

-- END CONFIGURATION }}}

-- {{{ PROMPT FUNCTION
function prompt()
	awful.prompt.run({prompt = 'Tag: '}, G.mypromptbox[mouse.screen].widget, 
	function (tagname)
		for s = 1, screen.count() do
			for _, t in ipairs(screen[s]:tags()) do
				if t.name == tagname then
					awful.tag.viewonly(t)
					awful.screen.focus(s)
					break
				end
			end
		end
	end,
	function (input, cur_pos, ncomp)
		local matches = {}
		for s = 1, screen.count() do
			for _, t in ipairs(screen[s]:tags()) do
				if t.name:match('^' .. input) ~= nil then
					matches[#matches+1] = t.name
				end
			end
		end

		if #matches == 0 then return '', 0 end
		
		while ncomp > #matches do
			ncomp = ncomp - #matches
		end
		current_match = matches[ncomp]
		-- return match and position
		return matches[ncomp], #current_match+1
	end)
end
-- }}}

-- {{{ TAGGING FUNCTIONS

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

local function tag_comparator( a, b )
	local a = a.name
	local b = b.name
	local ia, ib
	local retv = true
	for i, name in ipairs(start_tags) do
		if name == a then ia = i 
		elseif name == b then ib = i end
	end

	if not ia and not ib then 
		-- Neither tag is in start_tags, search end tags
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
	elseif ib and not ia then retv = not retv end
	return retv
end

local function newtag( name )
	if tag_to_screen[name] ~= nil and tag_to_screen[name] <= screen.count() then
		s = tag_to_screen[name]
	else
		s = get_screen(client.focus)
	end

	local t = tag({ name = name }) 

	if 		 layouts[name] 			then awful.layout.set(layouts[name][1], t)
	elseif layouts['default'] then awful.layout.set(layouts['default'][1], t)
	else 	 awful.layout.set(layouts[1], t) end

	local tags = tags[s]
	table.insert(tags, t)
	table.sort(tags, tag_comparator)
	screen[s]:tags(tags)
	return t
end

local function del(t)
	-- return if tag not empty (except sticky)
	return true
end

-- Remove tags that are empty or only have sticky clients
local function cleanup()
	for s = 1, screen.count() do
		local tags = tags[s]
		
		local selected = {}

		local removed = {}
		for i, t in ipairs(tags) do
			local clients = t:clients()
			local delete_me = true
			if #clients > 0 then
				for i, c in ipairs(clients) do
					if not c.sticky then 
						delete_me = false
						break
					end
				end
			end

			if delete_me then
				t.screen = nil
				table.remove(tags, i)
			end
		end

		if not awful.tag.selected(s) then
			awful.tag.history.restore()
		end
	end
end

-- Meat of the module, takes a client as it's argument and sets it's tags 
-- according to the tagname property in any matching awful rule
local function tagtables(c)
	local newtags, select_these = tagnames(c)

	-- If only match is 'any' tag, then don't retag the client
	if #newtags == 1 and newtags[1] == 'any' then
		return 
	end

	-- If no matches were found, check the fallback strategy
	if #newtags == 0 then
		if fallback then newtags = { fallback } --Use the defined fallback tagname
		else newtags = { c.class:lower() } end --Generate tags based on window class
	end

	local screen_tags = {}
	for _, name in ipairs(newtags) do
		local tag_screen = tag_to_screen[name]
		if tag_screen ~= nil then 
			if screen_tags[tag_screen] == nil then
				screen_tags[tag_screen] = {name}
			else
				table.insert(screen_tags[tag_screen], name)
			end
		end
	end

	if #screen_tags > 1 then -- Conflicting screens!
		local max_index = 1
		for i = 2, #screen_tags do 
			if #screen_tags[i] > #screen_tags[max_index] then
				max_index = i
			end
		end

		msg = "Cannot tag client '"..c.name.."' properly because tag screens conflict:\n"
		for screen, tags in pairs(screen_tags) do
			for _, tag in ipairs(tags) do 
				msg = msg .. tag .. '=' .. screen .. '\n'
			end
		end
		msg = '\n Choosing screen ' .. max_index
		newtags = screen_tags[max_index]
		c.screen = tags[max_index]
	end

	local vtags = {}
	-- go through newtags table and replace strings with tag objects
	for i, name in ipairs(newtags) do
		-- Don't do anything for the 'any' tag
		if name == 'any' then break end

		-- Search tags for existing matches
		for s = 1, screen.count() do
			for _, t in ipairs(screen[s]:tags()) do
				if t.name == name then
					newtags[i] = t
					break
				end
			end
		end
		
		-- Didn't find an existing matching tag, so make one
		if type(newtags[i]) == 'string' then
			newtags[i] = newtag( name )
			-- The check to select_these[name] is necessary to avoid adding the tag to vtags 2x
			if show_new_tags and not select_these[name] then
				vtags[#vtags + 1] = newtags[i]
			end
		end
		
		-- Add the tags in select_these to vtags
		if select_these[name] then vtags[#vtags + 1] = newtags[i] end
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

-- Publically visible manage signal callback
function manage(c)
	-- print("Manage " .. c.name)
  local ctags, vtags = tagtables(c)
	c:tags(ctags)
	settags(get_screen(c), vtags)
	local selected = awful.tag.selectedlist(s)
	if #selected == 0 then print("No selected tags after managing client <b>'" .. c.name ..
		"'</b>\nTry adding 'switchtotag = true' to (most of) your awful rules, \nor set 'always_switch' back to true in dyno/init.lua")
	end
end
-- }}}

-- {{{ MODULE SETUP

-- Clear tag tables
for s = 1, screen.count() do
	tags[s] = awful.tag({}, s, layouts[1])
end

G.globalkeys = awful.util.table.join(G.globalkeys,
	awful.key({ G.modkey }, "t", prompt)
)

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
			if c.name == prev_names[c] then return end
			local f = client.focus
			prev_names[c] = c.name
			manage(c)
			cleanup()
			-- Restore focus
			client.focus = f
		end)
	end)
end

cleanup()
-- }}}

-- vim: foldmethod=marker:filetype=lua:tabstop=2:encoding=utf-8:textwidth=80
