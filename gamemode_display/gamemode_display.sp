#pragma semicolon 1
#pragma newdecls required

/**
 * L4D2 Game Mode Display
 * 
 * 描述：
 *   该插件用于将 Left 4 Dead 2 的游戏模式内部名称）
 *   映射为中文显示名称，并通过 ConVar "l4d_gamemode_display" 供其他插件使用。
 * 
 * 作者：画風
 * 版本：1.0.0
 * 
 * 依赖：
 *   - SourceMod 1.10+
 *   - cjson.inc (用于 JSON 解析)
 * 
 * 工作原理：
 *   插件监听 mp_gamemode ConVar 的变化，当游戏模式改变时，
 *   根据预定义的映射表（从 JSON 文件加载）将内部模式名称转换为显示名称。
 *   如果未找到映射，则直接使用原始模式名称（对于以 "mutation" 开头的模式，可配置一个通用映射）。
 * 
 * ConVar：
 *   - l4d_gamemode_display (string, 默认: "未知模式", 通知)
 *       当前游戏模式的中文显示名称，只读（由插件自动更新）。
 * 
 * 命令：
 *   - sm_reload_gamemodes (权限: ADMFLAG_CONFIG)
 *       重新加载 json/gamemode.json 配置文件，并立即更新显示名称。
 * 
 * 配置文件：
 *   位置: addons/sourcemod/json/gamemode.json
 *   格式: JSON 对象，键为游戏模式内部名称，值为对应的显示字符串。
 *   示例:
 *   {
 *       "coop": "战役",
 *       "mutation4": "绝境",
 *       "mutation": "突变"   // 突变具体模式未找到的默认名称
 *   }
 *   首次运行时，如果文件不存在，插件会自动创建默认配置文件，包含基础映射。
 * 
 * 注意：
 *   - 插件需要 cjson 扩展支持，请确保已安装。
 *   - 配置文件路径为 addons/sourcemod/json/gamemode.json，目录会自动创建。
 *   - 插件在每次地图加载时也会更新显示，以确保准确。
 * 
 * 更新日志：
 *   1.0.0 - 初始版本
 */

#include <sourcemod>
#include <sdktools>
#include <cjson>        

#define PLUGIN_VERSION "1.0.0"

ConVar g_hGameModeDisplay = null;  
ConVar g_hGameMode = null;       
StringMap g_hMappings = null;    

// 默认映射
static char g_sDefaultKeys[][] = {"coop", "mutation4", ""};
static char g_sDefaultValues[][] = {"战役", "绝境", ""};

public Plugin myinfo = 
{
    name = "L4D2 Game Mode Display",
    author = "画風",
    description = "将游戏模式内部名称映射为中文显示字符串，并通过ConVar暴露",
    version = PLUGIN_VERSION,
    url = ""
};

public void OnPluginStart()
{
    g_hGameModeDisplay = CreateConVar("l4d_gamemode_display", 
                                       "未知模式", 
                                       "当前游戏模式的中文显示名称", 
                                       FCVAR_NOTIFY);

    g_hGameMode = FindConVar("mp_gamemode");
    if (g_hGameMode == null)
    {
        SetFailState("无法找到 mp_gamemode ConVar，游戏模式映射插件无法工作。");
    }

    HookConVarChange(g_hGameMode, OnGameModeChange);

    LoadGameModeMappings();

    UpdateGameModeDisplay();

    RegAdminCmd("sm_reload_gamemodes", Command_ReloadMappings, ADMFLAG_CONFIG, 
                "重新加载游戏模式映射配置文件 (data/json/gamemode.json)");
}

public void OnMapStart()
{
    // 换图时也更新一次，确保显示准确
    UpdateGameModeDisplay();
}

/**
 * 从 JSON 配置文件加载映射，若文件不存在则自动创建默认文件
 */
void LoadGameModeMappings()
{
    // 清理旧的映射
    if (g_hMappings != null)
    {
        delete g_hMappings;
    }
    g_hMappings = new StringMap();
    
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "json/gamemode.json");
  
    bool fileExists = FileExists(path);
    if (!fileExists)
    {
        LogMessage("配置文件不存在，尝试创建默认文件: %s", path);
        if (WriteDefaultJsonFile(path))
        {
            fileExists = true; 
        }
        else
        {
            LogError("无法创建默认配置文件，将使用内置默认映射。");
            SetDefaultMappings();
            return;
        }
    }

    JSONObject json = JSONObject.FromFile(path);
    if (json == null)
    {
        LogError("无法解析JSON配置文件 %s，使用默认映射。请检查文件格式。", path);
        SetDefaultMappings();
        return;
    }

    JSONObjectKeys keys = json.Keys();
    if (keys != null)
    {
        char key[64], value[64];
        while (keys.ReadKey(key, sizeof(key)))
        {
            if (json.GetString(key, value, sizeof(value)))
            {
                g_hMappings.SetString(key, value);
            }
            else
            {
                LogMessage("警告: 键 '%s' 的值不是字符串，已跳过", key);
            }
        }
        delete keys;
    }
    
    delete json;
    LogMessage("已从 %s 加载游戏模式映射", path);
}

/**
 * 设置默认映射（内置硬编码）
 */
void SetDefaultMappings()
{
    g_hMappings.Clear();
    for (int i = 0; g_sDefaultKeys[i][0] != '\0'; i++)
    {
        g_hMappings.SetString(g_sDefaultKeys[i], g_sDefaultValues[i]);
    }
}

/**
 * 将默认映射写入 JSON 文件（自动创建目录）
 */
bool WriteDefaultJsonFile(const char[] path)
{
    // 确保目录存在
    char dir[PLATFORM_MAX_PATH];
    strcopy(dir, sizeof(dir), path);
    
    int slash = FindCharInString(dir, '/', true);
    if (slash == -1)
        slash = FindCharInString(dir, '\\', true);
    
    if (slash != -1)
    {
        dir[slash] = '\0';
        if (!DirExists(dir))
        {
            if (!CreateDirectory(dir, 0, true))  // createPath = true 递归创建
            {
                LogError("无法创建目录: %s", dir);
                return false;
            }
        }
    }

    JSONObject obj = new JSONObject();
    for (int i = 0; g_sDefaultKeys[i][0] != '\0'; i++)
    {
        obj.SetString(g_sDefaultKeys[i], g_sDefaultValues[i]);
    }

    bool success = obj.ToFile(path);
    delete obj;

    if (!success)
    {
        LogError("无法写入默认配置文件: %s", path);
    }
    return success;
}

/**
 * 根据当前 mp_gamemode 的值更新显示ConVar
 */
void UpdateGameModeDisplay()
{
    if (g_hGameMode == null || g_hMappings == null)
        return;
    
    char mode[64];
    GetConVarString(g_hGameMode, mode, sizeof(mode));
    
    char display[64];
    
    if (!g_hMappings.GetString(mode, display, sizeof(display)))
    {
        if (StrContains(mode, "mutation") == 0 && strlen(mode) > 8)
        {
            if (!g_hMappings.GetString("mutation", display, sizeof(display)))
            {
                strcopy(display, sizeof(display), mode);
            }
        }
        else
        {
            strcopy(display, sizeof(display), mode);
        }
    }
    
    SetConVarString(g_hGameModeDisplay, display);
}

/**
 * mp_gamemode 变化时的回调
 */
public void OnGameModeChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
    UpdateGameModeDisplay();
}

/**
 * 重载映射配置的命令
 */
public Action Command_ReloadMappings(int client, int args)
{
    LoadGameModeMappings();
    UpdateGameModeDisplay();
    
    ReplyToCommand(client, "[SM] 游戏模式映射已重新加载。");
    return Plugin_Handled;
}