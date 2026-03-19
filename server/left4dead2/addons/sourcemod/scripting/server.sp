#pragma semicolon 1
#pragma newdecls required

/**
 * artserver (整合)
 * 
 * 描述：
 *   整合了服务器常用功能，包括 Convars 修改、自动清理错误日志、自定义 HUD、
 *   服名 JSON 管理以及地图投票系统。
 * 
 * 作者：画風
 * 版本：1.6.0
 * 
 * 依赖：
 *   - SourceMod 1.10+
 *   - SDKHooks, SDKTools
 *   - DHooks, left4dhooks
 *   - l4d2_ems_hud
 *   - cjson
 *   - l4d2_nativevote (https://github.com/fdxx/l4d2_nativevote)
 *   - l4d2_source_keyvalues (https://github.com/fdxx/l4d2_source_keyvalues)
 *   - colors.inc
 *   - localizer.inc
 *   - 可选: map_changer (用于设置下一张地图)
 * 
 * 工作原理：
 *   插件通过将多个功能模块（自杀、文件清理、自定义HUD、服名管理、地图投票、管理员命令）整合在一起，
 *   利用 SourceMod 的事件、命令和 ConVar 系统提供统一的服务器管理体验。各模块独立初始化，
 *   通过钩子函数响应游戏事件和玩家命令，实现对应功能。
 * 
 * ConVar：
 *   - l4d2_survivor_suicide (默认: 1) 自杀模式: 0=禁用, 1=倒地/挂边, 2=无条件。
 *   - file_deleter_allow_delete (默认: 1) 是否允许自动删除错误日志。
 *   - file_deleter_time_different (默认: 3) 删除超过多少天的错误日志。
 *   - file_deleter_allow_log (默认: 1) 是否记录删除日志。
 *   - file_deleter_log_path (默认: logs/file_deleter_log.txt) 删除日志存放路径。
 *   - l4d2_custom_hud_enable (默认: 1) 启用/禁用自定义 HUD 显示。
 *   - notify_map_next (默认: 1) 终局提示投票下一张地图的方式 (1=聊天,2=提示,4=菜单)。
 * 
 * 命令：
 *   - !ars <cvar> <value>         (管理员) 修改任何服务器参数。
 *   - !restartmap                  (管理员) 3秒后重启当前地图。
 *   - !filedelete                   (管理员) 手动触发错误日志删除。
 *   - !zs / !kill                    (玩家) 生还者自杀（根据自杀模式）。
 *   - !kb                            (玩家) 踢出所有电脑生还者（需 root 权限）。
 *   - !custom_hud_reload            (管理员) 重新加载 HUD 配置文件 server_hud.json。
 *   - !host [新服名]                 (管理员) 无参时重载 JSON 中的服名；带参时设置新服名并保存。
 *   - !v3 / !maps / !chmap / !vmap / !votemap   (玩家) 打开地图投票菜单。
 *   - !mapvote / !mapnext / !votenext            (玩家) 在终局投票设置下一张地图。
 *   - !reload_vpk / !update_vpk      (管理员) 重新加载 VPK 文件并更新地图列表。
 *   - !missions_export <文件>        (管理员) 导出当前任务列表到指定文件。
 * 
 * 配置文件：
 *   - sourcemod/json/server_hostname.json  : 保存服务器名称，格式: {"hostname":"服务器名"}
 *   - sourcemod/json/server_hud.json       : 自定义 HUD 布局配置。
 *   - translations/missions.phrases.txt    : 地图任务名称翻译文件（由插件自动生成）。
 *   - translations/chapters.phrases.txt    : 章节名称翻译文件（由插件自动生成）。
 * 
 * 注意：
 *   - 地图投票功能需要 map_changer 插件支持设置下一张地图 (可选)。
 *   - 插件在 AskPluginLoad2 中标记了 "l4d2_map_vote" 库，并可选使用 MC_SetNextMap 原生函数。
 *   - 所有子模块的代码分别位于 server/ 目录下的 .sp 文件中。
 * 
 * 更新日志：
 *   1.6.0 - 当前版本，整合多个功能模块，优化代码结构。
 */

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <left4dhooks>
#include <l4d2_ems_hud>
#include <cjson>
#include <l4d2_nativevote>
#include <l4d2_source_keyvalues>
#include <colors>
#include <localizer>

#include "server/util.sp"
#include "server/suicide.sp"
#include "server/filecleaner.sp"
#include "server/customhud.sp"
#include "server/hostname.sp"
#include "server/mapvote.sp"
#include "server/admincmds.sp"

public Plugin myinfo = 
{
    name        = "artserver (整合)",
    author      = "画風",
    description = "整合插件",
    version     = "1.6.0",
    url         = ""
};

public void OnPluginStart()
{
    Suicide_OnPluginStart();
    FileCleaner_OnPluginStart();
    CustomHUD_OnPluginStart();
    Hostname_OnPluginStart();
    MapVote_OnPluginStart();
    AdminCmds_OnPluginStart();
}

public void OnMapStart()
{
    CustomHUD_OnMapStart();
    MapVote_OnMapStart();
}

public void OnConfigsExecuted()
{
    FileCleaner_OnConfigsExecuted();
    Hostname_OnConfigsExecuted();
    MapVote_OnConfigsExecuted();
}

public void OnClientConnected(int client)
{
    CustomHUD_OnClientConnected(client);
}

public void OnClientDisconnect(int client)
{
    CustomHUD_OnClientDisconnect(client);
}

public Action OnClientSayCommand(int client, const char[] command, const char[] args)
{
    if (Suicide_OnClientSayCommand(client, command, args))
        return Plugin_Handled;
    return Plugin_Continue;
}

public void OnLibraryAdded(const char[] name)
{
    MapVote_OnLibraryAdded(name);
}

public void OnLibraryRemoved(const char[] name)
{
    MapVote_OnLibraryRemoved(name);
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    RegPluginLibrary("l4d2_map_vote");
    MarkNativeAsOptional("MC_SetNextMap");
    return APLRes_Success;
}