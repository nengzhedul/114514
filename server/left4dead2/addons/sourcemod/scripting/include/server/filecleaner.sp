// server/filecleaner.sp
// 自动清理错误日志

#include <sourcemod>
#include <sdktools>

static ConVar g_hAllowFileDelete;
static ConVar g_hDeleteTimeDiff;
static ConVar g_hAllowLog;
static ConVar g_hDeleteLogPath;
static char g_sLogDir[PLATFORM_MAX_PATH];
static char g_sDeleteLogPath[PLATFORM_MAX_PATH];
static File g_hDeleteLogFile;

void FileCleaner_OnPluginStart()
{
    g_hAllowFileDelete = CreateConVar("file_deleter_allow_delete", "1", "是否允许自动删除错误日志", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hDeleteTimeDiff = CreateConVar("file_deleter_time_different", "3", "删除超过多少天的错误日志", FCVAR_NOTIFY, true, 0.0);
    g_hAllowLog = CreateConVar("file_deleter_allow_log", "1", "是否记录删除日志", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hDeleteLogPath = CreateConVar("file_deleter_log_path", "logs/file_deleter_log.txt", "删除日志存放路径 (相对于 sourcemod/)", FCVAR_NOTIFY);

    g_hAllowFileDelete.AddChangeHook(OnAllowFileDeleteChanged);

    RegAdminCmd("sm_filedelete", Cmd_DeleteFiles, ADMFLAG_BAN, "手动触发错误日志删除");

    BuildPath(Path_SM, g_sLogDir, sizeof(g_sLogDir), "logs");
    UpdateDeleteLogPath();
}

void FileCleaner_OnConfigsExecuted()
{
    if (g_hAllowFileDelete.BoolValue)
        PrepareDeleteFile();
}

static void OnAllowFileDeleteChanged(ConVar convar, const char[] oldVal, const char[] newVal)
{
    if (g_hAllowFileDelete.BoolValue)
        PrepareDeleteFile();
}

static void UpdateDeleteLogPath()
{
    char buffer[64];
    g_hDeleteLogPath.GetString(buffer, sizeof(buffer));
    BuildPath(Path_SM, g_sDeleteLogPath, sizeof(g_sDeleteLogPath), buffer);
}

public Action Cmd_DeleteFiles(int client, int args)
{
    int deleted = PrepareDeleteFile();
    ReplyToCommand(client, "[错误文件删除] 已删除 %d 个超过 %d 天的错误日志文件",
                   deleted, g_hDeleteTimeDiff.IntValue);
    return Plugin_Continue;
}

static int PrepareDeleteFile()
{
    if (!g_hAllowFileDelete.BoolValue)
        return 0;

    if (!DirExists(g_sLogDir))
    {
        LogMessage("[错误文件删除] 日志目录不存在: %s", g_sLogDir);
        return 0;
    }

    SafeCloseHandle(g_hDeleteLogFile);
    if (g_hAllowLog.BoolValue)
    {
        g_hDeleteLogFile = OpenFile(g_sDeleteLogPath, FileExists(g_sDeleteLogPath) ? "a+" : "w");
    }

    int deletedCount = 0;
    DirectoryListing dir = OpenDirectory(g_sLogDir);
    if (dir == null)
    {
        LogError("[错误文件删除] 无法打开目录: %s", g_sLogDir);
        return 0;
    }

    char fileName[PLATFORM_MAX_PATH];
    FileType type;
    char nowDate[16];
    FormatTime(nowDate, sizeof(nowDate), "%Y%m%d");
    int now = StringToInt(nowDate);

    while (dir.GetNext(fileName, sizeof(fileName), type))
    {
        if (type != FileType_File)
            continue;

        int fileDate = ExtractFileDate(fileName);
        if (fileDate == -1)
            continue;

        int daysDiff = DateDifference(fileDate, now);
        if (daysDiff > g_hDeleteTimeDiff.IntValue)
        {
            char fullPath[PLATFORM_MAX_PATH];
            FormatEx(fullPath, sizeof(fullPath), "%s/%s", g_sLogDir, fileName);
            if (DeleteFile(fullPath))
            {
                deletedCount++;
                if (g_hAllowLog.BoolValue && g_hDeleteLogFile != null)
                {
                    char timeStr[32];
                    FormatTime(timeStr, sizeof(timeStr), "%Y-%m-%d %H:%M:%S");
                    WriteFileLine(g_hDeleteLogFile, "[错误文件删除] 已删除: %s [%s]", fileName, timeStr);
                }
            }
            else
            {
                LogError("[错误文件删除] 无法删除文件: %s", fullPath);
            }
        }
    }

    delete dir;

    if (deletedCount > 0 && g_hAllowLog.BoolValue && g_hDeleteLogFile != null)
    {
        WriteFileLine(g_hDeleteLogFile, "[错误文件删除] 本次共删除 %d 个超过 %d 天的错误日志文件\n",
                      deletedCount, g_hDeleteTimeDiff.IntValue);
    }

    SafeCloseHandle(g_hDeleteLogFile);
    return deletedCount;
}

static int ExtractFileDate(const char[] filename)
{
    int len = strlen(filename);
    int digitStart = -1;

    for (int i = 0; i < len; i++)
    {
        if (IsCharNumeric(filename[i]))
        {
            digitStart = i;
            break;
        }
    }

    if (digitStart != -1 && len - digitStart >= 8)
    {
        char dateStr[16];
        strcopy(dateStr, sizeof(dateStr), filename[digitStart]);
        dateStr[8] = '\0';
        return StringToInt(dateStr);
    }

    if (filename[0] == 'L' && len >= 7 && StrContains(filename, ".log") != -1)
    {
        if (IsCharNumeric(filename[1]) && IsCharNumeric(filename[2]) &&
            IsCharNumeric(filename[3]) && IsCharNumeric(filename[4]))
        {
            char year[8];
            FormatTime(year, sizeof(year), "%Y");
            char dateStr[16];
            Format(dateStr, sizeof(dateStr), "%s%c%c%c%c", year,
                   filename[1], filename[2], filename[3], filename[4]);
            return StringToInt(dateStr);
        }
    }

    return -1;
}