# sourcemod-nt-loadout-rescue
Experimental plugin for Neotokyo that provides the following change:

If a player spawns without a primary weapon, let them choose their weapon loadout again.

## Background
In Neotokyo, players can spawn without a primary weapon under the following situations:

#### Player chose a weapon loadout with insufficient XP
* If a player deranks after the loadout menu was displayed, the menu won't update to reflect possible changes in allowed loadouts for that player.
  Choosing a weapon at too high a tier will then leave them without a primary weapon.
  This happens particularly in comp games, where the game gets restarted when it goes live
  but the player chose their initial loadout before that final restart went through.
#### Player chose an incompatible loadout
* If a player doesn't choose a weapon in time, the game will eventually forcibly spawn them,
  and pick the loadout they chose last in their stead.
  If this previous loadout is no longer available for them (deranked or the loadout isn't available
  for their current player class), this player will end up without a primary weapon.
  This can happen if players go AFK, and then return to find themselves having auto-spawned empty handed.

## What this plugin does
If a player spawns without a weapon, this plugin will re-display that weapon loadout menu for them,
so they can choose a valid loadout. The player will then receive this weapon post-spawn.

## Build requirements
* SourceMod 1.8 or newer
  * **If you are using SourceMod older than 1.11**: you also need the [DHooks extension](https://forums.alliedmods.net/showpost.php?p=2588686) for your version of SourceMod. SM 1.11 and newer **do not require this extension**.
* The [neotokyo.inc include](https://github.com/softashell/sourcemod-nt-include/blob/master/scripting/include/neotokyo.inc), version 1.1 or newer

## Installation
* Move the compiled .smx binary to `addons/sourcemod/plugins`
* Move the gamedata file to `addons/sourcemod/gamedata/neotokyo` (create the *"neotokyo"* folder in gamedata if it doesn't exist yet)

## Configuration

#### Cvars

* *sm_loadout_rescue_allow_loadout_change*
  * Whether to allow already spawned players to swap their loadout at any time. Useful for DM style modes.
  * default: `0`, min: `0`, max: `1`
