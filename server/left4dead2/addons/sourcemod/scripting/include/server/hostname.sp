// server/hostname.sp
// 服名JSON管理

#include <sourcemod>
#include <cjson>

static ConVar g_hHostname;
static char g_sHostnameFilePath[PLATFORM_MAX_PATH];
static char g_sHostnameBuffer[PLATFORM_MAX_PATH];

void Hostname_OnPluginStart()
{
    g_hHostname = FindConVar("hostname");
    BuildPath(Path_SM, g_sHostnameFilePath, sizeof(g_sHostnameFilePath), "json/server_hostname.json");

    RegConsoleCmd("sm_host", Cmd_Hostname, "重载服名或设置新服名: !host [新服名] (JSON格式)");
}

void Hostname_OnConfigsExecuted()
{
    LoadHostnameFromFile();
}

public Action Cmd_Hostname(int client, int args)
{
    if (!HasRootAccess(client))
    {
        PrintToChat(client, "\x04[提示]\x05只限管理员使用该指令.");
        return Plugin_Handled;
    }

    if (args == 0)
    {
        LoadHostnameFromFile();
        PrintToChat(client, "\x04[提示]\x05已重新加载服名配置文件 (JSON) 使用 !host 空格+内容 可设置新服名.");
    }
    else
    {
        char newName[64];
        GetCmdArgString(newName, sizeof(newName));
        SaveHostnameToFile(newName);
        PrintToChat(client, "\x04[提示]\x05已设置新服名为: \x03%s\x04.", newName);
    }

    return Plugin_Handled;
}

static void LoadHostnameFromFile()
{
    if (!FileExists(g_sHostnameFilePath))
    {
        SaveHostnameToFile("猜猜这个是谁的萌新服?");
        return;
    }

    JSONObject json = JSONObject.FromFile(g_sHostnameFilePath);
    if (json == null)
    {
        LogError("无法解析服名JSON文件: %s", g_sHostnameFilePath);
        return;
    }

    char hostname[PLATFORM_MAX_PATH];
    if (json.GetString("hostname", hostname, sizeof(hostname)))
    {
        TrimString(hostname);
        if (strlen(hostname) > 0)
        {
            g_hHostname.SetString(hostname);
            strcopy(g_sHostnameBuffer, sizeof(g_sHostnameBuffer), hostname);
        }
    }
    else
    {
        LogError("JSON文件中缺少 'hostname' 字段");
    }

    delete json;
}

static void SaveHostnameToFile(const char[] newName)
{
    JSONObject json = new JSONObject();
    json.SetString("hostname", newName);

    if (!json.ToFile(g_sHostnameFilePath))
    {
        LogError("无法保存服名JSON文件: %s", g_sHostnameFilePath);
        delete json;
        return;
    }

    delete json;

    strcopy(g_sHostnameBuffer, sizeof(g_sHostnameBuffer), newName);
    TrimString(g_sHostnameBuffer);
    g_hHostname.SetString(g_sHostnameBuffer);
}