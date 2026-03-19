// server/customhud.sp
// 自定义HUD

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <l4d2_ems_hud>
#include <cjson>

#define MAX_SIZE_HUD 32

static Handle g_hTimerServerHUD = null;
static float g_fMapMaxFlow;
static int g_iTimeCount = -1;
static int g_iPlayerCount = 0;
static int g_iCurrentChapter = 1;
static int g_iMaxChapters = 5;
static int g_iSurvivorFlow = 0;
static int g_iInfectedCount = 0;
static ArrayList g_aCustomHUDConVars = null;

static char g_sHUDText[MAX_SIZE_HUD][256];
static int g_iHUDFlags[MAX_SIZE_HUD];
static float g_fHUDPosX[MAX_SIZE_HUD];
static float g_fHUDPosY[MAX_SIZE_HUD];
static float g_fHUDWidth[MAX_SIZE_HUD];
static float g_fHUDHeight[MAX_SIZE_HUD];
static bool g_bHUDUsed[MAX_SIZE_HUD];

static ConVar g_hHUDEnable;

void CustomHUD_OnPluginStart()
{
    g_hHUDEnable = CreateConVar("l4d2_custom_hud_enable", "1", "启用/禁用自定义HUD显示", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hHUDEnable.AddChangeHook(OnHUDEnableChanged);

    RegAdminCmd("sm_custom_hud_reload", Cmd_ReloadCustomHUDJson, ADMFLAG_ROOT, "重新加载自定义HUD配置文件");

    // 延迟加载HUD配置
    CreateTimer(3.0, Timer_DelayCreateHUDTimer, _, TIMER_FLAG_NO_MAPCHANGE);
}

void CustomHUD_OnMapStart()
{
    g_iTimeCount = 0;
    g_iPlayerCount = 0;
    g_fMapMaxFlow = L4D2Direct_GetMapMaxFlowDistance();

    g_iCurrentChapter = L4D_GetCurrentChapter();
    g_iMaxChapters = L4D_GetMaxChapters();

    if (g_hTimerServerHUD == null)
        g_hTimerServerHUD = CreateTimer(1.0, Timer_DisplayServerHUD, _, TIMER_REPEAT);
}

void CustomHUD_OnClientConnected(int client)
{
    if (!IsFakeClient(client))
        g_iPlayerCount++;
}

void CustomHUD_OnClientDisconnect(int client)
{
    if (!IsFakeClient(client))
        g_iPlayerCount--;
}

static void OnHUDEnableChanged(ConVar convar, const char[] oldVal, const char[] newVal)
{
    if (!g_hHUDEnable.BoolValue)
        RemoveAllCustomHUD();
}

static void LoadCustomHUDJson()
{
    char jsonPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, jsonPath, sizeof(jsonPath), "json/server_hud.json");

    if (!FileExists(jsonPath))
    {
        SetFailState("Failed to find sourcemod/json/server_hud.json");
        return;
    }

    SafeCloseHandle(g_aCustomHUDConVars);
    g_aCustomHUDConVars = new ArrayList(ByteCountToCells(64));

    JSONObject customHUDJson = JSONObject.FromFile(jsonPath);
    if (customHUDJson == null)
    {
        LogError("Failed to parse server_hud.json");
        return;
    }

    if (customHUDJson.HasKey("convar"))
    {
        JSONArray convarsArray = view_as<JSONArray>(customHUDJson.Get("convar"));
        for (int i = 0; i < convarsArray.Length; i++)
        {
            char convarName[64];
            convarsArray.GetString(i, convarName, sizeof(convarName));

            ConVar cvar = FindConVar(convarName);
            if (cvar != null)
                g_aCustomHUDConVars.Push(cvar);
            else
                LogError("ConVar not found: %s", convarName);
        }
    }

    char key[8];
    for (int i = 0; i < MAX_SIZE_HUD; i++)
    {
        IntToString(i, key, sizeof(key));
        if (customHUDJson.HasKey(key))
        {
            JSONObject HUDElement = view_as<JSONObject>(customHUDJson.Get(key));
            if (HUDElement == null)
            {
                g_bHUDUsed[i] = false;
                continue;
            }

            HUDElement.GetString("hudText", g_sHUDText[i], 256);
            g_fHUDPosX[i] = HUDElement.GetFloat("posX");
            g_fHUDPosY[i] = HUDElement.GetFloat("posY");
            g_fHUDWidth[i] = HUDElement.GetFloat("width");
            g_fHUDHeight[i] = HUDElement.GetFloat("height");

            JSONArray flagsArray = view_as<JSONArray>(HUDElement.Get("hudflags"));
            g_iHUDFlags[i] = 0;
            for (int j = 0; j < flagsArray.Length; j++)
                g_iHUDFlags[i] |= flagsArray.GetInt(j);

            if (!(g_iHUDFlags[i] & HUD_FLAG_TEXT))
                g_iHUDFlags[i] |= HUD_FLAG_TEXT;

            g_bHUDUsed[i] = true;
            delete HUDElement;
        }
        else
        {
            g_bHUDUsed[i] = false;
        }
    }

    delete customHUDJson;
}

static Action Timer_DelayCreateHUDTimer(Handle timer)
{
    LoadCustomHUDJson();
    if (g_hTimerServerHUD == null)
        g_hTimerServerHUD = CreateTimer(1.0, Timer_DisplayServerHUD, _, TIMER_REPEAT);
    return Plugin_Stop;
}

static Action Timer_DisplayServerHUD(Handle timer)
{
    if (g_hHUDEnable != null && !g_hHUDEnable.BoolValue)
    {
        RemoveAllCustomHUD();
        return Plugin_Continue;
    }

    if (g_iTimeCount == 0)
    {
        g_iCurrentChapter = L4D_GetCurrentChapter();
        g_iMaxChapters = L4D_GetMaxChapters();
    }

    g_iTimeCount++;
    g_iSurvivorFlow = GetHighestSurvivorFlow();
    g_iInfectedCount = GetCurrentInfectedCount();

    RemoveAllCustomHUD();
    ShowAllCustomHUD();

    return Plugin_Continue;
}

static void ShowAllCustomHUD()
{
    for (int i = 0; i < MAX_SIZE_HUD; i++)
    {
        if (g_bHUDUsed[i])
            ShowCustomHUD(i);
    }
}

static void RemoveAllCustomHUD()
{
    for (int i = 0; i < MAX_SIZE_HUD; i++)
    {
        if (HUDSlotIsUsed(i))
            RemoveHUD(i);
    }
}

static void ShowCustomHUD(int hudID)
{
    char formattedText[256];
    strcopy(formattedText, sizeof(formattedText), g_sHUDText[hudID]);

    ReplaceVariables(formattedText);

    HUDSetLayout(hudID, g_iHUDFlags[hudID], formattedText);
    HUDPlace(hudID, g_fHUDPosX[hudID], g_fHUDPosY[hudID], g_fHUDWidth[hudID], g_fHUDHeight[hudID]);
}

static void ReplaceVariables(char text[256])
{
    char buffer[128], search[64], replace[128];

    for (int i = 0; i < g_aCustomHUDConVars.Length; i++)
    {
        ConVar cvar = view_as<ConVar>(g_aCustomHUDConVars.Get(i));
        if (cvar != null)
        {
            cvar.GetName(search, sizeof(search));
            Format(search, sizeof(search), "${%s}", search);
            cvar.GetString(replace, sizeof(replace));
            ReplaceString(text, sizeof(text), search, replace);
        }
    }

    static ConVar cvar_hostname;
    if (cvar_hostname == null)
        cvar_hostname = FindConVar("hostname");

    cvar_hostname.GetString(buffer, sizeof(buffer));
    ReplaceString(text, sizeof(text), "${serverName}", buffer);

    GetCurrentMap(buffer, sizeof(buffer));
    ReplaceString(text, sizeof(text), "${mapName}", buffer);

    Format(buffer, sizeof(buffer), "%02d:%02d:%02d", g_iTimeCount / 3600, (g_iTimeCount % 3600) / 60, g_iTimeCount % 60);
    ReplaceString(text, sizeof(text), "${timeCount}", buffer);

    IntToString(g_iPlayerCount, buffer, sizeof(buffer));
    ReplaceString(text, sizeof(text), "${playerCount}", buffer);

    IntToString(GetServerMaxPlayers(), buffer, sizeof(buffer));
    ReplaceString(text, sizeof(text), "${maxPlayers}", buffer);

    IntToString(g_iCurrentChapter, buffer, sizeof(buffer));
    ReplaceString(text, sizeof(text), "${currentChapter}", buffer);

    IntToString(g_iMaxChapters, buffer, sizeof(buffer));
    ReplaceString(text, sizeof(text), "${maxChapters}", buffer);

    IntToString(g_iSurvivorFlow, buffer, sizeof(buffer));
    ReplaceString(text, sizeof(text), "${surFlow}", buffer);

    IntToString(g_iInfectedCount, buffer, sizeof(buffer));
    ReplaceString(text, sizeof(text), "${infectedCount}", buffer);

    FormatTime(buffer, sizeof(buffer), "%y-%m-%d %H:%M:%S");
    ReplaceString(text, sizeof(text), "${time}", buffer);

    static char weekDays[][] = { "星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日" };
    FormatTime(buffer, sizeof(buffer), "%u");
    int dayIndex = StringToInt(buffer) - 1;
    if (dayIndex >= 0 && dayIndex < sizeof(weekDays))
        Format(buffer, sizeof(buffer), "%s", weekDays[dayIndex]);
    else
        strcopy(buffer, sizeof(buffer), "未知");
    ReplaceString(text, sizeof(text), "${weekDay}", buffer);

    int tick = GetServerTickRate();
    if (tick > 0)
        IntToString(tick, buffer, sizeof(buffer));
    else
        strcopy(buffer, sizeof(buffer), "N/A");
    ReplaceString(text, sizeof(text), "${serverTick}", buffer);
}

static int GetServerMaxPlayers()
{
    static ConVar cvar_sv_maxplayers;
    if (cvar_sv_maxplayers == null)
        cvar_sv_maxplayers = FindConVar("sv_maxplayers");
    return cvar_sv_maxplayers == null ? 4 : cvar_sv_maxplayers.IntValue;
}

static int GetHighestSurvivorFlow()
{
    int target = L4D_GetHighestFlowSurvivor();
    float surMaxFlow = (target != -1) ? L4D2Direct_GetFlowDistance(target) : L4D2_GetFurthestSurvivorFlow();
    int flow = RoundToNearest(100.0 * surMaxFlow / g_fMapMaxFlow);
    return (flow < 100) ? flow : 100;
}

static int GetCurrentInfectedCount()
{
    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && GetClientTeam(i) == 3 && IsPlayerAlive(i))
            count++;
    }
    return count;
}

public Action Cmd_ReloadCustomHUDJson(int client, int args)
{
    LoadCustomHUDJson();
    return Plugin_Handled;
}