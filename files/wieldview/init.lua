local has_armor = minetest.get_modpath("3d_armor")
local time = 0
local update_time = tonumber(minetest.settings:get("wieldview_update_time"))
if not update_time then
	update_time = 2
	minetest.settings:set("wieldview_update_time", tostring(update_time))
end
local node_tiles = minetest.settings:get_bool("wieldview_node_tiles")
if not node_tiles then
	node_tiles = false
	minetest.settings:set("wieldview_node_tiles", "false")
end

wieldview = {
	wielded_item = {},
	transform = {},
}

dofile(minetest.get_modpath(minetest.get_current_modname()).."/transform.lua")

local function update_player_visuals(player, wield_image)
	local name = player:get_player_name()
	if has_armor then
		armor.textures[name].wielditem = wield_image
		armor:update_player_visuals(player)
		return
	end
	local animation = player_api.get_animation(player) or {}
	local textures = animation.textures or {}
	local skin = textures[1] and textures[1] or "character.png"
	player_api.set_textures(player, {skin, "blank.png", wield_image})
end

wieldview.get_item_texture = function(self, item)
	local texture = "blank.png"
	if item ~= "" then
		if minetest.registered_items[item] then
			if minetest.registered_items[item].inventory_image ~= "" then
				texture = minetest.registered_items[item].inventory_image
			elseif node_tiles == true and minetest.registered_items[item].tiles
					and type(minetest.registered_items[item].tiles[1]) == "string"
					and minetest.registered_items[item].tiles[1] ~= "" then
				texture = minetest.inventorycube(minetest.registered_items[item].tiles[1])
			end
		end
		-- Get item image transformation, first from group, then from transform.lua
		local transform = minetest.get_item_group(item, "wieldview_transform")
		if transform == 0 then
			transform = wieldview.transform[item]
		end
		if transform then
			-- This actually works with groups ratings because transform1, transform2, etc.
			-- have meaning and transform0 is used for identidy, so it can be ignored
			texture = texture.."^[transform"..tostring(transform)
		end
	end
	return texture
end

wieldview.update_wielded_item = function(self, name)
	local player = minetest.get_player_by_name(name)
	if not player or not player:is_player() then
		return
	end
	local stack = player:get_wielded_item()
	local item = stack:get_name()
	if not item then
		return
	end
	if self.wielded_item[name] then
		if self.wielded_item[name] == item then
			return
		end
		update_player_visuals(player, self:get_item_texture(item))
	end
	self.wielded_item[name] = item
end
if not minetest.is_singleplayer() then
	minetest.register_on_joinplayer(function(player)
		local name = player:get_player_name()
		wieldview.wielded_item[name] = ""
		minetest.after(0, function(player)
			wieldview:update_wielded_item(name)
		end, player)
	end)
	minetest.register_playerstep(function(dtime, playernames)
		for _, name in pairs(playernames) do
			wieldview:update_wielded_item(name)
		end
	end)
end
