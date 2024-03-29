-- ------------------------------------------------------------------------------------------------
-- -- PARAGON SERVER CONFIGURATION
-- ------------------------------------------------------------------------------------------------

local AIO = AIO or require("aio")

local paragon = {

    config = {
        db_name = 'ac_eluna',

        pointsPerLevel = 1,
        minLevel = 1,

        expMulti = 1,
        expMax = 500,

        pveKill = 100,
        pvpKill = 10,

        levelDiff = 10,
    },

    spells = {
        [7464] = 'Strength',
        [7471] = 'Agility',
        [7477] = 'Stamina',
        [7468] = 'Intellect',
        [7474] = 'Spirit',
    },
}

local paragon_addon = AIO.AddHandlers("AIO_Paragon", {})

paragon.account = {}

function paragon_addon.sendInformations(msg, player)
    local pGuid = player:GetGUIDLow()
    local pAcc = player:GetAccountId()

    local temp = {
        stats = {},
        level = 1,
        points = 1,
    }
    for stat, _ in pairs(paragon.spells) do
        temp.stats[stat] = player:GetData('paragon_stats_'..stat)
    end

    if not paragon.account[pAcc] then
        paragon.account[pAcc] = {
            level = 1,
            exp = 0,
            exp_max = 0,
        }
    end

    temp.level = paragon.account[player:GetAccountId()].level
    temp.points = player:GetData('paragon_points')
    temp.exps = {
        exp = paragon.account[player:GetAccountId()].exp,
        exp_max = paragon.account[player:GetAccountId()].exp_max
    }

    return msg:Add("AIO_Paragon", "setInfo", temp.stats, temp.level, temp.points, temp.exps)
end
AIO.AddOnInit(paragon_addon.sendInformations)

function paragon.setAddonInfo(player)
    paragon_addon.sendInformations(AIO.Msg(), player):Send(player)
end

function paragon.onServerStart(event)
    CharDBExecute('CREATE DATABASE IF NOT EXISTS `'..paragon.config.db_name..'`;')
    CharDBExecute('CREATE TABLE IF NOT EXISTS `'..paragon.config.db_name..'`.`paragon_account` (`account_id` INT(11) NOT NULL, `level` INT(11) DEFAULT 1, `exp` INT(11) DEFAULT 0, PRIMARY KEY (`account_id`) );');
    CharDBExecute('CREATE TABLE IF NOT EXISTS `'..paragon.config.db_name..'`.`paragon_characters` (`account_id` INT(11) NOT NULL, `guid` INT(11) NOT NULL, `strength` INT(11) DEFAULT 0, `agility` INT(11) DEFAULT 0, `stamina` INT(11) DEFAULT 0, `intellect` INT(11) DEFAULT 0, `spirit` INT(11) DEFAULT 0, PRIMARY KEY (`account_id`, `guid`));');
    io.write('Eluna :: paragon System start \n')
end
RegisterServerEvent(14, paragon.onServerStart)

function paragon_addon.setStats(player)
    local pLevel = player:GetLevel()

    if pLevel >= paragon.config.minLevel then
        for spell, _ in pairs(paragon.spells) do
            player:RemoveAura(spell)
            player:AddAura(spell, player)
            player:GetAura(spell):SetStackAmount(player:GetData('paragon_stats_'..spell))
        end
    end
end

-- flags
-- true == add_points
-- false == remove_points
function paragon_addon.setStatsInformation(player, stat, value, flags)
  local pCombat = player:IsInCombat()
  if (not pCombat) then
    local pLevel = player:GetLevel()
    if (pLevel >= paragon.config.minLevel) then
      if flags then
        -- Left click to add points
        if ((player:GetData('paragon_points') - value) >= 0) then
          player:SetData('paragon_stats_'..stat, (player:GetData('paragon_stats_'..stat) + value))
          player:SetData('paragon_points', (player:GetData('paragon_points') - value))

          player:SetData('paragon_points_spend', (player:GetData('paragon_points_spend') + value))
        else
          player:SendNotification('You have no more points to spend.')
          return false
        end
      else
        -- Right click to refund points
        if (player:GetData('paragon_stats_'..stat) > 0) then
          player:SetData('paragon_stats_'..stat, (player:GetData('paragon_stats_'..stat) - value))
          player:SetData('paragon_points', (player:GetData('paragon_points') + value))

          player:SetData('paragon_points_spend', (player:GetData('paragon_points_spend') - value))
        else
          player:SendNotification('You have no points to refund.')
          return false
        end
      end
      paragon.setAddonInfo(player)
    else
      player:SendNotification('You don\'t have the level required to do that.')
    end
  else
    player:SendNotification('You can\'t do this in combat.')
  end
end

function Player:setparagonInfo(strength, agility, stamina, intellect, spirit)
  self:SetData('paragon_stats_7464', strength)
  self:SetData('paragon_stats_7471', agility)
  self:SetData('paragon_stats_7477', stamina)
  self:SetData('paragon_stats_7468', intellect)
  self:SetData('paragon_stats_7474', spirit)
end

function paragon.onLogin(event, player)
    local pAcc = player:GetAccountId()
    local getparagonCharInfo = CharDBQuery('SELECT strength, agility, stamina, intellect, spirit FROM `'..paragon.config.db_name..'`.`paragon_characters` WHERE account_id = '..pAcc)
    if getparagonCharInfo then
      player:setparagonInfo(getparagonCharInfo:GetUInt32(0), getparagonCharInfo:GetUInt32(1), getparagonCharInfo:GetUInt32(2), getparagonCharInfo:GetUInt32(3), getparagonCharInfo:GetUInt32(4))
      player:SetData('paragon_points', getparagonCharInfo:GetUInt32(0) + getparagonCharInfo:GetUInt32(1) + getparagonCharInfo:GetUInt32(2) + getparagonCharInfo:GetUInt32(3) + getparagonCharInfo:GetUInt32(4))
    else
      local pGuid = player:GetGUIDLow()
      CharDBExecute('INSERT INTO `'..paragon.config.db_name..'`.`paragon_characters` VALUES ('..pAcc..', '..pGuid..', 0, 0, 0, 0, 0)')
      player:setparagonInfo(0, 0, 0, 0, 0)
    end
    player:SetData('paragon_points_spend', 0)

    if not paragon.account[pAcc] then
      paragon.account[pAcc] = {
        level = 1,
        exp = 0,
        exp_max = 0,
      }
    end

    local getparagonAccInfo = AuthDBQuery('SELECT level, exp FROM `'..paragon.config.db_name..'`.`paragon_account` WHERE account_id = '..pAcc)
    if getparagonAccInfo then
      paragon.account[pAcc].level = getparagonAccInfo:GetUInt32(0)
      paragon.account[pAcc].exp = getparagonAccInfo:GetUInt32(1)
      paragon.account[pAcc].exp_max = paragon.config.expMax * paragon.account[pAcc].level
    else
      AuthDBExecute('INSERT INTO `'..paragon.config.db_name..'`.`paragon_account` VALUES ('..pAcc..', 1, 0)')
    end

    paragon_addon.setStats(player)
    player:SetData('paragon_points', (paragon.account[pAcc].level * paragon.config.pointsPerLevel) - player:GetData('paragon_points'))
end
RegisterPlayerEvent(3, paragon.onLogin)

function paragon.getPlayers(event)
  for _, player in pairs(GetPlayersInWorld()) do
    paragon.onLogin(event, player)
  end
  io.write('Eluna :: paragon System start \n')
end
RegisterServerEvent(33, paragon.getPlayers)

function paragon.onLogout(event, player)
  local pAcc = player:GetAccountId()
  local pGuid = player:GetGUIDLow()
  local strength, agility, stamina, intellect, spirit = player:GetData('paragon_stats_7464'), player:GetData('paragon_stats_7471'), player:GetData('paragon_stats_7477'), player:GetData('paragon_stats_7468'), player:GetData('paragon_stats_7474')
  CharDBExecute('REPLACE INTO `'..paragon.config.db_name..'`.`paragon_characters` VALUES ('..pAcc..', '..pGuid..', '..strength..', '..agility..', '..stamina..', '..intellect..', '..spirit..')')

  if not paragon.account[pAcc] then
    paragon.account[pAcc] = {
      level = 1,
      exp = 0,
      exp_max = 0,
    }
  end

  local level, exp = paragon.account[pAcc].level, paragon.account[pAcc].exp
  AuthDBExecute('REPLACE INTO `'..paragon.config.db_name..'`.`paragon_account` VALUES ('..pAcc..', '..level..', '..exp..')')
end
RegisterPlayerEvent(4, paragon.onLogout)

function paragon.setPlayers(event)
  for _, player in pairs(GetPlayersInWorld()) do
    paragon.onLogout(event, player)
  end
end
RegisterServerEvent(16, paragon.setPlayers)

function paragon.setExp(player, victim)
    local pLevel = player:GetLevel()
    local vLevel = victim:GetLevel()
    local pAcc = player:GetAccountId()

    if (vLevel - pLevel <= paragon.config.levelDiff) and (vLevel - pLevel >= 0) or (pLevel - vLevel <= paragon.config.levelDiff) and (pLevel - vLevel >= 0) then
        local isPlayer = GetGUIDEntry(victim:GetGUID())
        if (isPlayer == 0) then
            paragon.account[pAcc].exp = paragon.account[pAcc].exp + paragon.config.pvpKill
            player:SendBroadcastMessage('Your victim gives you '..paragon.config.pvpKill..' paragon experience points.')
        else
            paragon.account[pAcc].exp = paragon.account[pAcc].exp + paragon.config.pveKill
            player:SendBroadcastMessage('Your victim gives you '..paragon.config.pveKill..' paragon experience points.')
        end
        paragon.setAddonInfo(player)
    end

    if paragon.account[pAcc].exp >= paragon.account[pAcc].exp_max then
        player:SetparagonLevel(1)
    end
end

function paragon.onKillCreatureOrPlayer(event, player, victim)
    local pLevel = player:GetLevel()

    if (pLevel >= paragon.config.minLevel) then
        local pGroup = player:GetGroup()
        local vLevel = victim:GetLevel()
        if pGroup then
            for _, player in pairs(pGroup:GetMembers()) do
                paragon.setExp(player, victim)
            end
        else
            paragon.setExp(player, victim)
        end
    end
end
RegisterPlayerEvent(6, paragon.onKillCreatureOrPlayer)
RegisterPlayerEvent(7, paragon.onKillCreatureOrPlayer)

function Player:SetparagonLevel(level)
    local pAcc = self:GetAccountId()

    paragon.account[pAcc].level = paragon.account[pAcc].level + level
    paragon.account[pAcc].exp = 0
    paragon.account[pAcc].exp_max = paragon.config.expMax * paragon.account[pAcc].level
    self:SetData('paragon_points', (((paragon.account[pAcc].level * paragon.config.pointsPerLevel) - self:GetData('paragon_points')) + self:GetData('paragon_points') - self:GetData('paragon_points_spend')))
    paragon.setAddonInfo(self)

    self:CastSpell(self, 24312, true)
    self:RemoveAura( 24312 )
    self:SendNotification('|CFF00A2FFYou have just passed a level of Paragon.\nCongratulations, you are now level '..paragon.account[pAcc].level..'!')
end