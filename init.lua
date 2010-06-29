-- {{{ INCLUDES
local table = table
local pairs = pairs
local ipairs = ipairs
local type = type

local modkey = modkey
local mypromptbox = mypromptbox
local globalkeys = globalkeys
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
-- You should leave this alone unless you want to update all your awful
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

-- A set of left/right taglists for each screen. These two tables determine 
-- tag order, with any un-matched tags being sandwiched in the middle. 
-- Only the first occurrence of a tag is ever used
screen_tags = {
	{
		left = {'web', },
		right = { },
	},
	{
		left = {'code', 'ssh', },
		right = { 'sys', 'term' },
	},
}

-- END CONFIGURATION }}}

-- {{{ PROMPT FUNCTION
function prompt()
	awful.prompt.run({prompt = 'Tag: '}, mypromptbox[client.focus.screen].widget, 
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


local function findscreen()
	for s = 1, #screen_tags do 
		for _, tag in ipairs(screen_tags[s]['left']) do
			if tag == name then return s end
		end
		for _, tag in ipairs(screen_tags[s]['right']) do
			if tag == name then return s end
		end
	end
	if client.focus ~= nil then
		return client.focus.screen -- Tag not found
	else
		return 1
	end
end

local function newtag( name )
	local s = findscreen(name)

	local t = tag({ name = name }) 
	t.screen = s

	if 		 layouts[name] 			then awful.layout.set(layouts[name][1], t)
	elseif layouts['default'] then awful.layout.set(layouts['default'][1], t)
	else 	 awful.layout.set(layouts[1], t) end

	table.insert(tags[s], t)
	table.sort(tags[s], function ( a, b )
		local a = a.name
		local b = b.name
		local ia, ib
		local retv = true
		for i, name in ipairs(screen_tags[s]['left']) do
			if name == a then ia = i 
			elseif name == b then ib = i end
		end

		if not ia and not ib then 
			-- Neither tag is in left, search right
			-- invert the return so that right come after unspecified tags
			retv = not retv 
			for i, name in ipairs(screen_tags[s]['right']) do
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
	end)
	screen[s]:tags(tags[s])
	return t
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


	local screen_counts = {0, 0, 0, 0, 0, 0} -- Six screens are enough for now!
	local vtags = {}
	-- go through newtags table and replace strings with tag objects
	for i, name in ipairs(newtags) do
		-- Don't do anything for the 'any' tag
		if name == 'any' then break end

		-- Search tags for existing matches
		for s = 1, screen.count() do
			table.foreach(screen[s]:tags(), function(t)
				if t.name == name then
					newtags[i] = t
					return
				end
			end)
		end
		
		-- Didn't find an existing matching tag, so make one
		if type(newtags[i]) == 'string' then
			newtags[i] = newtag( name )
			-- The check to select_these[name] is necessary to avoid adding the tag to vtags 2x
			if show_new_tags and not select_these[name] then
				table.insert(vtags, newtags[i])
			end
		end

		local s = newtags[i].screen
		screen_counts[s] = screen_counts[s] + 1
		
		-- Add the tags in select_these to vtags
		if select_these[name] then vtags[#vtags + 1] = newtags[i] end
	end
	
	local s = 1
	if #screen_counts > 1 then
		for i, count in pairs(screen_counts) do
			if count > screen_counts[s] then
				s = i
			end
		end
	end
	
	rtags = {}
	table.foreach(newtags, function(t)
		if t.screen == s then
			table.insert(rtags, t)
		end
	end)

	rvtags = {}
	table.foreach(vtags, function(t)
		if t.screen == s then
			table.insert(rvtags, t)
		end
	end)

  return rtags, rvtags
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

-- Remove tags that are empty or only have sticky clients
local function cleanup()
	for s = 1, screen.count() do

		local selected = {}
		local removed = {}

		for i, t in ipairs(tags[s]) do
			local clients = t:clients()
			local delete_me = true
			for i, c in ipairs(clients) do
				if not c.sticky then 
					delete_me = false
					break
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

-- Publically visible manage signal callback
function manage(c)
	-- print("Manage " .. c.name)
  local ctags, vtags = tagtables(c)
	local focus = client.focus
	local s = client.screen
	c:tags(ctags)
	print("Managing client <b>" .. c.name .. "</b>")
	if c == focus and #vtags > 0 then
		settags(s, vtags)
	else
		print("Managing unfocused client <b>" .. c.name .. "</b>, focused client is <b>" .. client.focus.name .. "</b>")
	end
	local selected = awful.tag.selectedlist(s)
	if #selected == 0 then 
		awful.tag.history.restore(s)
	end
	local selected = awful.tag.selectedlist(s)
	if #selected == 0 then 
		awful.tag.viewnext(tags[s][1])
	end
end
-- }}}

-- {{{ MODULE SETUP

-- Clear tag tables
for s = 1, screen.count() do
	tags[s] = awful.tag({}, s, layouts[1])
end

globalkeys = awful.util.table.join(globalkeys,
	awful.key({ modkey }, "t", prompt)
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
			prev_names[c] = c.name
			manage(c)
			cleanup()
		end)
	end)
end

-- cleanup()
-- }}}

-- vim: foldmethod=marker:filetype=lua:tabstop=2:encoding=utf-8:textwidth=80
