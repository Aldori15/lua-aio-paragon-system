-- --------------------------------
-- PARAGON SERVER CONFIGURATION
-- --------------------------------

local AIO = AIO or require("AIO")

local paragon = {
    config = {
        db_name = 'ac_eluna',

        pointsPerLevel = 1, -- number of stat points to grant per level of Paragon
        grantTalentPoints = true, -- Enable/disable talent points per level
        talentInterval = 5, -- Number of Paragon levels between talent point grants
        talentsPerLevel = 1, -- Number of talent points granted when eligible

        minPlayerLevel = 60, -- What level does the player need to be to unlock the Paragon XP system?
        expMax = 400, -- Base XP required for the first Paragon level.
        expScalingExponent = 1.2, -- Power-law exponent used to scale XP requirements as Paragon level increases.
        -- 1.0 produces linear growth
        -- Higher values make later levels scale more aggressively.
        -- Lower values produce a gentler progression curve.
        groupXpPenaltyStep = 0.1, -- % XP diminishing returns per extra group member (default 10%)

        fullXpRange = 5, -- Full XP if the enemy is no more than 5 levels below the player.
        halfXpRange = 10, -- 50% XP if the enemy is 6-10 levels below the player.
        halfXpMultiplier = 0.5,
        quarterXpRange = 15, -- 25% XP if the enemy is 11-15 levels below the player. More than 15 levels below grants no XP.
        quarterXpMultiplier = 0.25,

        showXPGainedMessages = true, -- Set to true to show XP gained messages, false to disable it.
        showTalentNotifications = true, -- Set to true to show talent point earned messages, false to disable it.
    },

    spells = {
        [7464] = 'Strength',
        [7468] = 'Intellect',
        [7471] = 'Agility',
        [7474] = 'Spirit',
        [7477] = 'Stamina',
        [7511] = 'Defense Rating',
    },
}

local paragon_addon = AIO.AddHandlers("AIO_Paragon", {})
paragon.account = {}
paragon.accountLoaded = {}

local HAS_PLAYERBOTS = type(GetPlayerbotsMgr) == "function"

local function ShouldSkipBot(player)
    if not HAS_PLAYERBOTS then return false end
    return player:IsRandomBot() or player:IsAddclassBot()
end

function paragon_addon.sendInformations(msg, player)
    local pAcc = player:GetAccountId()

    local temp = {
        stats = {},
        level = 1,
        points = 0,
    }

    for stat, _ in pairs(paragon.spells) do
        temp.stats[stat] = player:GetData('paragon_stats_'..stat) or 0
    end

    if not paragon.account[pAcc] then
        paragon.account[pAcc] = {
            level = 1,
            exp = 0,
            exp_max = paragon.config.expMax
        }
    end

    temp.level = paragon.account[pAcc].level
    temp.points = player:GetData('paragon_points')
    temp.exps = {
        exp = paragon.account[pAcc].exp,
        exp_max = paragon.account[pAcc].exp_max
    }
    temp.playerLevel = player:GetLevel()
    temp.minPlayerLevel = paragon.config.minPlayerLevel

    return msg:Add("AIO_Paragon", "setInfo", temp.stats, temp.level, temp.points, temp.exps, temp.playerLevel, temp.minPlayerLevel)
end
AIO.AddOnInit(paragon_addon.sendInformations)


function paragon.setAddonInfo(player)
    paragon_addon.sendInformations(AIO.Msg(), player):Send(player)
end


function paragon.onServerStart(event)
    CharDBExecute(string.format("CREATE DATABASE IF NOT EXISTS `%s`;", paragon.config.db_name))
    CharDBExecute(string.format("CREATE TABLE IF NOT EXISTS `%s`.`paragon_account` (`account_id` INT(11) NOT NULL, `level` INT(11) DEFAULT 1, `exp` INT(11) DEFAULT 0, PRIMARY KEY (`account_id`));", paragon.config.db_name))
    CharDBExecute(string.format("CREATE TABLE IF NOT EXISTS `%s`.`paragon_characters` (`account_id` INT(11) NOT NULL, `guid` INT(11) NOT NULL, `strength` INT(11) DEFAULT 0, `agility` INT(11) DEFAULT 0, `stamina` INT(11) DEFAULT 0, `intellect` INT(11) DEFAULT 0, `spirit` INT(11) DEFAULT 0, `defense` INT(11) DEFAULT 0, `points_spent` INT(11) DEFAULT 0, PRIMARY KEY (`account_id`, `guid`));", paragon.config.db_name))
end
RegisterServerEvent(14, paragon.onServerStart)


function paragon_addon.setStats(player)
    local pLevel = player:GetLevel()

    if pLevel >= paragon.config.minPlayerLevel then
        for spell, _ in pairs(paragon.spells) do
            player:RemoveAura(spell)
            player:AddAura(spell, player)
            player:GetAura(spell):SetStackAmount(player:GetData('paragon_stats_'..spell))
        end
    end
end


function paragon_addon.setStatsInformation(player, stat, value, flags)
    stat = tonumber(stat)
    if not stat or not paragon.spells[stat] then return end

    -- Clamp value between 1 and 10 since middle click can adjust it by 10
    value = tonumber(value) or 1
    value = math.max(1, math.min(value, 10))

    if player:IsInCombat() then
        player:SendNotification("You can't do this in combat.")
        return
    end

    local pLevel = player:GetLevel()
    if pLevel < paragon.config.minPlayerLevel then
        player:SendNotification("You don't have the level required to do that.")
        return
    end

    -- Cache all necessary values with fallback
    local keyStat = 'paragon_stats_' .. stat
    local currentStat = player:GetData(keyStat) or 0
    local currentPoints = player:GetData('paragon_points') or 0
    local currentSpent = player:GetData('paragon_points_spend') or 0

    if flags then
        -- Left or mousewheel up: allocate points
        if currentPoints >= value then
            player:SetData(keyStat, currentStat + value)
            player:SetData('paragon_points', currentPoints - value)
            player:SetData('paragon_points_spend', currentSpent + value)
        else
            player:SendNotification("You have no more points to spend.")
            return
        end
    else
        -- Right click or mousewheel down: refund points
        if currentStat >= value then
            player:SetData(keyStat, currentStat - value)
            player:SetData('paragon_points', currentPoints + value)
            player:SetData('paragon_points_spend', currentSpent - value)
        else
            player:SendNotification("You have no points to refund.")
            return
        end
    end

    -- Sync updated state to client
    paragon_addon.setStats(player)
    paragon.setAddonInfo(player)
end


function Player:setparagonInfo(strength, agility, stamina, intellect, spirit, defense)
    self:SetData('paragon_stats_7464', strength)
    self:SetData('paragon_stats_7471', agility)
    self:SetData('paragon_stats_7477', stamina)
    self:SetData('paragon_stats_7468', intellect)
    self:SetData('paragon_stats_7474', spirit)
    self:SetData('paragon_stats_7511', defense)
end


function paragon.onLogin(event, player)
    local pAcc = player:GetAccountId()

    -- Skip server-managed RandomBots and AddClass bots
    if ShouldSkipBot(player) then return end

    -- Initialize account-level Paragon data if not yet loaded
    if not paragon.account[pAcc] then
        paragon.account[pAcc] = {
            level = 1,
            exp = 0,
            exp_max = paragon.config.expMax
        }
    end

    -- Load account-level Paragon data only once per account.
    if not paragon.accountLoaded[pAcc] then
        local getparagonAccInfo = CharDBQuery(string.format("SELECT level, exp FROM `%s`.`paragon_account` WHERE account_id = %d", paragon.config.db_name, pAcc))
        if getparagonAccInfo then
            paragon.account[pAcc].level = getparagonAccInfo:GetUInt32(0)
            paragon.account[pAcc].exp = getparagonAccInfo:GetUInt32(1)
            paragon.updateExpMax(pAcc)
        else
            CharDBExecute(string.format("INSERT INTO `%s`.`paragon_account` VALUES (%d, 1, 0)", paragon.config.db_name, pAcc))
        end

        paragon.accountLoaded[pAcc] = true
    end

    -- Load character-specific stat allocations
    local getparagonCharInfo = CharDBQuery(string.format("SELECT strength, agility, stamina, intellect, spirit, defense, points_spent FROM `%s`.`paragon_characters` WHERE account_id = %d AND guid = %d", paragon.config.db_name, pAcc, player:GetGUIDLow()))
    
    local spent = 0
    if getparagonCharInfo then
        local strength  = getparagonCharInfo:GetUInt32(0)
        local agility   = getparagonCharInfo:GetUInt32(1)
        local stamina   = getparagonCharInfo:GetUInt32(2)
        local intellect = getparagonCharInfo:GetUInt32(3)
        local spirit    = getparagonCharInfo:GetUInt32(4)
        local defense   = getparagonCharInfo:GetUInt32(5)
        spent           = getparagonCharInfo:GetUInt32(6)

        player:setparagonInfo(strength, agility, stamina, intellect, spirit, defense)
    else
        -- First time this character logs in
        local pGuid = player:GetGUIDLow()
        CharDBExecute(string.format("INSERT INTO `%s`.`paragon_characters` VALUES (%d, %d, 0, 0, 0, 0, 0, 0, 0)", paragon.config.db_name, pAcc, pGuid))
        player:setparagonInfo(0, 0, 0, 0, 0, 0)
    end

    -- Set spent and unspent point data
    player:SetData('paragon_points_spend', spent)

    local level = paragon.account[pAcc].level
    local totalPointsEarned = (level > 1) and ((level - 1) * paragon.config.pointsPerLevel) or 0
    local availablePoints = totalPointsEarned - spent

    player:SetData('paragon_points', availablePoints)

    -- Apply active stat auras
    paragon_addon.setStats(player)
end
RegisterPlayerEvent(3, paragon.onLogin)


function paragon.getPlayers(event)
    for _, player in pairs(GetPlayersInWorld()) do
        if not ShouldSkipBot(player) then
            paragon.onLogin(event, player)
        end
    end
end
RegisterServerEvent(33, paragon.getPlayers)


function paragon.onLogout(event, player)
    local pAcc = player:GetAccountId()
    local pGuid = player:GetGUIDLow()

    -- Skip server-managed RandomBots and AddClass bots
    if ShouldSkipBot(player) then return end

    local strength, agility, stamina, intellect, spirit, defense, spent = player:GetData('paragon_stats_7464'), player:GetData('paragon_stats_7471'), player:GetData('paragon_stats_7477'), player:GetData('paragon_stats_7468'), player:GetData('paragon_stats_7474'), player:GetData('paragon_stats_7511'), player:GetData('paragon_points_spend')
    CharDBExecute(string.format("REPLACE INTO `%s`.`paragon_characters` VALUES (%d, %d, %d, %d, %d, %d, %d, %d, %d)", paragon.config.db_name, pAcc, pGuid, strength, agility, stamina, intellect, spirit, defense, spent))
    
    if not paragon.account[pAcc] then
        paragon.account[pAcc] = {
            level = 1,
            exp = 0,
            exp_max = paragon.config.expMax
          }
    end

    local level, exp = paragon.account[pAcc].level, paragon.account[pAcc].exp
    CharDBExecute(string.format("REPLACE INTO `%s`.`paragon_account` VALUES (%d, %d, %d)", paragon.config.db_name, pAcc, level, exp))
end
RegisterPlayerEvent(4, paragon.onLogout)


function paragon.setPlayers(event)
    for _, player in pairs(GetPlayersInWorld()) do
        if not ShouldSkipBot(player) then
            paragon.onLogout(event, player)
        end
    end
end
RegisterServerEvent(16, paragon.setPlayers)


function paragon.onLevelUp(event, player, oldLevel)
    -- Skip server-managed RandomBots and AddClass bots
    if ShouldSkipBot(player) then return end

    if player:GetLevel() == paragon.config.minPlayerLevel then
        player:SendBroadcastMessage(string.format("|CFF00A2FFCongratulations! You have reached level %d. The Paragon system has been unlocked and you can now start gaining Paragon levels.", paragon.config.minPlayerLevel))        
    end

    paragon.setAddonInfo(player)
end
RegisterPlayerEvent(13, paragon.onLevelUp)


function paragon.getRandomXP(type)
    local xpRanges = {
        elite = {5, 10},
        dungeonBoss = {90, 110},
        worldBoss = {250, 270},
        pvp = {8, 12}
    }
    return math.random(xpRanges[type][1], xpRanges[type][2])
end


function paragon.setExp(player, victim, numMembers)
    local pLevel = player:GetLevel()
    if pLevel < paragon.config.minPlayerLevel then return end
    local vLevel = victim:GetLevel()
    local pAcc = player:GetAccountId()

    local xpGain = 0

    local creature = victim:ToCreature()
    if creature then
        local isElite = creature:IsElite()
        local isDungeonBoss = creature:IsDungeonBoss()
        local isWorldBoss = creature:IsWorldBoss()

        if isWorldBoss then
            xpGain = paragon.getRandomXP("worldBoss")
        elseif isDungeonBoss then
            xpGain = paragon.getRandomXP("dungeonBoss")
        elseif isElite then
            xpGain = paragon.getRandomXP("elite")
        else
            return -- Ignore normal creatures
        end
    else
        xpGain = paragon.getRandomXP("pvp")
    end

    if xpGain <= 0 then return end  -- Exit early if no XP

    local levelDiff = pLevel - vLevel
    if levelDiff > 0 then -- Only reduce XP if the enemy is lower level
        if levelDiff > paragon.config.quarterXpRange then
            return -- Enemy too weak, no XP
        elseif levelDiff > paragon.config.halfXpRange then
            xpGain = math.floor(xpGain * paragon.config.quarterXpMultiplier)
        elseif levelDiff > paragon.config.fullXpRange then
            xpGain = math.floor(xpGain * paragon.config.halfXpMultiplier)
        end
    end

    -- Diminishing returns for group members
    local groupPenalty = 1 - (math.min((numMembers or 1) - 1, 4) * paragon.config.groupXpPenaltyStep)
    local adjustedXP = math.floor(xpGain * groupPenalty)

    if paragon.config.showXPGainedMessages then
        player:SendBroadcastMessage(string.format("|CFF00A2FFYou earned %d Paragon XP!|r", adjustedXP))
    end

    paragon.account[pAcc].exp = paragon.account[pAcc].exp + adjustedXP

    -- If the XP exceeds the max, be sure to carry over any excess XP to the next level
    -- Process level ups one at a time because the XP requirement changes each level.
    while paragon.account[pAcc].exp >= paragon.account[pAcc].exp_max do
        local carryOverXP = paragon.account[pAcc].exp - paragon.account[pAcc].exp_max
        player:SetparagonLevel(1, carryOverXP)
    end

    paragon.setAddonInfo(player)
end


function paragon.onKillCreatureOrPlayer(event, player, victim)
    local pGroup = player:GetGroup()
    if pGroup then
        local members = pGroup:GetMembers()
        local numMembers = #members

        for _, groupMember in pairs(members) do
            if not ShouldSkipBot(groupMember) then
                paragon.setExp(groupMember, victim, numMembers)
            end
        end
    else
        if not ShouldSkipBot(player) then
            paragon.setExp(player, victim, 1)
        end
    end
end
RegisterPlayerEvent(6, paragon.onKillCreatureOrPlayer)
RegisterPlayerEvent(7, paragon.onKillCreatureOrPlayer)


function Player:SetparagonLevel(levelsGained, carryOverXP)
    local pAcc = self:GetAccountId()
    if(pAcc ~= nil) then
        -- Increment the Paragon level
        paragon.account[pAcc].level = paragon.account[pAcc].level + levelsGained
        paragon.account[pAcc].exp = carryOverXP
        paragon.updateExpMax(pAcc)

        -- Update the available Paragon stat points
        local totalPoints = (paragon.account[pAcc].level > 1) and ((paragon.account[pAcc].level - 1) * paragon.config.pointsPerLevel) or 0
        local availablePoints = totalPoints - self:GetData('paragon_points_spend')
        self:SetData('paragon_points', availablePoints)

        -- Grant talent points based on config settings
        if paragon.config.grantTalentPoints and (paragon.account[pAcc].level % paragon.config.talentInterval == 0) then
            local newTalentPoints = paragon.config.talentsPerLevel * levelsGained
            self:SetFreeTalentPoints(self:GetFreeTalentPoints() + newTalentPoints)
            
            if paragon.config.showTalentNotifications then
                self:SendBroadcastMessage("|CFF00A2FFYou have earned a new talent point from Paragon!|r")
            end
        end
    end

    -- Visual/Notification effect
    self:CastSpell(self, 11540, true) -- blue firework
    self:CastSpell(self, 11541, true) -- green firework
    self:SendBroadcastMessage(string.format("|CFF00A2FFYou have just passed a level of Paragon.|r |CFF00FF00You are now level %d!|r", paragon.account[pAcc].level))    
end


function paragon.updateExpMax(pAcc)
    if paragon.account[pAcc] then
        local level = math.max(1, paragon.account[pAcc].level)
        paragon.account[pAcc].exp_max = math.floor(paragon.config.expMax * (level ^ paragon.config.expScalingExponent))
    end
end
