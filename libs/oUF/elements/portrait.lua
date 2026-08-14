--[[
# Element: Portraits

Handles the updating of the unit's portrait.

## Widget

Portrait - A `PlayerModel` or a `Texture` used to represent the unit's portrait.

## Notes

A question mark model will be used if the widget is a PlayerModel and the client doesn't have the model information for
the unit.

## Options

.showClass - Displays the unit's class in the portrait (boolean)

## Examples

    -- 3D Portrait
    -- Position and size
    local Portrait = CreateFrame('PlayerModel', nil, self)
    Portrait:SetSize(32, 32)
    Portrait:SetPoint('RIGHT', self, 'LEFT')

    -- Register it with oUF
    self.Portrait = Portrait

    -- 2D Portrait
    local Portrait = self:CreateTexture(nil, 'OVERLAY')
    Portrait:SetSize(32, 32)
    Portrait:SetPoint('RIGHT', self, 'LEFT')

    -- Register it with oUF
    self.Portrait = Portrait
--]]

local _, ns = ...
local oUF = ns.oUF
local Private = oUF.Private

local unitIsUnit = Private.unitIsUnit

local function Update(self, event, unit)
	if(not unit or not unitIsUnit(self.unit, unit)) then return end

	local element = self.Portrait

	--[[ Callback: Portrait:PreUpdate(unit)
	Called before the element has been updated.

	* self - the Portrait element
	* unit - the unit for which the update has been triggered (string)
	--]]
	if(element.PreUpdate) then element:PreUpdate(unit) end

	local guid = UnitGUID(unit)

	-- THUGUI LOCAL PATCH -- not upstream oUF. Re-apply if this library is
	-- updated; upstream guards the `guid` half just below and leaves this half
	-- unguarded.
	--
	-- `UnitIsConnected(unit) and UnitIsVisible(unit)` performs a truth test on
	-- each return, and those may be SECRET booleans. Every operation this
	-- function then does with the result -- `and`, `~=` on line below, `not`
	-- in the branch further down -- is one that throws on a secret. oUF is
	-- vendored under our name so any error here reports as ThugUI's
	-- (DECISIONS.md §12), which is what made this look like a taint problem
	-- rather than the ordinary bug it is.
	--
	-- issecretvalue is asked FIRST, before any test of the values themselves:
	-- comparing a secret to anything, nil included, is itself the operation
	-- that errors (Tests/README.md, "the secret stub does not throw on a nil
	-- comparison").
	local connected = UnitIsConnected(unit)
	local visible = UnitIsVisible(unit)
	local isAvailable = true
	if(not issecretvalue(connected) and not issecretvalue(visible)) then
		isAvailable = (connected and visible) and true or false
	end
	-- Fails OPEN when unreadable: the unit is treated as available, so the
	-- real portrait keeps drawing. The alternative failure is replacing a
	-- perfectly good portrait with a question mark every combat, which is a
	-- visible regression where a stale portrait is not.

	local hasStateChanged = event ~= 'OnUpdate'
		or (not issecretvalue(guid) and not issecretvalue(element.guid) and element.guid ~= guid)
		or element.state ~= isAvailable

	if(hasStateChanged) then
		if(element:IsObjectType('PlayerModel')) then
			if(not isAvailable) then
				element:SetCamDistanceScale(0.25)
				element:SetPortraitZoom(0)
				element:SetPosition(0, 0, 0.25)
				element:ClearModel()
				element:SetModel([[Interface\Buttons\TalkToMeQuestionMark.m2]])
			else
				element:SetCamDistanceScale(1)
				element:SetPortraitZoom(1)
				element:SetPosition(0, 0, 0)
				element:ClearModel()
				element:SetUnit(unit)
			end
		else
			local class, _
			if(element.showClass) then
				_, class = UnitClass(unit)
			end

			if(class) then
				element:SetAtlas('classicon-' .. class)
			else
				SetPortraitTexture(element, unit)
			end
		end

		element.guid = guid
		element.state = isAvailable
	end

	--[[ Callback: Portrait:PostUpdate(unit)
	Called after the element has been updated.

	* self            - the Portrait element
	* unit            - the unit for which the update has been triggered (string)
	* hasStateChanged - indicates whether the state has changed since the last update (boolean)
	--]]
	if(element.PostUpdate) then
		return element:PostUpdate(unit, hasStateChanged)
	end
end

local function Path(self, ...)
	--[[ Override: Portrait.Override(self, event, unit)
	Used to completely override the internal update function.

	* self  - the parent object
	* event - the event triggering the update (string)
	* unit  - the unit accompanying the event (string)
	--]]
	return (self.Portrait.Override or Update) (self, ...)
end

local function ForceUpdate(element)
	return Path(element.__owner, 'ForceUpdate', element.__owner.unit)
end

local function Enable(self, unit)
	local element = self.Portrait
	if(element) then
		element.__owner = self
		element.ForceUpdate = ForceUpdate

		self:RegisterEvent('UNIT_MODEL_CHANGED', Path)
		self:RegisterEvent('UNIT_PORTRAIT_UPDATE', Path)
		self:RegisterEvent('PORTRAITS_UPDATED', Path, true)
		self:RegisterEvent('UNIT_CONNECTION', Path)

		-- The quest log uses PARTY_MEMBER_{ENABLE,DISABLE} to handle updating of
		-- party members overlapping quests. This will probably be enough to handle
		-- model updating.
		if(unit == 'party' or unit == 'target') then
			self:RegisterEvent('PARTY_MEMBER_ENABLE', Path)
			self:RegisterEvent('PARTY_MEMBER_DISABLE', Path)
		end

		element:Show()

		return true
	end
end

local function Disable(self)
	local element = self.Portrait
	if(element) then
		element:Hide()

		self:UnregisterEvent('UNIT_MODEL_CHANGED', Path)
		self:UnregisterEvent('UNIT_PORTRAIT_UPDATE', Path)
		self:UnregisterEvent('PORTRAITS_UPDATED', Path)
		self:UnregisterEvent('PARTY_MEMBER_ENABLE', Path)
		self:UnregisterEvent('PARTY_MEMBER_DISABLE', Path)
		self:UnregisterEvent('UNIT_CONNECTION', Path)
	end
end

oUF:AddElement('Portrait', Path, Enable, Disable)
