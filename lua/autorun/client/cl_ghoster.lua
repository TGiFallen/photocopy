-- Photocopy
-- Copyright (c) 2010 sk89q <http://www.sk89q.com>
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 2 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
-- 
-- $Id$

local putil = require("photocopy.util")
local photocopy = require("photocopy")

------------------------------------------------------------
-- Ghoster
------------------------------------------------------------
local Ghoster = putil.CreateClass(putil.IterativeProcessor)

--creates the ghoster class, used for controlling all ghosts
function Ghoster:__construct()
	putil.IterativeProcessor.__construct(self)
	self.Ghosts = {}
	self.Parent = nil
	self.Ply = LocalPlayer()
	self.offset = Vector(0,0,0)
	self.alpha = 150

	self:Hook()
end

function Ghoster:InitializeGhost()
	MsgN("received")
	if self.Initialized then
		self:RemoveGhosts()
	end

	self.Parent = net.ReadEntity()
	self.offset = Vector(net.ReadFloat(),net.ReadFloat(),net.ReadFloat())
	self.Pos = self.Parent:GetPos()
	self.Ang = self.Parent:GetAngles()

	self.Initialized = true

	self:ParentToMouse()
	self:SetNext(0,self.ParentToMouse)
	self:Start()
end

function Ghoster:ReceiveInfo()

	local model = net.ReadString()
	local pos = Vector( net.ReadFloat() , net.ReadFloat() , net.ReadFloat() )
	local angle = Angle( net.ReadFloat() , net.ReadFloat() , net.ReadFloat() ) 

	pos , angle = LocalToWorld(pos, angle, self.Pos, self.Ang)

	if not util.IsValidModel(model) then MsgN("Mising Model:",model)
		//notification.AddLegacy("Missing model:"..model, NOTIFY_ERROR, 5) return
	end
	local ent = ClientsideModel( model )
	ent:SetAngles( angle )
	ent:SetPos( pos )
	ent:SetParent(self.Parent)
	ent:SetRenderMode(1)
	ent:SetColor(Color(255,255,255,150))
	self.Ghosts[ent] = ent

	self:SetAlpha(self.alpha)
end

function Ghoster:Hook()
	net.Receive( "photocopy_ghost_init" , function(l) self:InitializeGhost() end)
	net.Receive( "photocopy_ghost_info" , function(l) self:ReceiveInfo() end)
end

function Ghoster:SetOffset( x , y , z )
	self.offset.x = x or self.offset.x
	self.offset.y = y or self.offset.y
	self.offset.z = z or self.offset.z
end

function Ghoster:ParentToMouse()
	if self.Initialized then
		local Pos = LocalPlayer():GetEyeTraceNoCursor().HitPos + self.offset
		self.Pos = Pos
		self.Parent:SetPos( Pos )
		self:SetNext(0)
	end
end

function Ghoster:RemoveGhosts()
	for k , ent in pairs(self.Ghosts) do
		if IsValid(ent) then
			ent:Remove()
		end
		self.Initialized = false
		self.Ghosts[ent] = nil
	end
end

function Ghoster:HideGhosts( b )
	if b then self:Stop() else self:SetNext(0) end
	for k , ent in pairs(self.Ghosts) do
		if IsValid(ent) then
			ent:SetNoDraw(b)
		else
			self.Ghosts[k] = nil
		end
	end
end

function Ghoster:SetAlpha(alpha)
	self.alpha = alpha
	for k , ent in pairs(self.Ghosts) do
		if IsValid(ent) then
			ent:SetColor(Color(255,255,255 ,alpha))
		else
			self.Ghosts[k] = nil
		end
	end
end

photocopy.Ghoster = Ghoster