#pragma semicolon 1
#pragma newdecls required

/**
 * 踉跄控制开关 (Stagger Control Switch)
 * 
 * 描述：
 *   本插件允许独立控制特定类型的踉跄（Stagger）是否生效。
 *   主要针对以下几种情况：
 *   1. Boomer 爆炸造成的幸存者踉跄。
 *   2. Charger 撞墙（撞击墙壁或物体）造成的幸存者踉跄。
 *   3. 特殊感染者释放幸存者后，幸存者起身时的动画踉跄（例如 Hunter 扑空释放、Charger 携带/压制释放等）。
 * 
 * 作者：画風
 * 版本：1.0
 * 
 * 依赖：
 *   - SourceMod 1.7+
 *   - left4dhooks
 * 
 * 工作原理：
 *   插件利用 Left 4 Dead 2 提供的原生事件钩子 L4D2_OnStagger 和 L4D_OnDoAnimationEvent。
 *   对于 Charger 撞墙踉跄，通过 L4D2_OnChargerImpact 记录每个 Charger 最近一次撞墙的时间，
 *   然后在踉跄事件中检查受害者是否为幸存者，并在短时间内（0.2秒内）是否有 Charger 撞墙，
 *   以此判断是否为撞墙引发的踉跄，从而决定是否阻止。
 * 
 * ConVar：
 *   - l4d_stagger_boomer_switch (默认: 0)
 *       0 = 允许 Boomer 爆炸造成的踉跄（游戏默认行为）
 *       1 = 阻止 Boomer 爆炸造成的踉跄
 *   - l4d_stagger_charger_impact_switch (默认: 0)
 *       0 = 允许 Charger 撞墙造成的踉跄
 *       1 = 阻止 Charger 撞墙造成的踉跄
 *   - l4d_stagger_release_anim_switch (默认: 0)
 *       0 = 允许释放后的起身动画踉跄（如 Hunter/Charger 释放）
 *       1 = 阻止释放后的起身动画踉跄
 *   - l4d_stagger_debug (默认: 0)
 *       0 = 关闭调试输出
 *       1 = 在服务器控制台打印调试信息（用于排查问题）
 * 
 * 配置文件：
 *   插件使用 AutoExecConfig 自动生成配置文件。
 *   位置: cfg/sourcemod/l4d_stagger_control.cfg
 *   首次运行时自动创建，可在该文件中修改以上 ConVar 的默认值。
 * 
 * 注意：
 *   - 插件需要 left4dhooks 扩展支持，请确保已安装。
 * 
 * 更新日志：
 *   1.0 - 初始版本
 */

#include <sourcemod>
#include <left4dhooks>

ConVar g_cvBoomer;
ConVar g_cvChargerImpact;
ConVar g_cvReleaseAnim;
ConVar g_cvDebug;

float g_fChargerImpactTime[MAXPLAYERS+1];   

public Plugin myinfo =
{
	name = "踉跄控制开关",
	author = "画風",
	description = "独立控制 Boomer 踉跄、Charger 撞墙踉跄、释放动画踉跄的开关",
	version = "1.0",
	url = " "
};

public void OnPluginStart()
{
	g_cvBoomer        = CreateConVar("l4d_stagger_boomer_switch", "0", "0 = 允许 Boomer 踉跄, 1 = 阻止 Boomer 踉跄");
	g_cvChargerImpact = CreateConVar("l4d_stagger_charger_impact_switch", "0", "0 = 允许 Charger 撞墙踉跄, 1 = 阻止 Charger 撞墙踉跄");
	g_cvReleaseAnim   = CreateConVar("l4d_stagger_release_anim_switch", "0", "0 = 允许释放动画踉跄, 1 = 阻止释放动画踉跄");
	g_cvDebug         = CreateConVar("l4d_stagger_debug", "0", "0 = 关闭调试, 1 = 开启调试输出");

	AutoExecConfig(true, "l4d_stagger_control");
}

public void OnMapStart()
{
	for (int i = 1; i <= MaxClients; i++)
		g_fChargerImpactTime[i] = 0.0;
}

/**
 * Charger 撞墙事件：记录撞墙时间，用于后续踉跄判断。
 */
public void L4D2_OnChargerImpact(int client)
{
	g_fChargerImpactTime[client] = GetGameTime();
	if (g_cvDebug.BoolValue)
		PrintToServer("[Debug] Charger %N 撞墙，时间 %f", client, g_fChargerImpactTime[client]);
}

/**
 * 拦截物理/逻辑踉跄事件，根据配置决定是否阻止。
 */
public Action L4D2_OnStagger(int client, int source)
{
	float now = GetGameTime();
	
	if (source > 0 && source <= MaxClients && IsClientInGame(source) && GetClientTeam(source) == 3)
	{
		int class = GetEntProp(source, Prop_Send, "m_zombieClass");
		if (class == 2)
		{
			if (g_cvBoomer.IntValue == 1)
			{
				if (g_cvDebug.BoolValue)
					PrintToServer("[Debug] 阻止 Boomer 踉跄: 目标 %N, 来源 %N", client, source);
				return Plugin_Handled;
			}
			else
				return Plugin_Continue;
		}
	}

	if (GetClientTeam(client) == 2)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && GetClientTeam(i) == 3 && GetEntProp(i, Prop_Send, "m_zombieClass") == 6)
			{
				if (g_fChargerImpactTime[i] > 0.0 && now - g_fChargerImpactTime[i] <= 0.2)
				{
					if (g_cvChargerImpact.IntValue == 1)
					{
						if (g_cvDebug.BoolValue)
							PrintToServer("[Debug] 阻止 Charger 撞墙踉跄: 目标 %N (最近撞墙的 Charger: %N)", client, i);
						return Plugin_Handled;
					}
					break; 
				}
			}
		}
	}
	
	return Plugin_Continue;
}

/**
 * 拦截动画事件，根据配置决定是否阻止释放后的起身踉跄。
 */
public Action L4D_OnDoAnimationEvent(int client, int &event, int &variant_param)
{
	if (g_cvReleaseAnim.IntValue == 0)
		return Plugin_Continue;

	switch (event)
	{
		case PLAYERANIMEVENT_HUNTER_GETUP,          // Hunter 释放后幸存者起身
		     PLAYERANIMEVENT_POUNDED_BY_CHARGER,    // 被 Charger 撞击后起身（压制状态）
		     PLAYERANIMEVENT_CARRIED_BY_CHARGER,    // 被 Charger 携带后释放起身
		     PLAYERANIMEVENT_CHARGER_PUMMELED,      // 被 Charger 连续打击后释放起身
		     PLAYERANIMEVENT_VICTIM_SLAMMED_INTO_GROUND, // 被 Charger 撞墙后倒地起身
		     PLAYERANIMEVENT_IMPACT_BY_CHARGER:     // 被 Charger 撞击瞬间（可能触发起身动画）
		{
			if (g_cvDebug.BoolValue)
				PrintToServer("[Debug] 阻止释放动画踉跄: 事件 %d 发生于 %N", event, client);
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}