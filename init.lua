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

-- Debug environment
local naughty = require('naughty')
module('dyno')

-- Determine the behaviour when a client does not match to any tag	name.
-- This can be a tagname (string) that will be used as the 'fallback' tag, or
-- it can be set to false to auto-generate tags based on the clients class name
fallback = false

-- Whether to automatically select newly created tags
show_new_tags = true

-- The strategy used to decide which tags to display when mapping a new client
-- 1 == select the newly matched tags without deselecting anything
-- 2 == select only the newly matched tags
-- 3 == select only the first of the newly matched tags
-- 4 == select only the last of the newly matched tags
-- 5 == select only the matching tag with the least clients (this is often the
-- most specific tag to the client)
-- else == do not alter the selected tags at all
visibility_strategy = 5

-- Whether to retag windows when their name changes.
-- Can be useful for retagging terminals when you are using them for different
-- tasks, set it true to automatically retag all clients on name-changes, or 
-- an awful matching rule to only automatically retag matching clients
tag_on_rename = { class = "URxvt" }

-- These two tables determine tag order, with any un-matched tags being 
-- sandwiched in the middle. Do not put the same tagname in both tables!
start_tags = {'code', 'web', }
end_tags = { 'ssh', 'sys', 'term' }


local function get_screen(obj)
	return (obj and obj.screen) or mouse.screen or 1
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

function visibletags(vtags, s)
  if visibility_strategy == 1 then
    return awful.util.table.join(awful.tag.selectedlist(s), vtags)
  elseif visibility_strategy == 2 then
    return vtags
  elseif visibility_strategy == 3 then
    return {vtags[1]}
  elseif visibility_strategy == 4 then
    return {vtags[#vtags]}
	elseif visibility_strategy == 5 then
		naughty.notify({ text = "Retagging using strategy "..visibility_strategy })
		local mindex = 1
		for i, tag in ipairs(vtags) do
			if #tag:clients() < #vtags[mindex]:clients() then mindex = i end
		end
		return {vtags[mindex]}
  end

end

function tagnames( c )
  names = {}
  selected = {}
	-- find matches
	for _, r in ipairs(awful.rules.rules) do
		if r.properties.tagname and awful.rules.match(c, r.rule) then
			if r.properties.switchtotag then
				selected[r.properties.tagname] = true
			end
			if r.properties.exclusive then
				names = {r.properties.tagname}
				if r.properties.switchtotag then selected = {r.properties.tagname}
				else selected = {} end
				break
			end
			names[#names + 1] = r.properties.tagname
		end
	end
  return names, selected
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

function maketag( name, s )
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
				return false 
			end
		end
	end

	-- remove tag
	t.screen = nil
	return true
end

client.add_signal("manage", function(c)
  local tags, vtags = tagtables(c)
	local s = get_screen(c)
  c:tags(tags)
  local selected = visibletags(vtags, s)
  if #vtags > 0 then
    awful.tag.viewmore(visibletags(vtags, s), s)
  end
end)

client.add_signal("unmanage", cleanup)

if tag_on_rename then
	local last_rename = ""
	client.add_signal("manage", function(c)
		c:add_signal("property::name", function(c)
      if tag_on_rename ~= true and not awful.rules.match(c, tag_on_rename) then
        return
      elseif c.name ~= last_rename then
				naughty.notify({text = "Retagging on rename to "..c.name})
				local f = awful.client.focus
				last_rename = c.name
        local tags, vtags = tagtables(c)
				local s = get_screen(c)
        c:tags(tags)

        local switch = true
        local want = visibletags(vtags, s)
        local have = awful.tag.selectedlist(s)
        for _, w in ipairs(want) do
          for i, h in ipairs(have) do
            if h == w then switch = false; break end
          end
          if not switch then break end
        end
        if switch then awful.tag.viewmore(want, s) end
				cleanup(c)
				-- Restore focus
				awful.client.focus = f
			end
		end)
	end)
end
-- vim: foldmethod=marker:filetype=lua:tabstop=2:encoding=utf-8:textwidth=80
