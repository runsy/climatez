local modpath = ...
local climatez = {}
climatez.wind = {}
climatez.climates = {}
climatez.players = {}
climatez.settings = {}

--Settings

local settings = Settings(modpath .. "/settingtypes.txt")

climatez.settings.climate_min_height = tonumber(settings:get("climate_min_height"))
climatez.settings.climate_change_ratio = tonumber(settings:get("climate_change_ratio"))
climatez.settings.radius = tonumber(settings:get("climate_radius"))
climatez.settings.climate_duration = tonumber(settings:get("climate_duration"))
climatez.settings.duration_random_ratio = tonumber(settings:get("climate_duration_random_ratio"))

local climate_max_height = tonumber(minetest.settings:get('cloud_height', true)) or 120
local check_light = minetest.is_yes(minetest.settings:get_bool('light_roofcheck', true))

--Helper Functions

local function player_inside_climate(player_pos)
	--check altitude
	if (player_pos.y < climatez.settings.climate_min_height) or (player_pos.y > climate_max_height) then
		return false
	end
	--check if on water
	local node_name = minetest.get_node(player_pos).name
	if minetest.registered_nodes[node_name] and (
		minetest.registered_nodes[node_name]["liquidtype"] == "source" or
		minetest.registered_nodes[node_name]["liquidtype"] == "flowing") then
			return false
	end
	--If sphere's centre coordinates is (cx,cy,cz) and its radius is r,
	--then point (x,y,z) is in the sphere if (x−cx)2+(y−cy)2+(z−cz)2<r2.
	for i, climate in ipairs(climatez.climates) do
		local climate_center = climatez.climates[i].center
		if climatez.settings.radius > math.sqrt((player_pos.x - climate_center.x)^2+
			(player_pos.y - climate_center.y)^2 +
			(player_pos.z - climate_center.z)^2
			) then
				return i
		end
	end
	return false
end

local function has_light(minp, maxp)
	local manip = minetest.get_voxel_manip()
	local e1, e2 = manip:read_from_map(minp, maxp)
	local area = VoxelArea:new{MinEdge=e1, MaxEdge=e2}
	local data = manip:get_light_data()
	local node_num = 0
	local light = false

	for i in area:iterp(minp, maxp) do
		node_num = node_num + 1
		if node_num < 5 then
			if data[i] and data[i] == 15 then
				light = true
				break
			end
		else
			node_num = 0
		end
	end

	return light
end

local function array_remove(tab, idx)
	tab[idx] = nil
	local new_tab = {}
	for _, value in pairs(tab) do
		new_tab[ #new_tab+1] = value
	end
	return new_tab
end

--DOWNFALLS REGISTRATIONS

climatez.registered_downfalls = {}

local function register_downfall(name, def)
	local new_def = table.copy(def)
	climatez.registered_downfalls[name] = new_def
end

register_downfall("rain", {
	min_pos = {x = -15, y = 10, z = -15},
	max_pos = {x = 15, y = 10, z = 15},
	falling_speed = 10,
	amount = 25,
	exptime = 1,
	size = 1,
	texture = "climatez_rain.png",
})

register_downfall("snow", {
	min_pos = {x = -15, y = 10, z= -15},
	max_pos = {x = 15, y = 10, z = 15},
	falling_speed = 5,
	amount = 15,
	exptime = 7,
	size = 1,
	texture= "climatez_snow.png",
})

register_downfall("sand", {
	min_pos = {x = -20, y = -4, z = -20},
	max_pos = {x = 20, y = 4, z = 20},
	falling_speed = -1,
	amount = 40,
	exptime = 1,
	size = 1,
	texture = "climatez_sand.png",
})

--WIND STUFF

local function create_wind()
	local wind = {
		x = math.random(0,5),
		y = 0,
		z = math.random(0,5)
	}
	return wind
end

function get_player_wind(player)
	local player_pos = player:get_pos()
	local climate_id = player_inside_climate(player_pos)
	if climate_id then
		return climatez.climates[climate_id].wind
	else
		return create_wind()
	end
end

--CLIMATE FUNCTIONS

local function create_climate(player)
	--get some data
	local player_pos = player:get_pos()
	local biome_data = minetest.get_biome_data(player_pos)
	local biome_heat = biome_data.heat
	local biome_humidity = biome_data.humidity

	local downfall

	if biome_heat > 40 and biome_humidity > 50 then
		downfall = "rain"
	elseif biome_heat > 50 and biome_humidity < 20  then
		downfall = "sand"
	else
		downfall = "snow"
	end

	if not downfall then
		return
	end

	--create wind
	local wind = create_wind()

	--create climate
	local climate_id = #climatez.climates+1
	climatez.climates[climate_id] = {
		center = player_pos,
		downfall = downfall,
		wind = wind,
	}

	--save the player
	local player_name = player:get_player_name()
	climatez.players[player_name] = climate_id

	--program climate's end
	local climate_duration = climatez.settings.climate_duration
	local climate_duration_random_ratio = climatez.settings.duration_random_ratio
	local random_end_time = (math.random(climate_duration- (climate_duration*climate_duration_random_ratio),
		climate_duration+ (climate_duration*climate_duration_random_ratio)))
	minetest.after(random_end_time, function()
		--remove the player
		for _player_name, _climate_id in pairs(climatez.players) do
			if _climate_id == climate_id then
				climatez.players[_player_name] = nil
			end
		end
		--remove the climate
		climatez.climates = array_remove(climatez.climates, climate_id)
	end)
end

local function apply_climate(player, climate_id)

	local player_pos = player:get_pos()
	local climate = climatez.climates[climate_id]
	local downfall = climatez.registered_downfalls[climate.downfall]
	local wind = climatez.climates[climate_id].wind
	local wind_pos = vector.multiply(wind, -1)
	local minp = vector.add(vector.add(player_pos, downfall.min_pos), wind_pos)
	local maxp = vector.add(vector.add(player_pos, downfall.max_pos), wind_pos)

	--Check if in player in interiors or not
	if check_light and not has_light(minp, maxp) then
		return
	end

	local vel = {x = wind.x, y = - downfall.falling_speed, z = wind.z}
	local acc = {x = 0, y = 0, z = 0}
	local exp = downfall.exptime

	minetest.add_particlespawner({
		amount = downfall.amount, time=0.5,
		minpos = minp, maxpos = maxp,
		minvel = vel, maxvel = vel,
		minacc = acc, maxacc = acc,
		minexptime = exp, maxexptime = exp,
		minsize = downfall.size, maxsize= downfall.size,
		collisiondetection = true, collision_removal = true,
		vertical = true,
		texture = downfall.texture, playername = player:get_player_name()
	})
end

--CLIMATE CORE: GLOBALSTEP

local timer = 0
minetest.register_globalstep(function(dtime)
	timer = timer + dtime;
	if timer >= 1 then
		for _, player in ipairs(minetest.get_connected_players()) do
			local _player_name = player:get_player_name()
			local player_pos = player:get_pos()
			local climate_id = player_inside_climate(player_pos)
			local _climate_id = climatez.players[_player_name]
			if  climate_id and _climate_id then --if already in a climate, check if still inside it
				if not climate_id == _climate_id then
					climatez.players[_player_name] = nil
				end
			elseif climate_id and not(_climate_id) then --another player enter into the climate
				--minetest.chat_send_all(_player_name.." enter into the climate")
				climatez.players[_player_name] = climate_id
			else --chance to create a climate
				local chance = math.random(climatez.settings.climate_change_ratio)
				if chance == 1 then
					--minetest.chat_send_all(_player_name.." create climate")
					create_climate(player)
				end
			end
		end
		timer = 0
	end
	for _player_name, _climate_id in pairs(climatez.players) do
		local player = minetest.get_player_by_name(_player_name)
		if player then
			apply_climate(player, _climate_id)
		else
			climatez.players[_player_name] = nil
		end
	end
end)
