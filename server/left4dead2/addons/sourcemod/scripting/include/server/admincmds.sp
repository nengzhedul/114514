// server/admincmds.sp
// 管理员通用命令

#include <sourcemod>
#include <sdktools>

void AdminCmds_OnPluginStart()
{
    RegAdminCmd("sm_ars", Cmd_ChangeCvar, ADMFLAG_GENERIC, "修改Cvar: sm_ars <cvar> <value>");
    RegAdminCmd("sm_restartmap", Cmd_RestartMap, ADMFLAG_ROOT, "重启当前地图 (3秒后)");
}

public Action Cmd_ChangeCvar(int client, int args)
{
    if (args < 2)
    {
        ReplyToCommand(client, "用法: sm_ars <ConVar名> <值>");
        return Plugin_Handled;
    }

    char cvarName[64], value[32];
    GetCmdArg(1, cvarName, sizeof(cvarName));
    GetCmdArg(2, value, sizeof(value));

    ConVar cvar = FindConVar(cvarName);
    if (cvar == null)
    {
        ReplyToCommand(client, "找不到 ConVar: %s", cvarName);
        return Plugin_Handled;
    }

    cvar.SetString(value);
    ReplyToCommand(client, "已将 %s 设置为 %s", cvarName, value);
    return Plugin_Handled;
}

public Action Cmd_RestartMap(int client, int args)
{
    PrintHintTextToAll("地图将在3秒后重启");
    CreateTimer(3.0, Timer_RestartMap);
    return Plugin_Handled;
}

static Action Timer_RestartMap(Handle timer)
{
    char map[64];
    GetCurrentMap(map, sizeof(map));
    ServerCommand("changelevel %s", map);
    return Plugin_Handled;
}