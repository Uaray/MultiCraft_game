local abs, floor, min, sign = math.abs, math.floor, math.min, math.sign
local vector_add, vector_equals, vector_new, vector_round = vector.add, vector.equals, vector.new, vector.round

-- Compatible for MultiCraft Engine 2.0
local ah = minetest.features.object_independent_selectionbox and 0 or 10
carts.default_attach = {x=0, y=-3+ah, z=-2}

function carts:manage_attachment(player, obj)
	if not player then
		return
	end
	local status = obj ~= nil
	local player_name = player:get_player_name()
	if player_api.player_attached[player_name] == status then
		return
	end
	player_api.player_attached[player_name] = status

	if status then
		player:set_attach(obj, "", carts.default_attach, {x=0, y=0, z=0})
		player:set_eye_offset({x=0, y=-4, z=0},{x=0, y=-4, z=0})
	else
		player:set_detach()
		player:set_eye_offset({x=0, y=0, z=0},{x=0, y=0, z=0})
		-- HACK in effect! Force updating the attachment rotation
		player:set_properties({})
	end
end

function carts:velocity_to_dir(v)
	if abs(v.x) > abs(v.z) then
		return {x=sign(v.x), y=sign(v.y), z=0}
	else
		return {x=0, y=sign(v.y), z=sign(v.z)}
	end
end

local get_node = minetest.get_node
local get_item_group = minetest.get_item_group
function carts:is_rail(pos, railtype)
	if not minetest.is_valid_pos(pos) then
		return false
	end

	local node = get_node(pos).name
	if node == "ignore" then
		local vm = minetest.get_voxel_manip()
		local emin, emax = vm:read_from_map(pos, pos)
		local area = VoxelArea:new{
			MinEdge = emin,
			MaxEdge = emax,
		}
		local data = vm:get_data()
		local vi = area:indexp(pos)
		node = minetest.get_name_from_content_id(data[vi] or 0)
	end
	if get_item_group(node, "rail") == 0 then
		return false
	end
	if not railtype then
		return true
	end
	return get_item_group(node, "connect_to_raillike") == railtype
end

function carts:check_front_up_down(pos, dir_, check_up, railtype)
	local dir = vector_new(dir_)
	local cur

	-- Front
	dir.y = 0
	cur = vector_add(pos, dir)
	if carts:is_rail(cur, railtype) then
		return dir
	end
	-- Up
	if check_up then
		dir.y = 1
		cur = vector_add(pos, dir)
		if carts:is_rail(cur, railtype) then
			return dir
		end
	end
	-- Down
	dir.y = -1
	cur = vector_add(pos, dir)
	if carts:is_rail(cur, railtype) then
		return dir
	end
	return nil
end

function carts:get_rail_direction(pos_, dir, ctrl, old_switch, railtype)
	local pos = vector_round(pos_)
	local cur
	local left_check, right_check = true, true

	-- Check left and right
	local left = {x=0, y=0, z=0}
	local right = {x=0, y=0, z=0}
	if dir.z ~= 0 and dir.x == 0 then
		left.x = -dir.z
		right.x = dir.z
	elseif dir.x ~= 0 and dir.z == 0 then
		left.z = dir.x
		right.z = -dir.x
	end

	local straight_priority = ctrl and dir.y ~= 0

	-- Normal, to disallow rail switching up- & downhill
	if straight_priority then
		cur = self:check_front_up_down(pos, dir, true, railtype)
		if cur then
			return cur
		end
	end

	if ctrl then
		if old_switch == 1 then
			left_check = false
		elseif old_switch == 2 then
			right_check = false
		end
		if ctrl.left and left_check then
			cur = self:check_front_up_down(pos, left, false, railtype)
			if cur then
				return cur, 1
			end
			left_check = false
		end
		if ctrl.right and right_check then
			cur = self:check_front_up_down(pos, right, false, railtype)
			if cur then
				return cur, 2
			end
			right_check = true
		end
	end

	-- Normal
	if not straight_priority then
		cur = self:check_front_up_down(pos, dir, true, railtype)
		if cur then
			return cur
		end
	end

	-- Left, if not already checked
	if left_check then
		cur = carts:check_front_up_down(pos, left, false, railtype)
		if cur then
			return cur
		end
	end

	-- Right, if not already checked
	if right_check then
		cur = carts:check_front_up_down(pos, right, false, railtype)
		if cur then
			return cur
		end
	end

	-- Backwards
	if not old_switch then
		cur = carts:check_front_up_down(pos, {
				x = -dir.x,
				y = dir.y,
				z = -dir.z
			}, true, railtype)
		if cur then
			return cur
		end
	end

	return {x=0, y=0, z=0}
end

function carts:pathfinder(pos_, old_pos, old_dir, distance, ctrl,
		pf_switch, railtype)

	local pos = vector_round(pos_)
	if vector_equals(old_pos, pos) then
		return
	end

	local pf_pos = vector_round(old_pos)
	local pf_dir = vector_new(old_dir)
	distance = min(carts.path_distance_max,
		floor(distance + 1))

	for _ = 1, distance do
		pf_dir, pf_switch = self:get_rail_direction(
			pf_pos, pf_dir, ctrl, pf_switch or 0, railtype)

		if vector_equals(pf_dir, {x=0, y=0, z=0}) then
			-- No way forwards
			return pf_pos, pf_dir
		end

		pf_pos = vector_add(pf_pos, pf_dir)

		if vector_equals(pf_pos, pos) then
			-- Success! Cart moved on correctly
			return
		end
	end
	-- Not found. Put cart to predicted position
	return pf_pos, pf_dir
end

function carts:boost_rail(pos, amount)
	minetest.get_meta(pos):set_string("cart_acceleration", tostring(amount))
	for _, obj_ in pairs(minetest.get_objects_inside_radius(pos, 0.5)) do
		if not obj_:is_player() and
				obj_:get_luaentity() and
				obj_:get_luaentity().name == "carts:cart" then
			obj_:get_luaentity():on_punch()
		end
	end
end

function carts:register_rail(name, def_overwrite)
	local def = {
		drawtype = "raillike",
		paramtype = "light",
		sunlight_propagates = true,
		is_ground_content = false,
		walkable = false,
		selection_box = {
			type = "fixed",
			fixed = {-1/2, -1/2, -1/2, 1/2, -1/2+1/16, 1/2}
		},
		sounds = default.node_sound_metal_defaults()
	}
	for k, v in pairs(def_overwrite) do
		def[k] = v
	end
	if not def.inventory_image then
		def.wield_image = def.tiles[1]
		def.inventory_image = def.tiles[1]
	end

	minetest.register_node(name, def)
end

function carts:get_rail_groups(additional_groups)
	-- Get the default rail groups and add more when a table is given
	local groups = {
		dig_immediate = 2,
		falling_node = 1,
		rail = 1,
		connect_to_raillike = minetest.raillike_group("rail")
	}
	if type(additional_groups) == "table" then
		for k, v in pairs(additional_groups) do
			groups[k] = v
		end
	end
	return groups
end
