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
//, package.seeall
local table = table
local hook = hook
local coroutine = coroutine 

local coroutine_resume = coroutine.resume
local coroutine_yield = coroutine.yield

local concat = table.concat
local type = type 
local CurTime = CurTime 
local Vector = Vector 
local tonumber = tonumber 
local tostring = tostring 
local pairs = pairs 
local setmetatable = setmetatable 
local Angle = Angle 
local pcall = pcall 
local unpack = unpack 
local ErrorNoHalt = ErrorNoHalt 
local AccessorFunc = AccessorFunc 
local SysTime = SysTime 
local CreateConVar = CreateConVar 
local FrameTime = FrameTime 

local PrintTable = PrintTable 
local MsgN = MsgN 

module("photocopy.util")

--- Creates a new class (a table) that is callable.
-- @param parent Optional parent table (__index = parent)
-- @return Callable table
function CreateClass(parent)
    local cls = {}
    
    return setmetatable(cls, {
        __call = function(self, ...)
            local args = {...}
            local instance = {}
            setmetatable(instance, { __index = cls })
            if cls.__construct then
                instance:__construct(unpack(args))
            elseif type(args[1]) == 'table' then
                for k, v in pairs(args[1]) do
                    instance[k] = v
                end
            end
            
            return instance
        end,
        __index = parent
    })
end

--- Makes sure that the returned value is indeed a Vector. This function
-- accepts Vectors, tables, and anything else. A vector at 0, 0, 0 will
-- be returned if the data is invalid.
-- @param val Value of any type
-- @return Vector
function CastVector(val)
    if type(val) == 'Vector' then
        return val
    elseif type(val) == 'table' then
        return Vector(tonumber(val[1]) or 0,
                      tonumber(val[2]) or 0,
                      tonumber(val[3]) or 0)
    else
        return Vector(0, 0, 0)
    end
end

--- Makes sure that the return value is actually an Angle. This function
-- accepts Angles, tables, and anything else. An angle of 0, 0, 0 will be
-- returned in lieu of a valid Angle.
-- @param val Value
-- @return Angle
function CastAngle(val)
    if type(val) == 'Angle' then
        return val
    elseif type(val) == 'table' then
        return Angle(tonumber(val[1]) or 0,
                     tonumber(val[2]) or 0,
                     tonumber(val[3]) or 0)
    else
        return Angle(0, 0, 0)
    end
end

--- Returns a table for sure.
-- @param val
-- @return Table
function CastTable(val)
    if type(val) == 'table' then
        return val
    else
        return {}
    end
end

--- Runs a function and catches errors, without caring about the return
-- value of the function. Errors will be raised as a Lua error, but it
-- will not end execution.
-- @param f Function to call
-- @param ... Arguments
function ProtectedCall(f, ...)
    local args = {...}
    local ret, err = pcall(f, unpack(args, 1, table.maxn(args)))
    if not ret then
        ErrorNoHalt(err)
        return false
    end
    return true
end

--- Freeze all the physics objects of an entity.
-- @param ent
function FreezeAllPhysObjs(ent)
    for bone = 0, ent:GetPhysicsObjectCount() - 1 do
        local physObj = ent:GetPhysicsObjectNum(bone)
        
        if physObj:IsValid() then
            physObj:EnableMotion(false)
        end
    end
end

------------------------------------------------------------
-- ProcessManager
------------------------------------------------------------
-- this convar means that when it's set to 50, it will take 50 miliseconds of processing time AT 100 frames per second
local alloted 
if CLIENT then
    alloted = CreateClientConVar("photocopy_process_speed_miliseconds_cl", "100", { FCVAR_ARCHIVE })
else
    alloted = CreateConVar("photocopy_process_speed_miliseconds_sv", "30", { FCVAR_ARCHIVE })
end

ProcessManager = {
}
local start , thread = SysTime()
local totaltime , hightime , medtime , lowtime
local stack = {
    high = {},
    med = {},
    low = {},
}

hook.Add("Think", "PhotocopyIterativeProcessor" , function()
    start = SysTime()

    totaltime = ProcessManager.GetProcessTime()
    hightime = totaltime * 2/3
    medtime = totaltime * 1/4
    lowtime = totaltime * 1/12

    if not stack.high[1] then 
        medtime = medtime + hightime
    else
        while (start + hightime) > SysTime() do
            if not ProcessManager.Process( stack.high[1] , "high" ) then
                break 
            end
        end
    end

    if not stack.med[1] then
        lowtime = lowtime + medtime
    else
        while (start + medtime) > SysTime() do
            if not ProcessManager.Process( stack.med[1] , "med" ) then
                break 
            end
        end
    end

    if not stack.low[1] then
        hightime = hightime + lowtime
    else
        while (start + lowtime) > SysTime() do
            if not ProcessManager.Process( stack.low[1] , "low" ) then
                break 
            end
        end
    end
end)

function ProcessManager.GetProcessTime()
    return (1/((FrameTime()) *100)) * ( alloted:GetInt() / 1000 )
end

function ProcessManager.AddToProcessors( priority , processor )
    if priority < 0.1 then
        stack.high[ #stack.high + 1 ] = processor
    elseif priority < 0.2 then
        stack.med[ #stack.med + 1 ] = processor
    else
        stack.low[ #stack.low + 1 ] = processor
    end
end

function ProcessManager.Process( processor ,priority)
    if not processor:Advance() then
        processor.Finished = true
        processor:Stop()
        table.remove( stack[priority] , 1 )
        return false
    end
    return true
end

------------------------------------------------------------
-- IterativeProcessor
------------------------------------------------------------

IterativeProcessor = CreateClass()

-- Constructor.
function IterativeProcessor:__construct(data)
    self.Progress = 0
    self.Finished = false
    self.Error = nil
    self.Warnings = {}
    self.Callbackargs = {}
    self.Priority = 0
    self.NextFunc = nil

    self.Thread = coroutine.create( function( self ) 
        while self.Runtimes > self.Timesrun do
            self.NextFunc( self )
            self.Timesrun = self.Timesrun + 1
            coroutine_yield()
        end

        return false
    end)
    self.Runtimes = 0
    self.Timesrun = 0
end

function IterativeProcessor:OnSuccess() end
function IterativeProcessor:OnError() end

function IterativeProcessor:Start(callback, errback , ...)
    if callback then
        self.Callbackargs = {...}
        self.OnSuccess = callback
        self.OnError = errback
    end

    ProcessManager.AddToProcessors( self.Priority , self )
end

function IterativeProcessor:Stop()
    if self.Finished then
        self:OnSuccess(unpack(self.Callbackargs))
    elseif self.OnError then
        self:OnError(unpack(self.Callbackargs))
    end
end

function IterativeProcessor:SetNext(t, func)
    self.Priority = t
    self.Runtimes = self.Runtimes + 1

    if func then
        self.NextFunc = func
    end
    if func == false then self.NextFunc = nil end
end

function IterativeProcessor:Advance()
    if self:GetError() then return false end
    
    if self.Thread then
        return coroutine_resume( self.Thread , self )
    else
        return false
    end
end

function IterativeProcessor:IsFinished()
    return self:GetError() ~= nil or self.Finished
end

function IterativeProcessor:SetFinished(finished)
    self.Finished = finished
end

function IterativeProcessor:Warn(errorCode, ...)
    self.Warnings[#self.Warnings + 1] = { errorCode, unpack({...}) }
end

function IterativeProcessor:SetError(err, ...)
    if not self.Error then
        self:OnError(err,unpack(self.Callbackargs))
    end
    self.Error = err
end

function IterativeProcessor:GetError()
    return self.Error
end

function IterativeProcessor:GetWarnings()
    return self.Warnings
end

function IterativeProcessor:Complete()
    self:Stop() -- remove hook
    
    -- Warning: Infinite loop check may trigger
    while self:Advance() do end
    
    if self:GetError() then
        return false, self:GetError()
    else
        return true
    end
end

AccessorFunc(IterativeProcessor, "Progress", "Progress")

------------------------------------------------------------
-- Buffer
------------------------------------------------------------

Buffer = CreateClass()

-- Constructor.
function Buffer:__construct()
    -- Strings are immutable
    self.Output = {}
end

function Buffer:Write(str)
    self.Output[#self.Output + 1] = str
end

function Buffer:GetValue()
    return concat(self.Output, "")
end