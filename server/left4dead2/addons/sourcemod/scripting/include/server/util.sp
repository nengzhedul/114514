// server/util.sp
// 通用工具函数，不包含任何特定功能

#if defined _util_included
 #endinput
#endif
#define _util_included

#include <sourcemod>

// 安全关闭句柄
void SafeCloseHandle(Handle &h)
{
    if (h != null)
    {
        delete h;
        h = null;
    }
}

// 检查玩家是否有 root 权限
bool HasRootAccess(int client)
{
    return (GetUserFlagBits(client) & ADMFLAG_ROOT) != 0;
}

// 检查地图是否有效
bool IsMapValidEx(const char[] map)
{
    if (!map[0])
        return false;

    char foundmap[1];
    return FindMap(map, foundmap, sizeof(foundmap)) == FindMap_Found;
}

// 日期计算相关函数
static int g_iMonthDays[12] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

bool IsLeapYear(int year)
{
    return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
}

int GetDaysInMonth(int year, int month)
{
    if (month == 2 && IsLeapYear(year))
        return 29;
    return g_iMonthDays[month - 1];
}

int DayOfYear(int year, int month, int day)
{
    int days = 0;
    for (int m = 1; m < month; m++)
        days += GetDaysInMonth(year, m);
    days += day;
    return days;
}

int DateDifference(int date1, int date2)
{
    int y1 = date1 / 10000;
    int m1 = (date1 / 100) % 100;
    int d1 = date1 % 100;

    int y2 = date2 / 10000;
    int m2 = (date2 / 100) % 100;
    int d2 = date2 % 100;

    int dayOfYear1 = DayOfYear(y1, m1, d1);
    int dayOfYear2 = DayOfYear(y2, m2, d2);

    int total = 0;
    for (int y = y1; y < y2; y++)
        total += IsLeapYear(y) ? 366 : 365;

    return total + (dayOfYear2 - dayOfYear1);
}