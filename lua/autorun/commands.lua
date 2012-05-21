-- MAKE COMMANDS POOLED AFTER THE ADDITION OF THE NET LIBRARY
-- ASWELL AS CHANGING THE FUNCTIONS TO UTILIZE THE NET LIBRARY
--[[
 local callbacks = {};
local function addcallback(name)
    callbacks[name] = true;
end
command.Add("mytoolabstractionies", function(ply, what, ...)
    if (not callbacks[what]) then return end
    local tool = ply:GetActiveWeapon();
    if (not bla bla bla bla) then return end
    tool[what](tool, ...)
end
--]]
require "glon"
Command = {}
local commands = {}
local cmdlookup = {}
local extraargs = {}

net.Receive("command_pool" , function(len,ply)
	cmdlookup[net.ReadString()] = net.ReadLong() 
end)

if SERVER then
	net.Receive("command_call",function(len,ply)
		local name = net.ReadLong()
		local args = glon.decode(util.Decompress(net.ReadString()))

		table.insert(args , 1 , ply)
		for i = 1 , #extraargs[ name ] do
			table.insert( args , 1 , extraargs[ name ][i])
		end
		
		if commands[name] then
			commands[name]( unpack(args) )
		end
	end)

	util.AddNetworkString("command_call")
	util.AddNetworkString("command_pool")
else
	net.Receive("command_call",function(len)
		local name = net.ReadLong()
		local args = glon.decode(net.ReadString())

		for i = 1 , #extraargs[ name ] do
			table.insert( args , 1 , extraargs[ name ][i])
		end
		
		if commands[name] then
			commands[name]( unpack(args) )
		end
	end)
end

function Command.Add( name , func , ... )
	local idx = #commands + 1
	cmdlookup[ name ] = idx
	commands[ idx ] = func
	extraargs[ idx ] = {...}

	net.Start("command_pool")
		net.WriteString( name )
		net.WriteLong( idx )
	if SERVER then net.Broadcast() else net.SendToServer() end
end

if SERVER then
	function Command.Call( name , ply , ...)
		net.Start("command_call")
			net.WriteLong(cmdlook[name])
			net.WriteString(util.Compress(glon.encode({...})))
		net.Send(ply)
	end
else
	function Command.Call( name , ... )
		net.Start("command_call")
			net.WriteLong(cmdlook[name])
			net.WriteString(util.Compress(glon.encode({...})))
		net.SendToServer()
	end
end