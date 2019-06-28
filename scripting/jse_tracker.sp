#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.1"

#define API_URL "https://api.jumpacademy.tf/mapinfo_json"

#include <sourcemod>
#include <sdktools>
#include <smlib/clients>
#include <smlib/entities>
#include <jse_core>
#include <ripext>
#include <tf2>
#include <multicolors>

Handle g_hTrackerLoadedForward;
Handle g_hCheckpointReachedForward;

int g_iMapID = -1;
bool g_bLoaded = false;

ArrayList g_hCourses;

#include <jse_tracker>
#include "jse_tracker_course.sp"
#include "jse_tracker_database.sp"

enum struct HashedCheckpoint {
	int iHash;
	int iTimestamp;
}

ConVar g_hCVProximity;

Checkpoint g_eNearestCheckpoint[MAXPLAYERS+1];
Checkpoint g_eLastCheckpoint[MAXPLAYERS+1];
ArrayList g_hProgress[MAXPLAYERS+1];

HTTPClient g_hHTTPClient;

Handle g_hTimer = null;

public Plugin myinfo = {
	name = "Jump Server Essentials - Tracker",
	author = PLUGIN_AUTHOR,
	description = "JSE player progress tracker module",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	CreateConVar("jse_tracker_version", PLUGIN_VERSION, "Jump Server Essentials tracker version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_hCVProximity = CreateConVar("jse_tracker_proximity", "1000.0", "Max distance to check near checkpoints", FCVAR_NOTIFY, true, 0.0);
	
	RegConsoleCmd("sm_whereami", cmdWhereAmI, "Locate calling player");
	RegConsoleCmd("sm_whereis", cmdWhereIs, "Locate player");

	RegConsoleCmd("sm_progress", cmdProgress, "Show player progress");

	DB_Connect();

	g_hHTTPClient = new HTTPClient(API_URL);
	g_hHTTPClient.FollowLocation = true;
	g_hHTTPClient.Timeout = 5;

	g_hCourses = new ArrayList();

	LoadTranslations("common.phrases");

	for (int i=1; i<=MaxClients; i++) {
		g_hProgress[i] = new ArrayList(sizeof(HashedCheckpoint));
	}

	g_hTrackerLoadedForward = CreateGlobalForward("OnTrackerLoaded", ET_Ignore, Param_Cell);
	g_hCheckpointReachedForward = CreateGlobalForward("OnCheckpointReached", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int sErrMax) {
	RegPluginLibrary("jse_tracker");
	Course_SetupNatives();

	CreateNative("IsTrackerLoaded", Native_IsLoaded);
	CreateNative("GetTrackerDatabase", Native_GetDatabase);
	CreateNative("GetTrackerCourses", Native_GetCourses);
	CreateNative("GetTrackerMapID", Native_GetMapID);
	CreateNative("GetPlayerNearestCheckpoint", Native_GetPlayerNearestCheckpoint);
	CreateNative("GetPlayerNewestCheckpoint", Native_GetPlayerNewestCheckpoint);
	CreateNative("GetPlayerLastCheckpoint", Native_GetPlayerLastCheckpoint);
	CreateNative("GetPlayerProgress", Native_GetPlayerProgress);
	CreateNative("ResetPlayerProgress", Native_ResetPlayerProgress);
}

public void OnMapStart() {
	DB_AddMap();

	for (int i=1; i<=MaxClients; i++) {
		ResetClient(i);
	}

	if (Client_GetCount(true, false)) {
		SetupTimer();
	}
}

public void OnMapEnd() {
	for (int i=0; i<g_hCourses.Length; i++) {
		Course iCourse = view_as<Course>(g_hCourses.Get(i));
		Course.Destroy(iCourse);
	}

	g_hCourses.Clear();

	g_iMapID = -1;
	g_bLoaded = false;

	delete g_hTimer;
}

public void OnClientPutInServer(int iClient) {
	SetupTimer();
}

public void OnClientDisconnect(int iClient) {
	ResetClient(iClient);

	if (!Client_GetCount(true, false)) {
		delete g_hTimer;
	}
}

// Custom Callbacks

public void HTTPRequestCallback_FetchedLayout(HTTPResponse hResponse, any aValue, const char[] sError) {
	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

	if (hResponse.Status == HTTPStatus_NoContent) {
		LogError("No map info found in repository for %s", sMapName);
		return;
	}

	if (hResponse.Status != HTTPStatus_OK) {
		LogError("Failed to fetch layout for map %s: $d %s", sMapName, hResponse.Status, sError);
		CreateTimer(10.0, Timer_Refetch);
		return;
	}

	JSONObject hMapData = view_as<JSONObject>(view_as<JSONObject>(hResponse.Data).Get(sMapName));
	if (hMapData == null) {
		LogError("Map %s not found in API results", sMapName);
		return;
	}

	JSONArray hLayoutData = view_as<JSONArray>(hMapData.Get("layout"));
	if (hLayoutData == null) {
		LogMessage("Map %s has no layout data", sMapName);
		delete hMapData;
		return;
	}

	Transaction hTxn = new Transaction();

	int iCoursesTotal = hLayoutData.Length;

	char sBuffer[1024];
	for (int i=0; i<iCoursesTotal; i++) {
		JSONObject hCourseData = view_as<JSONObject>(hLayoutData.Get(i));
		int iCourseID = hCourseData.GetInt("id");
		if (!hCourseData.GetString("name", sBuffer, sizeof(sBuffer))) {
			sBuffer[0] = '\0';
		}

		DB_AddCourse(hTxn, iCourseID, sBuffer);

		JSONArray hWaypointList = view_as<JSONArray>(hCourseData.Get("waypoints"));
		int iWaypointsTotal = hWaypointList.Length;

		for (int j=0; j<iWaypointsTotal; j++) {
			JSONObject hWaypointData = view_as<JSONObject>(hWaypointList.Get(j));

			sBuffer[0] = '\0';
			int iX, iY, iZ;
			
			if (!hWaypointData.GetString("identifier", sBuffer, sizeof(sBuffer))) {
				iX = hWaypointData.GetInt("x");
				iY = hWaypointData.GetInt("y");
				iZ = hWaypointData.GetInt("z");
			}

			DB_AddJump(hTxn, iCourseID, j+1, sBuffer, iX, iY, iZ);

			delete hWaypointData;
		}

		delete hWaypointList;

		JSONObject hControlPointData = view_as<JSONObject>(hCourseData.Get("controlpoint"));

		sBuffer[0] = '\0';
		int iX, iY, iZ;

		if (!hControlPointData.GetString("identifier", sBuffer, sizeof(sBuffer))) {
			iX = hControlPointData.GetInt("x");
			iY = hControlPointData.GetInt("y");
			iZ = hControlPointData.GetInt("z");
		}

		DB_AddControlPoint(hTxn, iCourseID, sBuffer, iX, iY, iZ);

		delete hControlPointData;
	}

	delete hLayoutData;
	delete hMapData;

	DB_ExecuteAddMapInfoTX(hTxn);
}

// Natives

public int Native_IsLoaded(Handle hPlugin, int iArgC) {
	return g_bLoaded;
}

public int Native_GetDatabase(Handle hPlugin, int iArgC) {
	return view_as<int>(g_hDatabase);
}

public int Native_GetCourses(Handle hPlugin, int iArgC) {
	return view_as<int>(g_hCourses);
}

public int Native_GetMapID(Handle hPlugin, int iArgC) {
	return g_iMapID;
}

public int Native_GetPlayerNearestCheckpoint(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);

	if (g_eNearestCheckpoint[iClient].iCourse) {
		SetNativeCellRef(2, g_eNearestCheckpoint[iClient].iCourse);
		SetNativeCellRef(3, g_eNearestCheckpoint[iClient].iJump);
		SetNativeCellRef(4, g_eNearestCheckpoint[iClient].iControlPoint);
		SetNativeCellRef(5, g_eNearestCheckpoint[iClient].iTimestamp);

		return true;
	}
	
	return false;
}

public int Native_GetPlayerNewestCheckpoint(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);

	ArrayList hProgress = g_hProgress[iClient];
	int iCheckpoints = hProgress.Length;
	if (iCheckpoints) {
		int iLatestTime = hProgress.Get(0, HashedCheckpoint::iTimestamp);
		int iLatestIdx = 0;

		for (int i=1; i<iCheckpoints; i++) {
			int iTimestamp = hProgress.Get(i, HashedCheckpoint::iTimestamp);
			if (iTimestamp > iLatestTime) {
				iLatestTime = iTimestamp;
				iLatestIdx = i;
			}
		}

		Course iCourse;
		Jump iJump;
		ControlPoint iControlPoint;
		FromProgressHash(hProgress.Get(iLatestIdx, HashedCheckpoint::iHash), iCourse, iJump, iControlPoint);

		SetNativeCellRef(2, iCourse);
		SetNativeCellRef(3, iJump);
		SetNativeCellRef(4, iControlPoint);
		SetNativeCellRef(5, iLatestTime);

		return true;
	}

	return false;
}

public int Native_GetPlayerLastCheckpoint(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);

	if (g_eLastCheckpoint[iClient].iCourse) {
		SetNativeCellRef(2, g_eLastCheckpoint[iClient].iCourse);
		SetNativeCellRef(3, g_eLastCheckpoint[iClient].iJump);
		SetNativeCellRef(4, g_eLastCheckpoint[iClient].iControlPoint);
		SetNativeCellRef(5, g_eLastCheckpoint[iClient].iTimestamp);

		return true;
	}
	
	return false;
}

public int Native_GetPlayerProgress(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);

	ArrayList hList = GetNativeCell(2);
	if (hList.BlockSize != sizeof(Checkpoint)) {
		LogError("ArrayList block must match Checkpoint enum-struct size");
		return 0;
	}

	Checkpoint eCheckpoint;
	HashedCheckpoint eHashedCheckpoint;

	ArrayList hProgress = g_hProgress[iClient];
	for (int i=0; i<hProgress.Length; i++) {
		hProgress.GetArray(i, eHashedCheckpoint, sizeof(HashedCheckpoint));
		FromProgressHash(eHashedCheckpoint.iHash, eCheckpoint.iCourse, eCheckpoint.iJump, eCheckpoint.iControlPoint);
		eCheckpoint.iTimestamp = eHashedCheckpoint.iTimestamp;

		hList.PushArray(eCheckpoint);
	}

	return hList.Length;
}

public int Native_ResetPlayerProgress(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);
	ResetClient(iClient);
}

// Timers

public Action Timer_Refetch(Handle hTimer) {
	FetchMapData();
	
	return Plugin_Handled;
}

public Action Timer_TrackPlayers(Handle hTimer, any aData) {
	int iTime = GetTime();

	for (int i=1; i<=MaxClients; i++) {
		g_eNearestCheckpoint[i].iCourse = NULL_COURSE;
		g_eNearestCheckpoint[i].iJump = NULL_JUMP;
		g_eNearestCheckpoint[i].iControlPoint = NULL_CONTROLPOINT;
		g_eNearestCheckpoint[i].iTimestamp = iTime;
	}

	int iClients[MAXPLAYERS];
	float fMinDist[MAXPLAYERS + 1] =  { view_as<float>(0x7F800000), ... }; // +inf

	float fOrigin[3], fPos[3];
	for (int i=0; i<g_hCourses.Length; i++) {
		Course iCourseIter = g_hCourses.Get(i);

		ArrayList hJumps = iCourseIter.hJumps;
		for (int j=0; j<hJumps.Length; j++) {
			Jump iJumpIter = hJumps.Get(j);
			iJumpIter.GetOrigin(fOrigin);

			int iClientsCount = GetClientsInRange(fOrigin, RangeType_Visibility, iClients, sizeof(iClients));
			for (int k = 0; k < iClientsCount; k++) {
				int iClient = iClients[k];
				if (GetClientTeam(iClient) > view_as<int>(TFTeam_Spectator)) {
					GetClientEyePosition(iClient, fPos);

					float fDist = GetVectorDistance(fPos, fOrigin);
					if ((fDist < g_hCVProximity.FloatValue) && (fDist < fMinDist[iClient]) && IsVisible(fPos, fOrigin)) {
						g_eNearestCheckpoint[iClient].iCourse = iCourseIter;
						g_eNearestCheckpoint[iClient].iJump = iJumpIter;
						g_eNearestCheckpoint[iClient].iControlPoint = NULL_CONTROLPOINT;
						fMinDist[iClient] = fDist;
					}

				}
			}
		}

		ControlPoint iControlPointItr = iCourseIter.iControlPoint;
		if (iControlPointItr) {
			iControlPointItr.GetOrigin(fOrigin);

			int iClientsCount = GetClientsInRange(fOrigin, RangeType_Visibility, iClients, sizeof(iClients));
			for (int k = 0; k < iClientsCount; k++) {
				int iClient = iClients[k];
				if (GetClientTeam(iClient) > view_as<int>(TFTeam_Spectator)) {
					GetClientEyePosition(iClient, fPos);

					float fDist = GetVectorDistance(fPos, fOrigin);
					if ((fDist < g_hCVProximity.FloatValue) && (fDist < fMinDist[iClient]) && IsVisible(fPos, fOrigin)) {
						g_eNearestCheckpoint[iClient].iCourse = iCourseIter;
						g_eNearestCheckpoint[iClient].iJump = NULL_JUMP;
						g_eNearestCheckpoint[iClient].iControlPoint = iControlPointItr;
						fMinDist[iClient] = fDist;
					}
				}
			}
		}
	}

	HashedCheckpoint eHashedCheckpoint;

	for (int i=1; i<=MaxClients; i++) {
		Course iCourseIter = g_eNearestCheckpoint[i].iCourse;
		if (iCourseIter) {
			Jump iJumpIter0 = g_eNearestCheckpoint[i].iJump;
			int iJumpNumber = iJumpIter0 ? iJumpIter0.iNumber : 0;
			ControlPoint iControlPointIter = g_eNearestCheckpoint[i].iControlPoint;

			if (iTime > g_eLastCheckpoint[i].iTimestamp) {
				g_eLastCheckpoint[i].iCourse = iCourseIter;
				g_eLastCheckpoint[i].iJump = iJumpIter0;
				g_eLastCheckpoint[i].iControlPoint = iControlPointIter;
				g_eLastCheckpoint[i].iTimestamp = iTime;
			}

			int iProgress0 = ToProgressHash(iCourseIter, iJumpIter0, g_eNearestCheckpoint[i].iControlPoint);
			if (g_hProgress[i].FindValue(iProgress0, HashedCheckpoint::iHash) == -1) {
				if (iControlPointIter) {
					ArrayList hJumps = iCourseIter.hJumps;
					for (int j=0; j<hJumps.Length; j++) {
						Jump iJumpIter = hJumps.Get(j);

						int iProgress = ToProgressHash(iCourseIter, iJumpIter, NULL_CONTROLPOINT);
						if (g_hProgress[i].FindValue(iProgress, HashedCheckpoint::iHash) == -1) {
							eHashedCheckpoint.iHash = iProgress;
							eHashedCheckpoint.iTimestamp = GetTime();
							g_hProgress[i].PushArray(eHashedCheckpoint);

							SortADTArray(g_hProgress[i], Sort_Ascending, Sort_Integer);

							Call_StartForward(g_hCheckpointReachedForward);
							Call_PushCell(i);
							Call_PushCell(iCourseIter);
							Call_PushCell(iJumpIter);
							Call_PushCell(NULL_CONTROLPOINT);
							Call_Finish();
						}
					}
				} else if (iJumpNumber > 1) {
					ArrayList hJumps = iCourseIter.hJumps;
					for (int j=0; j<hJumps.Length; j++) {
						Jump iJumpIter = hJumps.Get(j);

						if (iJumpIter.iNumber >= iJumpNumber) {
							break;
						}

						int iProgress = ToProgressHash(iCourseIter, iJumpIter, NULL_CONTROLPOINT);
						if (g_hProgress[i].FindValue(iProgress, HashedCheckpoint::iHash) == -1) {
							eHashedCheckpoint.iHash = iProgress;
							eHashedCheckpoint.iTimestamp = GetTime();
							g_hProgress[i].PushArray(eHashedCheckpoint);

							SortADTArray(g_hProgress[i], Sort_Ascending, Sort_Integer);

							Call_StartForward(g_hCheckpointReachedForward);
							Call_PushCell(i);
							Call_PushCell(iCourseIter);
							Call_PushCell(iJumpIter);
							Call_PushCell(NULL_CONTROLPOINT);
							Call_Finish();
						}
					}
				}


				if (GetEntityFlags(i) & FL_ONGROUND) {
					eHashedCheckpoint.iHash = iProgress0;
					eHashedCheckpoint.iTimestamp = GetTime();
					g_hProgress[i].PushArray(eHashedCheckpoint);


					SortADTArray(g_hProgress[i], Sort_Ascending, Sort_Integer);

					Call_StartForward(g_hCheckpointReachedForward);
					Call_PushCell(i);
					Call_PushCell(iCourseIter);
					Call_PushCell(iJumpIter0);
					Call_PushCell(iControlPointIter);
					Call_Finish();
				}
			}
		}
		
	}
	
	return Plugin_Continue;
}

// Helpers

void FetchMapData() {
	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

	char sEndpoint[128];
	FormatEx(sEndpoint, sizeof(sEndpoint), "/?map=%s&layout=1", sMapName);

	g_hHTTPClient.Get(sEndpoint, HTTPRequestCallback_FetchedLayout);
}

bool LocatePlayer(int iClient, Course &iCourse=NULL_COURSE, Jump &iJump=NULL_JUMP, ControlPoint &iControlPoint=NULL_CONTROLPOINT) {
	float fPos[3];
	GetClientEyePosition(iClient, fPos);

	return LocatePosition(fPos, iCourse, iJump, iControlPoint);
}

void ResetClient(int iClient) {
	g_eNearestCheckpoint[iClient].iCourse = NULL_COURSE;
	g_eNearestCheckpoint[iClient].iJump = NULL_JUMP;
	g_eNearestCheckpoint[iClient].iControlPoint = NULL_CONTROLPOINT;
	g_eNearestCheckpoint[iClient].iTimestamp = 0;

	g_eLastCheckpoint[iClient].iCourse = NULL_COURSE;
	g_eLastCheckpoint[iClient].iJump = NULL_JUMP;
	g_eLastCheckpoint[iClient].iControlPoint = NULL_CONTROLPOINT;
	g_eLastCheckpoint[iClient].iTimestamp = 0;

	g_hProgress[iClient].Clear();
}

bool LocatePosition(float fPos[3], Course &iCourse, Jump &iJump, ControlPoint &iControlPoint, float fMinDist=view_as<float>(0x7F800000)) {
	// 0x7F800000 = +inf
	
	iCourse=NULL_COURSE;
	iJump=NULL_JUMP;
	iControlPoint=NULL_CONTROLPOINT;

	float fOrigin[3];
	for (int i=0; i<g_hCourses.Length; i++) {
		Course iCourseIter = g_hCourses.Get(i);

		ArrayList hJumps = iCourseIter.hJumps;
		for (int j=0; j<hJumps.Length; j++) {
			Jump iJumpIter = hJumps.Get(j);
			iJumpIter.GetOrigin(fOrigin);
			
			float fDist = GetVectorDistance(fPos, fOrigin);
			if ((fDist < fMinDist) && IsVisible(fPos, fOrigin)) {
				iCourse = iCourseIter;
				iJump = iJumpIter;
				iControlPoint = NULL_CONTROLPOINT;
				fMinDist = fDist;
			}
		}

		ControlPoint iControlPointItr = iCourseIter.iControlPoint;
		if (iControlPointItr) {
			iControlPointItr.GetOrigin(fOrigin);

			float fDist = GetVectorDistance(fPos, fOrigin);
			if ((fDist < fMinDist) && IsVisible(fPos, fOrigin)) {
				iCourse = iCourseIter;
				iJump = NULL_JUMP;
				iControlPoint = iControlPointItr;
				fMinDist = fDist;
			}	
		}
	}

	return iJump || iControlPoint;
}

bool IsVisible(float fPos[3], float fPosTarget[3]) {
	Handle hTr = TR_TraceRayFilterEx(fPos, fPosTarget, MASK_SHOT_HULL, RayType_EndPoint, TraceFilter_Environment);
	if (!TR_DidHit(hTr)) {
		CloseHandle(hTr);
		return true;
	}
	CloseHandle(hTr);
	
	return false;
}

public bool TraceFilter_Environment(int iEntity, int iMask) {
	return false;
}

void SetupTimer() {
	if (g_hTimer == null) {
		g_hTimer = CreateTimer(0.1, Timer_TrackPlayers, INVALID_HANDLE, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

int ToProgressHash(Course iCourse, Jump iJump, ControlPoint iControlPoint) {
	int iCourseNumber = iCourse.iNumber & 0xFF;
	int iJumpNumber = iJump ? iJump.iNumber & 0xFF : 0;
	int iCapped = view_as<int>(iControlPoint != NULL_CONTROLPOINT) & 0xFF;

	return (iCourseNumber << 24) | (iCapped << 16) | (iJumpNumber << 8);
}

bool FromProgressHash(int iProgressHash, Course &iCourse, Jump &iJump, ControlPoint &iControlPoint) {
	int iCourseNumber 	=  (iProgressHash >> 24) & 0xFF;
	bool bCapped 		= ((iProgressHash >>  16) & 0xFF) != 0;
	int iJumpNumber 	=  (iProgressHash >>  8) & 0xFF;

	// Restore unsigned to signed (short)
	if (iCourseNumber > 127) {
		iCourseNumber = iCourseNumber-256;
	}

	iCourse = NULL_COURSE;
	iJump = NULL_JUMP;
	iControlPoint = NULL_CONTROLPOINT;

	for (int j=0; j<g_hCourses.Length; j++) {
		Course iCourseIter = g_hCourses.Get(j);
		if (iCourseIter.iNumber == iCourseNumber) {
			iCourse = iCourseIter;
			break;
		}
	}

	if (!iCourse) {
		return false;
	}

	if (bCapped) {
		iControlPoint = iCourse.iControlPoint;
	} else {
		iJump = iCourse.hJumps.Get(iJumpNumber-1);
	}

	return true;
}

// Commands

public Action cmdWhereAmI(int iClient, int iArgC) {
	if (!iClient) {
		ReplyToCommand(iClient, "[jse] You cannot run this command from server console.");
		return Plugin_Handled;
	}

	Course iCourse;
	Jump iJump;
	ControlPoint iControlPoint;
	if (LocatePlayer(iClient, iCourse, iJump, iControlPoint)) {
		char sCourseName[128];
		iCourse.GetName(sCourseName, sizeof(sCourseName));

		char sBuffer[128];
		if (iJump) {
			FormatEx(sBuffer, sizeof(sBuffer), "jump %d", iJump.iNumber);
		} else {
			FormatEx(sBuffer, sizeof(sBuffer), "control point");
		}

		CPrintToChat(iClient, "{dodgerblue}[jse] {white}You are on %s %s.", sCourseName, sBuffer);
	} else {
		CPrintToChat(iClient, "{dodgerblue}[jse] {white}You are not near any jump."); 
	}

	return Plugin_Handled;
}

public Action cmdWhereIs(int iClient, int iArgC) {
	char sArg1[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));
	
	int iTarget = FindTarget(iClient, sArg1, false, false);
	if (iTarget != -1) {
		if (GetClientTeam(iTarget) <= view_as<int>(TFTeam_Spectator)) {
			CReplyToCommand(iClient, "\x04[jse] \x01%N has not joined a team.", iTarget);
			return Plugin_Continue;
		}

		Course iCourse;
		Jump iJump;
		ControlPoint iControlPoint;

		if (LocatePlayer(iTarget, iCourse, iJump, iControlPoint)) {
			char sCourseName[128];
			iCourse.GetName(sCourseName, sizeof(sCourseName));

			char sBuffer[128];
			if (iJump) {
				FormatEx(sBuffer, sizeof(sBuffer), "jump %d", iJump.iNumber);
			} else {
				FormatEx(sBuffer, sizeof(sBuffer), "control point");
			}

			CReplyToCommand(iClient, "{dodgerblue}[jse] {white}%N is at %s %s.", iTarget, sCourseName, sBuffer);
		} else {
			CReplyToCommand(iClient, "{dodgerblue}[jse] {white}%N is not found near any jump.", iTarget);
		}
	}

	return Plugin_Handled;
}

public Action cmdProgress(int iClient, int iArgC) {
	if (!g_hCourses.Length) {
		CReplyToCommand(iClient, "{dodgerblue}[jse] {white}No courses were found for this map.");
		return Plugin_Handled;
	}

	char sTargetName[MAX_TARGET_LENGTH];
	int iTargetList[MAXPLAYERS], iTargetCount;
	bool bTnIsML;

	if (iArgC == 1) {
		char sArg1[32];
		GetCmdArg(1, sArg1, sizeof(sArg1));
	 
		if ((iTargetCount = ProcessTargetString(
				sArg1,
				iClient,
				iTargetList,
				MAXPLAYERS,
				COMMAND_FILTER_NO_IMMUNITY,
				sTargetName,
				sizeof(sTargetName),
				bTnIsML)) <= 0) {
			ReplyToTargetError(iClient, iTargetCount);
			return Plugin_Handled;
		}

		CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Showing progress for %s:", sTargetName);
	} else {
		iTargetList[iTargetCount++] = iClient;

		CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Showing your progress:");
	}

	char sBuffer[4096];
	for (int i = 0; i < iTargetCount; i++) {
		int iTarget = iTargetList[i];

		if (!g_hProgress[iTarget].Length) {
			if (iArgC) {
				CReplyToCommand(iClient, "{dodgerblue}- %N has not been to any jumps.", iTarget);
			} else {
				CReplyToCommand(iClient, "{dodgerblue}- You have not been to any jumps.");
			}

			continue;
		}

		if (iArgC) {
			FormatEx(sBuffer, sizeof(sBuffer), "{white}- %N:\n", iTarget);
		}

		ArrayList hProgress = g_hProgress[iTarget];

		for (int j=0; j<g_hCourses.Length; j++) {
			Course iCourse = g_hCourses.Get(j);
			char sCourseName[128];
			iCourse.GetName(sCourseName, sizeof(sCourseName));

			int iJumpCount = 0;
			int iJumpsTotal = iCourse.hJumps.Length;

			for (int k=0; k<hProgress.Length; k++) {
				Course iCourseItr;
				Jump iJumpItr;
				ControlPoint iControlPointItr;

				FromProgressHash(hProgress.Get(k, HashedCheckpoint::iHash), iCourseItr, iJumpItr, iControlPointItr);

				if (iCourse == iCourseItr) {
					if (iControlPointItr) {
						Format(sBuffer, sizeof(sBuffer), "%s\t{white}%20s\t{lightgray}%2d/%2d\t\t{lime}Completed\n", sBuffer, sCourseName, iJumpsTotal, iJumpsTotal);
						iJumpCount = 0;
						break;
					} else {
						iJumpCount++;
					}
				}
			}

			if (iJumpCount) {
				Format(sBuffer, sizeof(sBuffer), "%s\t{white}%20s\t{lightgray}%2d/%2d\n", sBuffer, sCourseName, iJumpCount, iJumpsTotal);
			}
		}

		CReplyToCommand(iClient, sBuffer);
	}

	return Plugin_Handled;
}
