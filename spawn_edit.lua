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
        Json parsing is handled by: JSON by Jeffrey Friedl
          + The JSON.lua file for this should be distributed with this script
              and installed in sapp/lua as well.
]]--

api_version = "1.9.0.0"


ADMIN_LEVEL = 4
ADD_SPAWN_SYNTAX = "Syntax: +spawn (@<player_index>) <vehicle> ((~)<gametype>)"
VEHICLES = {
  ghost = "",
  banshee = "",
  scorpion = "",
  warthog = "",
  rwarthog = "",
  turret = ""
}

GAMETYPES = {
  "slayer",
  "oddball",
  "king",
  "ctf",
  "race"
}

SCHEMA_VERSION = 1


function OnScriptLoad() register_callback(cb['EVENT_COMMAND'],"OnCommand") end
function OnScriptUnload() end

-- Print to rcon given a player, or else print to console.
function rcprint(ply_index, message)
  if ply_index then
    rprint(ply_index, message)
  else
    cprint(message)
  end
end

function ReplyFunction( environment )
  return (environment == 2 and say) or  -- If executed by player in chat, use say
         (rcprint)                      -- Else, use rcprint to handle rcon/console
end

function CheckCommand(cmd)
  if cmd == "+spawn" then return end
  return true
end

function ValidateGametype(gametype)
  for k,_ in pairs(GAMETYPES) do
    if k == gametype then return true end
  end
  return false
end

function ValidateVehicle(vehicle)
  for k,_ in pairs(VEHICLES) do
    if k == vehicle then return true end
  end
  return false
end

function OnCommand( ply_index, msg, env, rcon_pwd )
  local command = false
  local args = {}
  for str in string.gmatch(msg, "%S+") do
    if      command           then table.insert(args, str)
    elseif  CheckCommand(str) then return
    else    command = str     end
  end

  reply = ReplyFunction(env)

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

  if command == "+spawn" then
    if ply_index and tonumber(get_var(ply_index, "$lvl")) < ADMIN_LEVEL then
        reply(ply_index, "Insufficient permission to create spawns")
        return false
    end

    local target_index = 0
    local vehicle = ""
    local gametype = "any"
    local variant = false

    --Get target_index if specified (and then remove it from args)
    if args[1] then
      if string.sub(args[1], 1, 1) == "@" then
        target_index = tonumber(string.gsub(table.remove(args, 1), "%d+"))
        if not target_index then
          reply(ply_index, "Invalid target_index, did not resolve to a player index.")
          reply(ply_index, ADD_SPAWN_SYNTAX)
          return false
        end
      else
        if ply_index then
          target_index = ply_index
        else
          reply(ply_index, "You must specify a target index!")
          reply(ply_index, ADD_SPAWN_SYNTAX)
          return false
        end
      end
    else
      reply(ply_index, ADD_SPAWN_SYNTAX)
      return false
    end

    --Get vehicle name
    if args[1] then
      vehicle = args[1]
      if not ValidateVehicle(vehicle) then
        reply(ply_index, "Unknown vehicle. Valid options are: ghost, scorpion, banshee, warthog, rwarthog, turret")
        reply(ply_index, ADD_SPAWN_SYNTAX)
        return false
      end
    else
      reply(ply_index, "You must specify a vehicle name!")
      reply(ply_index, ADD_SPAWN_SYNTAX)
      return false
    end

    --Get gametype if specified
    if args[2] then
      if string.sub(args[2], 1, 1) == "~" then
        gametype = string.sub(args[2], 2, #args[2])

        if not ValidateGametype(gametype) then
          reply(ply_index, "Invalid gametype. Valid options are: slayer, oddball, king, ctf, race")
          reply(ply_index, ADD_SPAWN_SYNTAX)
          return false
        end
      else
        variant = args[2]
      end
    end

    cprint("Reading vehicles.json...")
    local vehi_file, err = io.open("vehicles.json", "r")
    local vehicle_spawns = {}
    if vehi_file then
      local vehi_json = vehi_file:read("*a")
      local status, output = pcall(function() return JSON:decode(vehi_json) end)
      if status then
        vehicle_spawns = output or {}
      else
        reply(ply_index, "WARNING: Could not parse vehicles.json. Malformed JSON?")
        reply(ply_index, "JSON Error: " .. output)
        if vehi_json then
          reply(ply_index, "The existing vehicles.json is being backed up and a new one will be created.")
          local backup = assert(io.open("vehicles.json.backup", "w"))
          backup:write(vehi_json)
          backup:close()
        end
      end
      vehi_file:close()
    end


    --version = vehicle_spawns["schema_version"] or vehicle_spawns["schema_version"] = SCHEMA_VERSION

    -- local target_index = 0
    -- local vehicle = ""
    -- local gametype = "any"
    -- local variant = ""
    local player_object = get_dynamic_player(target_index)
    local player_static = get_player(target_index)
    local x, y, z = read_vector3d(player_object + 0x5C)
    local rotation = read_float(player_static + 0x138)
    local map_name = get_var(0,"$map")

    if not vehicle_spawns[map_name] then vehicle_spawns[map_name] = {} end
    if not vehicle_spawns[map_name][vehicle] then vehicle_spawns[map_name][vehicle] = {} end

    local vehi_spawn = {
      x = x,
      y = y,
      z = z,
      rot = rotation
    }

    local gametypes_allowed = {}
    local variants_allowed = {}

    if gametype == "any" then
      gametypes_allowed = GAMETYPES
    elseif string.sub(gametype, 1, 1) == "~" then
      gametypes_allowed = {string.sub(gametype, 2, #gametype)}
    end

    if variant then
      variants_allowed = {gametype}
    end

    vehi_spawn["gametypes_allowed"] = gametypes_allowed
    vehi_spawn["variants_allowed"] = variants_allowed

    table.insert(vehicle_spawns[map_name][vehicle], vehi_spawn)

    cprint("Writing vehicles.json...")
    vehi_file = io.open("vehicles.json", "w")
    vehi_file:write(JSON:encode_pretty(vehicle_spawns))
    reply(ply_index, "Added new vehicle spawn for "..vehicle.." on "..map_name.."!")
    reply(ply_index, "X: " .. x .. " Y: " .. y .. " Z: " .. z .. " R: " .. rotation)
    vehi_file:close()
    cprint("Added new vehicle spawn:")
    cprint(JSON:encode_pretty(vehi_spawn))
  else
    return
  end

  return false
end

JSON = require "JSON"
