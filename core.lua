-- ThugUI Core
-- A growing UI suite by Thug

ThugUI = ThugUI or {}
ThugUI.modules = {}

-- Addon info
ThugUI.name = "ThugUI"
ThugUI.version = "1.1.0"

-- Saved variables (initialized on load)
ThugUIDB = ThugUIDB or {}

-- Default settings structure
ThugUI.defaults = {
    CursorCooldowns = {
        enabled = true,
        showOnlyInCombat = true,
        updateFrequency = 0.016,  -- ~60fps, can be 0.033 for 30fps, 0.066 for 15fps
        
        -- GCD Ring (inner, thicker - Ring_20px)
        gcdRingSize = 36,
        gcdRingColor = {1, 1, 1, 0.9},
        useClassColor = true,
        
        -- Cast Ring (outer, thinner - Ring_10px)
        castRingSize = 48,
        castRingColor = {0.2, 0.8, 1, 0.9},
        
        -- Center dot
        centerDotSize = 8,
        centerDotColor = {1, 1, 1, 1},
        
        -- Essential Cooldowns anchoring
        anchorEssentialCooldowns = true,
        essentialCooldownsFrameName = "EssentialCooldownViewer",
        essentialCooldownsOffsetY = 50,
        essentialCooldownsScale = 1.0,
    },
    OrbAnchors = {
        enabled = true,
        -- Locked by default on purpose. Unlocked, OnDragStart fires on a
        -- couple of pixels of movement, so an ordinary click gets eaten as a
        -- drag and never reaches OnClick -- the orb feels like it only toggles
        -- sometimes. Locked, plain left-click always toggles and Shift+drag
        -- moves, which is what the orb tooltip already tells you.
        locked = true,
        chatOrb = {
            enabled = true,
            mode = 1, -- 1: Normal Chat, 2: Stream Box, 3: Hidden
            -- Same CC0 acorn as the objectives orb; the two are told apart by
            -- ring colour, tint and label rather than by different artwork.
            iconTexture = "Interface\\AddOns\\ThugUI\\media\\Acorn.tga",
            point = "BOTTOMLEFT",
            x = 25,
            y = 220,
            size = 36,
            color = {0.2, 0.7, 1.0, 0.9},
            streamWidth = 420,
            streamHeight = 220,
            fontSize = 14,
            fontOutline = "OUTLINE",
            showTimestamp = false,
            -- Stream box channel filters, toggled from the chat orb's
            -- right-click menu. Keys match CHANNEL_KEY_BY_EVENT in
            -- modules/OrbAnchors.lua; anything not explicitly false shows.
            -- CHANNEL covers Trade/General/custom and is off by default because
            -- a city's Trade chat buries everything else in the box.
            channels = {
                SAY = true,
                EMOTE = true,
                YELL = true,
                WHISPER = true,
                PARTY = true,   -- includes LFG/instance group chat
                RAID = true,
                GUILD = true,
                OFFICER = true,
                CHANNEL = false,
                SYSTEM = false,
            },
        },
        objectivesOrb = {
            enabled = true,
            visible = true, -- true: tracker shown, false: tracker hidden
            -- Acorn.tga is a CC0 (public domain, no attribution required)
            -- silhouette from Wikimedia Commons, redrawn white at 64x64 so the
            -- orb can tint it at runtime. Set to nil, or use
            -- "/orb icon obj none", to go back to the OBJ/OFF text badge.
            iconTexture = "Interface\\AddOns\\ThugUI\\media\\Acorn.tga",
            point = "TOPRIGHT",
            x = -260,
            y = -220,
            size = 36,
            color = {1.0, 0.82, 0.2, 0.9},
        },
    },
}

-- Class colors lookup
ThugUI.classColors = {
    WARRIOR = {0.78, 0.61, 0.43},
    PALADIN = {0.96, 0.55, 0.73},
    HUNTER = {0.67, 0.83, 0.45},
    ROGUE = {1.00, 0.96, 0.41},
    PRIEST = {1.00, 1.00, 1.00},
    DEATHKNIGHT = {0.77, 0.12, 0.23},
    SHAMAN = {0.00, 0.44, 0.87},
    MAGE = {0.41, 0.80, 0.94},
    WARLOCK = {0.58, 0.51, 0.79},
    MONK = {0.00, 1.00, 0.59},
    DRUID = {1.00, 0.49, 0.04},
    DEMONHUNTER = {0.64, 0.19, 0.79},
    EVOKER = {0.20, 0.58, 0.50},
}

function ThugUI:GetClassColor()
    local _, class = UnitClass("player")
    if class and self.classColors[class] then
        return unpack(self.classColors[class])
    end
    return 1, 1, 1
end

-- Helper for deep merging default tables into target tables
local function DeepMergeDefaults(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            DeepMergeDefaults(target[k], v)
        elseif target[k] == nil then
            if type(v) == "table" then
                target[k] = {}
                DeepMergeDefaults(target[k], v)
            else
                target[k] = v
            end
        end
    end
end

-- Initialize saved variables with defaults
function ThugUI:InitializeDB()
    for moduleName, moduleDefaults in pairs(self.defaults) do
        if not ThugUIDB[moduleName] then
            ThugUIDB[moduleName] = {}
        end
        DeepMergeDefaults(ThugUIDB[moduleName], moduleDefaults)
    end
end

-- Register a module
function ThugUI:RegisterModule(name, module)
    self.modules[name] = module
end

-- Event frame for core initialization
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "ThugUI" then
        ThugUI:InitializeDB()
        
        -- Initialize all registered modules
        for name, module in pairs(ThugUI.modules) do
            if module.Initialize then
                module:Initialize()
            end
        end
        
        print("|cff00ff00ThugUI|r v" .. ThugUI.version .. " loaded.")
        
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
