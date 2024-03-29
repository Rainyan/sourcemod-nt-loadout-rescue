#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>

#include <neotokyo>

#define PLUGIN_VERSION "0.4.2"

// Note: these indices must be in the same order as the neotokyo.inc weapons_primary array!
enum {
    WEP_INVALID = -1,
    WEP_GHOST,
    WEP_MPN,
    WEP_SRM,
    WEP_SRM_S,
    WEP_JITTE,
    WEP_JITTESCOPED,
    WEP_ZR68C,
    WEP_ZR68L,
    WEP_ZR68S,
    WEP_SUPA7,
    WEP_M41,
    WEP_M41S,
    WEP_MX,
    WEP_MX_S,
    WEP_AA13,
    WEP_SRS,
    WEP_PZ
};

static bool _loadout_successful[NEO_MAXPLAYERS + 1];

ConVar _allow_loadout_change = null;

// Workaround for cases where the drop would not propagate to nt_ghostcap,
// for SM range < 1.11 because it wasn't available, and for range 1.11-1.12.6961
// because it was bugged.
#define NEED_DROP_FIX (SOURCEMOD_V_MAJOR == 1 && (SOURCEMOD_V_MINOR < 11 || (SOURCEMOD_V_MINOR == 12 && SOURCEMOD_V_REV < 6961)))

#if NEED_DROP_FIX
static Handle g_hForwardDrop;
#endif

public Plugin myinfo = {
    name = "NT Loadout Rescue",
    description = "If a player spawns without a primary weapon, let them choose it again.",
    author = "Rain",
    version = PLUGIN_VERSION,
    url = "https://github.com/Rainyan/sourcemod-nt-loadout-rescue"
};

public void OnPluginStart()
{
    FeatureStatus fs = GetFeatureStatus(FeatureType_Capability, FEATURECAP_COMMANDLISTENER);
    if (fs != FeatureStatus_Available)
    {
        SetFailState("No feature CommandListener available");
    }
    else if (!AddCommandListener(Cmd_OnLoadout, "loadout"))
    {
        SetFailState("Failed to add command listener");
    }

    Handle gd = LoadGameConfigFile("neotokyo/loadout_rescue");
    if (!gd)
    {
        SetFailState("Failed to load GameData");
    }
    DynamicDetour dd = DynamicDetour.FromConf(gd, "Fn_CBasePlayer__GiveNamedItem");
    if (!dd)
    {
        SetFailState("Failed to create dynamic detour");
    }
    if (!dd.Enable(Hook_Post, GiveNamedItem))
    {
        SetFailState("Failed to detour");
    }
    CloseHandle(gd);

    _allow_loadout_change = CreateConVar("sm_loadout_rescue_allow_loadout_change",
        "0", "Whether to allow already spawned players to swap their loadout at any time. \
Useful for DM style modes.", _, true, 0.0, true, 1.0);

    if (!HookEventEx("game_round_start", OnRoundStart))
    {
        SetFailState("Failed to hook event");
    }

    AutoExecConfig();
}

#if NEED_DROP_FIX
public void OnAllPluginsLoaded()
{
    g_hForwardDrop = CreateGlobalForward("OnGhostDrop", ET_Event, Param_Cell);
}
#endif

public void OnMapEnd()
{
    for (int client = 1; client <= MaxClients; ++client)
    {
        _loadout_successful[client] = false;
    }
}

public void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int client = 1; client <= MaxClients; ++client)
    {
        _loadout_successful[client] = false;
    }
}

// For a primary weapon edict, and its corresponding neotokyo.inc primary weapon index,
// fills that weapon with the correct amount of ammmo.
// Returns a boolean of whether the operation was successful.
bool FillPrimaryWepAmmo(int wep_edict, int primary_wep_index)
{
    if (!IsValidEdict(wep_edict))
    {
        return false;
    }

    int owner = GetEntPropEnt(wep_edict, Prop_Data, "m_hOwnerEntity");
    if (owner <= 0 || owner > MaxClients || !IsClientInGame(owner))
    {
        return false;
    }

    int ammo_count_and_type[sizeof(weapons_primary)][2] = {
        { 0, -1 }, // Ghost
        { 120, AMMO_PRIMARY }, // MPN
        { 150, AMMO_PRIMARY }, // SRM
        { 150, AMMO_PRIMARY }, // SRM-S
        { 120, AMMO_PRIMARY }, // Jitte
        { 120, AMMO_PRIMARY }, // Jittescoped
        { 120, AMMO_PRIMARY }, // ZR68C
        { 30, AMMO_PRIMARY }, // ZR68L
        { 120, AMMO_PRIMARY }, // ZR68S
        { 28, AMMO_SHOTGUN }, // Supa7
        { 60, AMMO_PRIMARY }, // M41
        { 60, AMMO_PRIMARY }, // M41-S
        { 120, AMMO_PRIMARY }, // MX
        { 120, AMMO_PRIMARY }, // MX-S
        { 64, AMMO_SHOTGUN }, // AA13
        { 18, AMMO_PRIMARY }, // SRS
        { 200, AMMO_PZ }, // PZ
    };

    if (primary_wep_index < 0 || primary_wep_index >= sizeof(ammo_count_and_type))
    {
        return false;
    }

    SetWeaponAmmo(
        owner,
        ammo_count_and_type[primary_wep_index][1],
        ammo_count_and_type[primary_wep_index][0]
    );
    return true;
}

// Hook of the native weapons loadout VGUIMenu result
public Action Cmd_OnLoadout(int client, const char[] command, int argc)
{
    if (!_allow_loadout_change.BoolValue)
    {
        // If the player hasn't spawned in yet, this is their first loadout flow.
        // Do nothing because we're only interested in the second, backup loadout rescue.
        if (!IsPlayerAlive(client))
        {
            return Plugin_Continue;
        }

        // We've already given this player their weapon loadout this round.
        if (_loadout_successful[client])
        {
            return Plugin_Continue;
        }
    }

    // This can happen if a client attempts to get their loadout directly
    // via client console, using incorrect parameters.
    if (argc != 1)
    {
        return Plugin_Continue;
    }

    int loadout;
    if (!GetCmdArgIntEx(1, loadout))
    {
        return Plugin_Continue;
    }

    // Never attempt to arm a spectating client
    int team = GetClientTeam(client);
    if (team != TEAM_JINRAI && team != TEAM_NSF)
    {
        return Plugin_Continue;
    }

    // This player somehow chose a loadout before choosing their player class?
    // As we cannot determine which guns they are entitled to spawn with
    // without the class, bail out.
    int player_class = GetPlayerClass(client);
    if (player_class != CLASS_RECON &&
        player_class != CLASS_ASSAULT &&
        player_class != CLASS_SUPPORT)
    {
        return Plugin_Continue;
    }

    int primary_index = WEP_INVALID;
    int unlock_rank = RANK_INVALID;
    GetPrimaryOfLoadout(loadout, player_class, primary_index, unlock_rank);
    if (GetPlayerRank(client) < unlock_rank)
    {
        return Plugin_Continue;
    }

    if (_allow_loadout_change.BoolValue)
    {
        for(int slot = 0; slot <= 5; ++slot)
        {
            int wep = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", slot);
            if (IsValidEdict(wep) && GetWeaponSlot(wep) == SLOT_PRIMARY)
            {
                if (IsWeaponGhost(wep))
                {
#if NEED_DROP_FIX
                    SDKHooks_DropWeapon(client, wep, NULL_VECTOR, NULL_VECTOR);
                    Call_StartForward(g_hForwardDrop);
                    Call_PushCell(client);
                    Call_Finish();
#else
                    SDKHooks_DropWeapon(client, wep, NULL_VECTOR, NULL_VECTOR, false);
#endif
                }
                else
                {
                    RemovePlayerItem(client, wep);
                    RemoveEdict(wep);
                }
                break;
            }
        }
    }

    int wep = GivePlayerItem(client, weapons_primary[primary_index]);
    if (wep == -1)
    {
        ThrowError("GivePlayerItem %N (%d, %d, %d -> \"%s\" failed",
            client, player_class, loadout, primary_index, weapons_primary[primary_index]);
    }

    if (!FillPrimaryWepAmmo(wep, primary_index))
    {
        ThrowError("Failed to fill rescued primary weapon with ammo");
    }

    // Defer equipping to the slot command, because things get funkalicious
    // if we try and set the active weapon dataprop in this callback directly.
    // Not sure why it fails, but probably either because we're too early,
    // or because we're essentially inside a weapon spawn logic already in this
    // code path. Regardless, this seems to work well enough.
    // TODO: is  this still the case with FEATURECAP_COMMANDLISTENER?
    ClientCommand(client, "slot1");

    _loadout_successful[client] = true;
    return Plugin_Continue;
}

// Assumes weapon input to always be a valid NT wep index.
bool IsWeaponGhost(int weapon)
{
    // "weapon_gh" + '\0' == strlen 10.
    // We assume any non -1 ent index we get is always
    // a valid NT weapon ent index.
    char wepName[9 + 1];
    if (!GetEntityClassname(weapon, wepName, sizeof(wepName)))
    {
        return false;
    }

    // weapon_gHost -- only weapon with letter H on 8th position of its name.
    return wepName[8] == 'h';
}

// For a given valid loadout index and valid player class,
// passes by reference the corresponding primary weapon index of neotokyo.inc,
// and the rank at which that primary weapon unlocks for the player class.
void GetPrimaryOfLoadout(int loadout, int player_class,
    int& out_primary_index, int& out_unlock_rank)
{
    // Class-specific mappings of (player class, loadout index) -> (weapon index, rank).
    int loadouts[3][12][2] = {
        // Recon
        {
            { WEP_MPN,          RANK_RANKLESSDOG },
            { WEP_SRM,          RANK_PRIVATE },
            { WEP_JITTE,        RANK_PRIVATE },
            { WEP_SRM_S,        RANK_CORPORAL },
            { WEP_JITTESCOPED,  RANK_CORPORAL },
            { WEP_ZR68L,        RANK_CORPORAL },
            { WEP_ZR68C,        RANK_SERGEANT },
            { WEP_SUPA7,        RANK_LIEUTENANT },
            { WEP_M41S,         RANK_LIEUTENANT },
            { WEP_INVALID,      RANK_INVALID },
            { WEP_INVALID,      RANK_INVALID },
            { WEP_INVALID,      RANK_INVALID },
        },
        // Assault
        {
            { WEP_MPN,          RANK_RANKLESSDOG },
            { WEP_SRM,          RANK_PRIVATE },
            { WEP_JITTE,        RANK_PRIVATE },
            { WEP_ZR68C,        RANK_PRIVATE },
            { WEP_ZR68S,        RANK_PRIVATE },
            { WEP_SUPA7,        RANK_CORPORAL },
            { WEP_M41,          RANK_CORPORAL },
            { WEP_M41S,         RANK_CORPORAL },
            { WEP_MX,           RANK_SERGEANT },
            { WEP_MX_S,         RANK_SERGEANT },
            { WEP_AA13,         RANK_LIEUTENANT },
            { WEP_SRS,          RANK_LIEUTENANT },
        },
        // Support
        {
            { WEP_MPN,          RANK_RANKLESSDOG },
            { WEP_SRM,          RANK_PRIVATE },
            { WEP_ZR68C,        RANK_PRIVATE },
            { WEP_M41,          RANK_PRIVATE },
            { WEP_SUPA7,        RANK_PRIVATE },
            { WEP_MX,           RANK_CORPORAL },
            { WEP_M41S,         RANK_CORPORAL },
            { WEP_MX_S,         RANK_SERGEANT },
            { WEP_PZ,           RANK_LIEUTENANT },
            { WEP_INVALID,      RANK_INVALID },
            { WEP_INVALID,      RANK_INVALID },
            { WEP_INVALID,      RANK_INVALID },
        },
    };

    if (player_class < CLASS_RECON || player_class > CLASS_SUPPORT)
    {
        ThrowError("Unexpected player class index: %d", player_class);
    }
    if (loadout < 0 || loadout >= sizeof(loadouts[]))
    {
        ThrowError("Loadout index out of range: %d", loadout);
    }

    out_primary_index = loadouts[player_class - 1][loadout][0];
    out_unlock_rank = loadouts[player_class - 1][loadout][1];
}

// Detour of CBasePlayer::GiveNamedItem
public MRESReturn GiveNamedItem(int client, DHookReturn hReturn, DHookParam hParams)
{
    if (_loadout_successful[client])
    {
        return MRES_Ignored;
    }

    if (hReturn.Value != INVALID_ENT_REFERENCE)
    {
        char classname[18 + 1];
        hParams.GetString(1, classname, sizeof(classname));
        for (int i = 0; i < sizeof(weapons_primary); ++i)
        {
            if (StrEqual(classname, weapons_primary[i]))
            {
                _loadout_successful[client] = true;
                break;
            }
        }
        return MRES_Ignored;
    }

    ClientCommand(client, "loadoutmenu");
    return MRES_Ignored;
}

// Backported from SourceMod/SourcePawn SDK for SM < 1.11 compatibility.
// Used here under GPLv3 license: https://www.sourcemod.net/license.php
// SourceMod (C)2004-2023 AlliedModders LLC.  All rights reserved.
#if SOURCEMOD_V_MAJOR <= 1 && SOURCEMOD_V_MINOR < 11
/**
 * Retrieves a numeric command argument given its index, from the current
 * console or server command. Returns false if the argument can not be
 * completely parsed as an integer.
 *
 * @param argnum        Argument number to retrieve.
 * @param value         Populated with the value of the command argument.
 * @return              Whether the argument was entirely a numeric value.
 */
stock bool GetCmdArgIntEx(int argnum, int &value)
{
    char str[12];
    int len = GetCmdArg(argnum, str, sizeof(str));

    return StringToIntEx(str, value) == len && len > 0;
}
#endif
