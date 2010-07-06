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
local G = getfenv(1)
local get_screen = get_screen
require('awful.rules')
require('awful.util')
require('naughty')
local print = function(msg)
	naughty.notify({title="Dyno says", text=msg, timeout=15})
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
tag_order = {
	left = {'web', 'code', 'ssh',},
	right = { 'sys', 'term' },
}

-- END CONFIGURATION }}}

-- {{{ PROMPT FUNCTION
local function dyno_prompt()
	awful.prompt.run({prompt = 'Tag: '}, mypromptbox[get_screen()].widget, 
	function (tagname)
		local name, s = tagname:match('(%a+) {(%d+)}')
		s = 0 + s -- Attempt to convert back to number
		for _, t in ipairs(screen[s]:tags()) do
			if t.name == name then
				awful.tag.viewonly(t, s)
				awful.screen.focus(s)
				break
			end
		end
	end,
	function (input, cur_pos, ncomp)
		local matches = {}
		for s = 1, screen.count() do
			for _, t in ipairs(screen[s]:tags()) do
				if t.name:match('^' .. input) then
					matches[#matches+1] = t.name .. ' {' .. t.screen .. '}'
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

-- Match the client against awful rules and return two lists:
--   Tag names that the client should be tagged with
--   Tags that should be selected (according to switchtotag)
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
	for _, tag in ipairs(screen_tags['left']) do
		if tag == name then return s end
	end
	for _, tag in ipairs(screen_tags['right']) do
		if tag == name then return s end
	end
	if client.focus ~= nil then
		return client.focus.screen -- Tag not found
	else
		return mouse.screen
	end
end

local function newtag( name, s )
	local t = tag({ name = name }) 

	if 		 layouts[name] 			then awful.layout.set(layouts[name][1], t)
	elseif layouts['default'] then awful.layout.set(layouts['default'][1], t)
	else 	 awful.layout.set(layouts[1], t) end

	local tags = screen[s]:tags()
	table.insert(tags, t)
	table.sort(tags, function ( a, b )
		local a = a.name
		local b = b.name
		local ia, ib
		local retv = true
		for i, name in ipairs(tag_order['left']) do
			if name == a then ia = i 
			elseif name == b then ib = i end
		end

		if not ia and not ib then 
			-- Neither tag is in left, search right
			-- invert the return so that tags on the right come after unspecified tags
			retv = not retv 
			for i, name in ipairs(tag_order['right']) do
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
	screen[s]:tags(tags)
	return t
end

-- 
--
local function tagtables(c)
	local newtags, select_these = tagnames(c)
	
	local s
	if c.screen then
		s = c.screen
	else 
		s = get_screen()
	end

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

		-- Search tags for existing matches
		for _, t in pairs(screen[s]:tags()) do
			if t.name == name then
				newtags[i] = t
				break
			end
		end
		
		-- Didn't find an existing matching tag, so make one
		if type(newtags[i]) == 'string' then
			newtags[i] = newtag( name, s )
			-- The check to select_these[name] is necessary to avoid adding the tag to vtags 2x
			if show_new_tags and not select_these[name] then
				table.insert(vtags, newtags[i])
			end
		end

		-- Add the tags in select_these to vtags
		if select_these[name] then vtags[#vtags + 1] = newtags[i] end
	end
	
  return newtags, vtags
end

-- Set the visible tags according to the selected visibility strategy
local function viewtags(vtags, s)
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

		local tags = screen[s]:tags() 
		for n, t in pairs(tags) do
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

		screen[s]:tags(tags)
		if not awful.tag.selected(s) then
			awful.tag.history.restore()
		end
	end
end

-- Publically visible manage signal callback
function manage(c)
	local focus = client.focus
  local ctags, vtags = tagtables(c)
	c:tags(ctags)
	local s = client.screen or get_screen()
	if c == focus and #vtags > 0 then
		viewtags(vtags, s)
	end
	local selected = awful.tag.selectedlist(s)
	if #selected == 0 then 
		awful.tag.history.restore(s)
	end
	local selected = awful.tag.selectedlist(s)
	if #selected == 0 then 
		awful.tag.viewnext(screen[s])
	end
end
-- }}}

-- {{{ MODULE SETUP

-- Clear tag tables
for s = 1, screen.count() do
	tags[s] = nil
	screen[s]:tags({})
end

local function get_tags()
	return screen[get_screen()]:tags()
end

for i = 1, 9 do
	G.globalkeys = awful.util.table.join(G.globalkeys,
		awful.key({ modkey }, "#" .. i + 9,
			function ()
				local tags = get_tags()
				if tags[i] then
					awful.tag.viewonly(tags[i])
				end
			end),
		awful.key({ modkey, "Control" }, "#" .. i + 9,
			function ()
				local tags = get_tags()
				if tags[i] then
					awful.tag.viewtoggle(tags[i])
				end
			end),
		awful.key({ modkey, "Shift" }, "#" .. i + 9,
			function ()
				local tags = get_tags()
				if client.focus and tags[i] then
					awful.client.movetotag(tags[i])
				end
			end),
		awful.key({ modkey, "Control", "Shift" }, "#" .. i + 9,
			function ()
				local tags = get_tags()
				if client.focus and tags[i] then
					awful.client.toggletag(tags[i])
				end
			end)
	)
end

G.globalkeys = awful.util.table.join(G.globalkeys,
	awful.key({ modkey }, "t", dyno_prompt)
)

local prev_names = {}
client.add_signal("manage", manage)

client.add_signal("unmanage", function(c)
	prev_names[c] = nil
	cleanup()
end)

if tag_on_rename then
	client.add_signal("manage", function(c)
		c:add_signal("property::name", function(c)
      if tag_on_rename ~= true and not awful.rules.match(c, tag_on_rename) then return end
			if c.prev_name ~= nil or c.name == c.prev_name then return end
			-- if c.name == prev_names[c] then return end
			c.prev_name = c.name
			-- prev_names[c] = c.name
			manage(c)
			cleanup()
		end)
	end)
end

-- cleanup()
-- }}}

-- vim: foldmethod=marker:filetype=lua:tabstop=2:encoding=utf-8:textwidth=80
