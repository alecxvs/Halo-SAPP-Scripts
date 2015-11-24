--[[
      Spawn Editor by SonicXVe
      Version 1.0

        This script allows you to save your current position and rotation
      in the game with a vehicle name to facilitate custom vehicle spawns.
      This script does not spawn vehicles in itself (yet). Vehicle position
      and rotation are output to a json file which can be edited by hand
      or shared with others.

      Credits:
        Structure based on: Time Remaining by 002
        Coordinate and rotation logic from: Object Tag Info Utility by H® Shaft
        Json parsing is handled by: JSON by Jeffrey Friedl (http://regex.info/code/JSON.lua)
          + The JSON.lua file for this should be distributed with this script
              and installed in sapp/lua as well.
]]--

api_version = "1.9.0.0"


ADMIN_LEVEL = 4
ADD_SPAWN_SYNTAX = "Syntax: +spawn (@<player_index>) <vehicle> ((~)<gametype>)"
VEHICLES = {
  ghost = "vehicles\\ghost\\ghost_mp",
  banshee = "vehicles\\banshee\\banshee_mp",
  scorpion = "vehicles\\scorpion\\scorpion_mp",
  warthog = "vehicles\\warthog\\mp_warthog",
  rwarthog = "vehicles\\rwarthog\\rwarthog",
  turret = "vehicles\\c gun turret\\c gun turret_mp"
}

GAMETYPES = {
  "slayer",
  "oddball",
  "king",
  "ctf",
  "race"
}

SCHEMA_VERSION = 1

local game_started = false
local spawned_vehicles = {}

function OnScriptLoad()
  register_callback(cb['EVENT_COMMAND'], "OnCommand")
  register_callback(cb['EVENT_GAME_START'], "OnNewGame")
  Commander:RegisterCommand("+spawn", Command_AddSpawn)

  if get_var(0, "$gt") ~= "n/a" then
		game_started = true
	end
end
function OnScriptUnload() end

function OnNewGame()
  game_started = true
  local map_name = get_var(0, "$map")
  local gametype = get_var(0, "$gt")
  local variant = get_var(0, "$mode")

  local status, vehicle_spawns = ReadVehicleSpawns()

  --Spawn all the vehicles!
  if status and vehicle_spawns[map_name] then
    local default_spawns = vehicle_spawns[map_name].default or {}
    local gametype_spawns = vehicle_spawns[map_name].gametypes[gametype] or {}
    local variant_spawns = vehicle_spawns[map_name].variants[variant] or {}
    local tags_used = {}

    for _, spawnlist in ipairs({variant_spawns, gametype_spawns, default_spawns}) do
      for tag, spawns in pairs(spawnlist) do
        if not tags_used[tag] then
          tags_used[tag] = true
          for i, spawn in ipairs(spawns) do
            table.insert(spawned_vehicles, spawn_object("vehi", tag, spawn.x, spawn.y, spawn.z, spawn.rot))
          end
        end
      end
    end
  end
end

function OnCommand(a, b, c, d)
  return Commander:OnCommand(a, b, c, d)
end

function SyntaxError(msg)
  return msg and {msg, ADD_SPAWN_SYNTAX} or ADD_SPAWN_SYNTAX
end

function ReadVehicleSpawns()
  cprint("Reading vehicles.json...")
  local status, output = false, {}
  local vehi_file, err = io.open("vehicles.json", "r")
  local vehicle_spawns = {}
  if vehi_file then
    status, output = pcall(function() return JSON:decode(vehi_file:read("*a")) end)
    vehi_file:close()
  else
    local newfile = io.open("vehicles.json", "w")
    newfile:close()
    return true, {}
  end
  return status, err or output or {}
end

function WriteVehicleSpawns(vehicle_spawns)
  cprint("Writing vehicles.json...")
  vehi_file = io.open("vehicles.json", "w")
  vehi_file:write(JSON:encode_pretty(vehicle_spawns))
  vehi_file:close()
end

function ParseGametype(name)
  if string.sub(name, 1, 1) == "~" then
    gametype = string.sub(name, 2, #name)
    for k,_ in pairs(GAMETYPES) do
      if k == gametype then return "gametype", gametype end
    end
    return "gametype", false
  end
  return "variant", name
end

--[[
    Command: +spawn
    Parameters:
      target_index (optional for players)
          Index of player whose coordinates will be saved. Defaults to the player executing the command (if applicable).
          This parameter is required if executing from console.
          Syntax: @<index>, where index is a player index (example: @1)

      vehicle [required]
          Name of the vehicle to spawn at the player's coordinates.
          Syntax: Must be ghost, scorpion, banshee, warthog, rwarthog, or turret

      gametype (optional)
          Name of the gametype to spawn the vehicle for. Defaults to "any"
          Syntax: Specific name of gametype, or ~<gametype> for general types, or "any" (example: "my_fun_slayer" or "~slayer")

]]--
function Command_AddSpawn( ply_index, cmd, args )
  if ply_index and ply_index ~= 0 and tonumber(get_var(ply_index, "$lvl")) < ADMIN_LEVEL then
      return "Insufficient permission to create spawns"
  end

  local target_index = 0
  local vehicle = ""
  local gametype = "any"
  local variant = false

  --Get target_index if specified (and then remove it from args)
  if args[1] then
    if string.sub(args[1], 1, 1) == "@" then
      local str_target_index = string.gsub(table.remove(args, 1), "@(%d+)", "%1")
      target_index = tonumber(str_target_index)
      if not target_index then
        return SyntaxError("Invalid target_index, did not resolve to a player index.")
      end
    else
      if ply_index ~= 0 then target_index = ply_index
      else return SyntaxError("You must specify a target index!") end
    end
  else return SyntaxError() end

  --Get vehicle name
  if args[1] then
    vehicle = VEHICLES[args[1]]
    if not vehicle then
      return SyntaxError("Unknown vehicle. Valid options are: ghost, scorpion, banshee, warthog, rwarthog, turret")
    end
  else return SyntaxError("You must specify a vehicle name!") end

  --Get gametype if specified
  if args[2] then
    local type, result = ParseGametype(args[2])
    if type == "variant" then variant = result elseif result then gametype = result
    else return SyntaxError("Invalid gametype. Valid options are: slayer, oddball, king, ctf, race") end
  end

  --version = vehicle_spawns["schema_version"] or vehicle_spawns["schema_version"] = SCHEMA_VERSION

  local player_object = get_dynamic_player(target_index)
  local player_static = get_player(target_index)
  local x, y, z = read_vector3d(player_object + 0x5C)
  local rotation = read_float(player_static + 0x138)
  local map_name = get_var(0, "$map")

  local status, vehicle_spawns = ReadVehicleSpawns()

  if not status then
    if type(vehicle_spawns) == "table" then
      if vehi_json then
        local backup = assert(io.open("vehicles.json.backup", "w"))
        backup:write(vehi_json)
        backup:close()
      end
    else
      return "An error has occurred in opening vehicles.json!"
    end
  end

  if not vehicle_spawns[map_name] then
    vehicle_spawns[map_name] = {
      default = {},
      gametypes = {
        slayer = {},
        ctf = {},
        oddball = {},
        king = {},
        race = {}
      },
      variants = {}
    }
  end

  local context = variant and vehicle_spawns[map_name].variants[variant] or
                  gametype ~= "any" and vehicle_spawns[map_name].gametypes[gametype] or
                  vehicle_spawns[map_name].default

  if not context[vehicle] then context[vehicle] = {} end

  local vehi_spawn = {
    x = x,
    y = y,
    z = z,
    rot = rotation
  }
  table.insert(context[vehicle], vehi_spawn)

  WriteVehicleSpawns(vehicle_spawns)

  cprint("Added new vehicle spawn:")
  cprint(JSON:encode_pretty(vehi_spawn))

  local new_vehicle = spawn_object("vehi", vehicle, x, y, z, rotation)
  enter_vehicle(new_vehicle, target_index, 0)


  return {
    "Added new vehicle spawn for "..vehicle.." on "..map_name.."!",
    "X: " .. x .. " Y: " .. y .. " Z: " .. z .. " R: " .. rotation
  }
end

JSON = require "JSON"
Commander = require "commander"
