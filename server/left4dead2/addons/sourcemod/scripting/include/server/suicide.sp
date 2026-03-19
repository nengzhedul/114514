// server/suicide.sp
// 自杀功能 + 踢Bot

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

static int g_iSuicideMode;
static ConVar g_hSuicideMode;

void Suicide_OnPluginStart()
{
    g_hSuicideMode = CreateConVar("l4d2_survivor_suicide", "1", "启用生还者自杀功能: 0=禁用, 1=只限倒地/挂边, 2=无条件");
    g_hSuicideMode.AddChangeHook(OnSuicideModeChanged);
    OnSuicideModeChanged(g_hSuicideMode, "", "");

    RegConsoleCmd("sm_zs", Cmd_Suicide, "玩家自杀 (!zs)");
    RegConsoleCmd("sm_kill", Cmd_Suicide, "玩家自杀 (!kill)");
    RegConsoleCmd("sm_kb", Cmd_KickBots, "踢出所有电脑幸存者");
}

static void OnSuicideModeChanged(ConVar convar, const char[] oldVal, const char[] newVal)
{
    g_iSuicideMode = g_hSuicideMode.IntValue;
}

public Action Cmd_Suicide(int client, int args)
{
    RequestFrame(Frame_Suicide, GetClientUserId(client));
    return Plugin_Handled;
}

static void Frame_Suicide(int userId)
{
    int client = GetClientOfUserId(userId);
    if (client == 0 || !IsClientInGame(client) || IsFakeClient(client))
        return;

    int team = GetClientTeam(client);

    if (team == 1) // spectator
    {
        int bot = GetBotSpectatedBy(client);
        if (bot != 0 && g_iSuicideMode > 0)
            PerformSuicide(bot, client, "生还者");
        else
            PrintToChat(client, "\x04[提示]\x05旁观者无权使用该指令.");
    }
    else if (team == 2 || team == 4) // survivor or special infected? (原代码允许 team 4)
    {
        if (g_iSuicideMode > 0)
            PerformSuicide(client, client, "生还者");
        else
            PrintToChat(client, "\x04[提示]\x05生还者自杀指令未启用.");
    }
}

static void PerformSuicide(int target, int reporter, const char[] teamName)
{
    if (!IsPlayerAlive(target))
    {
        PrintToChat(reporter, "\x04[提示]\x05你当前已是死亡状态.");
        return;
    }

    char name[64];
    GetClientName(target, name, sizeof(name));

    if (g_iSuicideMode == 1 && IsPlayerStanding(target))
    {
        PrintToChat(reporter, "\x04[提示]\x05该指令只限倒地或挂边的%s使用.", teamName);
        return;
    }

    ForcePlayerSuicide(target);
    PrintToChatAll("\x04[提示]\x05(\x04%s\x05)\x03%s\x05突然失去了梦想.", teamName, name);
}

static bool IsPlayerStanding(int client)
{
    return !GetEntProp(client, Prop_Send, "m_isIncapacitated") &&
           !GetEntProp(client, Prop_Send, "m_isHangingFromLedge");
}

static int GetBotSpectatedBy(int spectator)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) == 2)
        {
            if (GetSpectatorOfBot(i) == spectator)
                return i;
        }
    }
    return 0;
}

static int GetSpectatorOfBot(int bot)
{
    if (!HasEntProp(bot, Prop_Send, "m_humanSpectatorUserID"))
        return 0;

    int userId = GetEntProp(bot, Prop_Send, "m_humanSpectatorUserID");
    return GetClientOfUserId(userId);
}

public Action Cmd_KickBots(int client, int args)
{
    if (!HasRootAccess(client))
    {
        PrintToChat(client, "\x04[提示]\x05你无权使用此指令.");
        return Plugin_Handled;
    }

    if (KickAllSurvivorBots())
        PrintToChat(client, "\x04[提示]\x05已踢出全部电脑生还者.");
    else
        PrintToChat(client, "\x04[提示]\x05没有多余的电脑生还者.");

    return Plugin_Handled;
}

static bool KickAllSurvivorBots()
{
    bool kicked = false;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) == 2 && GetSpectatorOfBot(i) == 0)
        {
            StripSurvivorWeapons(i);
            KickClient(i, "踢出全部电脑生还者.");
            kicked = true;
        }
    }
    return kicked;
}

static void StripSurvivorWeapons(int client)
{
    for (int slot = 0; slot <= 4; slot++)
    {
        int weapon = GetPlayerWeaponSlot(client, slot);
        if (weapon != -1)
        {
            RemovePlayerItem(client, weapon);
            RemoveEdict(weapon);
        }
    }
}

// 处理玩家聊天输入 "自杀"
bool Suicide_OnClientSayCommand(int client, const char[] command, const char[] args)
{
    if (strlen(args) <= 1 || strncmp(command, "say", 3, false) != 0)
        return false;

    if (StrEqual(args, "自杀", false))
    {
        RequestFrame(Frame_Suicide, GetClientUserId(client));
        return true;
    }
    return false;
}