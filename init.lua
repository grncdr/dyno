local clientkeys = clientkeys
local client = client
local mouse = mouse
local pairs = pairs
local ipairs = ipairs
local type = type
local table = table
local screen = screen
local tags = tags
local tag = tag
local layouts = config.layouts
local awful = awful
local rules = awful.rules.rules
local match = awful.rules.match
local naughty = require('naughty')
local beautiful = require('beautiful')
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
-- default == do not alter the selected tags at all
visibility_strategy = 3

local function get_screen(obj)
	return (obj and obj.screen) or mouse.screen or 1
end

function retag(c)
	local s = get_screen(c)

	local tags = tags[s]
	local newtags = {}
	local selected = {}
	-- check awful.rules.rules to see if anything matches
	for _, r in ipairs(rules) do
		if r.properties.tagname and match(c, r.rule) then
			newtags[#newtags + 1] = r.properties.tagname
			if r.properties.switchtotag then
				selected[r.properties.tagname] = true
			end
		end
	end

	-- if no tagnames specified
	if #newtags == 0 then
		if fallback then
			if type(fallback) == 'string' then
				newtags = { fallback }
			elseif type(fallback) == 'tag' then
				newtags = { fallback }
			end
		else
			newtags = { c.class:lower() }
		end
	end

	local visible = {}
	for i, name in ipairs(newtags) do
		for _, t in ipairs(tags) do
			if t.name == name then
				newtags[i] = t
				break
			end
		end
		if type(newtags[i]) == 'string' then
			newtags[i] = maketag( name, s )
			if not selected[name] and show_new_tags then
				visible[#visible + 1] = newtags[i]
			end
		end
		if selected[name] ~= nil then visible[#visible + 1] = newtags[i] end
	end
	c:tags(newtags)
	set_visible(visible, s)
end
	
function set_visible(vtags, s)
	if visibility_strategy == 1 then
		for _, t in ipairs(vtags) do
			t.selected = true
		end
	elseif visibility_strategy == 2 then
		for _, t in ipairs(screen[s]:tags()) do
			local keep = false
			for n, vt in ipairs(vtags) do
				if t == vt then
					keep = true
					break
				end
			end
			t.selected = keep
		end
	elseif visibility_strategy == 3 then
		awful.tag.viewonly(vtags[1])
	elseif visibility_strategy == 4 then
		awful.tag.viewonly(vtags[#vtags])
	end
	if not awful.tag.selected() then tags[1].selected = true end
end

function maketag( name, s )
	local tags = tags[s]
	local t =  tag({ name = name })
	t.screen = s
	tags[#tags + 1] = t
	if layouts[name] ~= nil then
		awful.layout.set(layouts[name][1], tags[#tags])
	elseif layouts['default'] ~= nil then
		awful.layout.set(layouts['default'][1], t)
	else
		awful.layout.set(layouts[1], t)
	end
	t.selected = true
	return t
end

client.add_signal("manage", retag)
-- client.add_signal("property::name", retag)

function cleanup(c)
	local tags = tags[c.screen]
	for i, t in ipairs(tags) do
		del(tags[i], i)
	end
end

client.add_signal("unmanage", cleanup)

--{{{ del : delete a tag. Taken directly from the shifty sources
--@param tag : the tag to be deleted [current tag]
function del(tag, idx)
  local scr = get_screen(tag)
  local tags = screen[scr]:tags()
  local sel = awful.tag.selected(scr) local t = tag or sel

  -- return if tag not empty (except sticky)
  local clients = t:clients()
  local sticky = 0
  for i, c in ipairs(clients) do
    if c.sticky then sticky = sticky + 1 end
  end
  if #clients > sticky then return end

  -- remove tag
  t.screen = nil

  -- if the current tag is being deleted, restore from history
  if t == sel and #tags > 1 then
    awful.tag.history.restore(scr)
    -- this is supposed to cycle if history is invalid?
    -- e.g. if many tags are deleted in a row
    if not awful.tag.selected(scr) then
      awful.tag.viewonly(tags[awful.util.cycle(#tags, idx - 1)])
    end
  end

  -- FIXME: what is this for??
  -- if client.focus then client.focus:raise() end
end
--}}}
