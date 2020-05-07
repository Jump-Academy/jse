#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.3.2"

#define API_URL "https://api.jumpacademy.tf/mapinfo_json"

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <smlib/clients>
#include <smlib/entities>
#include <jse_core>
#include <ripext>
#include <tf2>
#include <tf2_stocks>
#include <multicolors>

GlobalForward g_hTrackerLoadedForward;
GlobalForward g_hCheckpointReachedForward;
GlobalForward g_hNewCheckpointReachedForward;

int g_iMapID = -1;
bool g_bLoaded = false;

ArrayList g_hCourses;
int g_iNormalCourses;
int g_iBonusCourses;

#include <jse_tracker>
#include "jse_tracker_course.sp"
#include "jse_tracker_database.sp"

ConVar g_hCVProximity;
ConVar g_hCVTeleSettleTime;
ConVar g_hCVInterval;

float g_fProximity;
float g_fTeleSettleTime;

Checkpoint g_eNearestCheckpoint[MAXPLAYERS+1];
Checkpoint g_eNearestCheckpointLanded[MAXPLAYERS+1];

ArrayList g_hProgress[MAXPLAYERS+1];

float g_fLastTeleport[MAXPLAYERS+1];

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
	g_hCVTeleSettleTime = CreateConVar("jse_tracker_tele_settle_time", "1.0", "Time in seconds to ignore checkpoints after touching a teleport trigger", FCVAR_NOTIFY, true, 0.0);
	g_hCVInterval = CreateConVar("jse_tracker_interval", "0.5", "Time in seconds between progress checks", FCVAR_NOTIFY, true, 0.0);
	
	RegConsoleCmd("sm_whereami", cmdWhereAmI, "Locate calling player");
	RegConsoleCmd("sm_whereis", cmdWhereIs, "Locate player");

	RegConsoleCmd("sm_progress", cmdProgress, "Show player progress");

	DB_Connect();

	g_hHTTPClient = new HTTPClient(API_URL);
	g_hHTTPClient.FollowLocation = true;
	g_hHTTPClient.Timeout = 5;

	g_hCourses = new ArrayList();

	HookEvent("teamplay_round_start", Event_RoundStart);

	LoadTranslations("common.phrases");

	// Late load
	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i)) {
			g_hProgress[i] = new ArrayList(sizeof(Checkpoint));
		}
	}

	g_hTrackerLoadedForward = new GlobalForward("OnTrackerLoaded", ET_Ignore, Param_Cell);
	g_hCheckpointReachedForward = new GlobalForward("OnCheckpointReached", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	g_hNewCheckpointReachedForward = new GlobalForward("OnNewCheckpointReached", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

	AutoExecConfig(true, "jse_tracker");
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
	CreateNative("ResolveCourseNumber", Native_ResolveCourseNumber);
	CreateNative("ResolveJumpNumber", Native_ResolveJumpNumber);
	CreateNative("GetCourseDisplayName", Native_GetCourseDisplayName);
	CreateNative("GetCheckpointDisplayName", Native_GetCheckpointDisplayName);
	CreateNative("GetCourseCheckpointDisplayName", Native_GetCourseCheckpointDisplayName);
}

public void OnMapStart() {
	DB_AddMap();

	for (int i=1; i<=MaxClients; i++) {
		ResetClient(i);
	}

	if (Client_GetCount(true, false)) {
		SetupTeleportHook();
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
	g_hProgress[iClient] = new ArrayList(sizeof(Checkpoint));

	SetupTimer();
}

public void OnClientDisconnect(int iClient) {
	ResetClient(iClient);
	delete g_hProgress[iClient];

	if (!Client_GetCount(true, false)) {
		delete g_hTimer;
	}
}

public void OnConfigsExecuted() {
	g_fProximity = g_hCVProximity.FloatValue;
	g_fTeleSettleTime = g_hCVTeleSettleTime.FloatValue;
}

// Custom Callbacks

public Action Event_RoundStart(Event hEvent, const char[] sName, bool bDontBroadcast) {
	SetupTeleportHook();
}

public Action Hook_TeleportStartTouch(int iEntity, int iOther) {
	if (Client_IsValid(iOther)) {
		g_fLastTeleport[iOther] = GetGameTime();
	}

	return Plugin_Continue;
}

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

int Sort_Courses(int iIdx1, int iIdx2, Handle hArr, Handle hHandle) {
	Course iCourse1 = g_hCourses.Get(iIdx1);
	Course iCourse2 = g_hCourses.Get(iIdx2);

	int iCourseNumber1 = iCourse1.iNumber;
	int iCourseNumber2 = iCourse2.iNumber;
	if (iCourseNumber1 > 0) {
		if (iCourseNumber2 > 0) {
			return iCourseNumber1-iCourseNumber2;
		}

		return -1;
	} else {
		if (iCourseNumber2 > 0) {
			return 1;
		}

		// Negate bonus course number
		return iCourseNumber2-iCourseNumber1;
	}
}

// Natives

public int Native_IsLoaded(Handle hPlugin, int iArgC) {
	return g_bLoaded;
}

public int Native_GetDatabase(Handle hPlugin, int iArgC) {
	return view_as<int>(g_hDatabase);
}

public int Native_GetCourses(Handle hPlugin, int iArgC) {
	return view_as<int>(g_hCourses.Clone());
}

public int Native_GetMapID(Handle hPlugin, int iArgC) {
	return g_iMapID;
}

public int Native_GetPlayerNearestCheckpoint(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);

	Checkpoint eCheckpoint;
	eCheckpoint.iHash = g_eNearestCheckpoint[iClient].iHash;
	eCheckpoint.iTimestamp = g_eNearestCheckpoint[iClient].iTimestamp;

	if (eCheckpoint.iTimestamp) {
		SetNativeCellRef(2, eCheckpoint.GetCourseNumber());
		SetNativeCellRef(3, eCheckpoint.GetJumpNumber());
		SetNativeCellRef(4, eCheckpoint.IsControlPoint());

		return true;
	}

	SetNativeCellRef(2, 0);
	SetNativeCellRef(3, 0);
	SetNativeCellRef(4, false);
	
	return false;
}

public int Native_GetPlayerNewestCheckpoint(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);

	ArrayList hProgress = g_hProgress[iClient];
	if (hProgress == null) {
		return false;
	}

	TFTeam iTeam = view_as<TFTeam>(GetNativeCell(6));
	TFClassType iClass = TF2_GetPlayerClass(GetNativeCell(7));

	Checkpoint eCheckpoint;
	Checkpoint eCheckpointIter;

	for (int i=0; i<hProgress.Length; i++) {	
		hProgress.GetArray(i, eCheckpointIter, sizeof(Checkpoint));

		if ((iTeam != TFTeam_Unassigned && eCheckpoint.GetTeam() != iTeam) || (iClass != TFClass_Unknown && eCheckpoint.GetClass() != iClass)) {
			continue;
		}

		if (eCheckpoint.iTimestamp > eCheckpointIter.iTimestamp) {
			eCheckpoint = eCheckpointIter;
		}
	}

	if (eCheckpoint.iTimestamp) {
		SetNativeCellRef(2, eCheckpoint.GetCourseNumber());
		SetNativeCellRef(3, eCheckpoint.GetJumpNumber());
		SetNativeCellRef(4, eCheckpoint.IsControlPoint());
		SetNativeCellRef(5, eCheckpoint.iTimestamp);

		return true;
	}

	SetNativeCellRef(2, 0);
	SetNativeCellRef(3, 0);
	SetNativeCellRef(4, false);
	SetNativeCellRef(5, 0);

	return false;
}

public int Native_GetPlayerLastCheckpoint(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);

	Checkpoint eCheckpoint;
	eCheckpoint.iHash = g_eNearestCheckpointLanded[iClient].iHash;
	eCheckpoint.iTimestamp = g_eNearestCheckpointLanded[iClient].iTimestamp;

	if (eCheckpoint.iTimestamp) {
		SetNativeCellRef(2, eCheckpoint.GetCourseNumber());
		SetNativeCellRef(3, eCheckpoint.GetJumpNumber());
		SetNativeCellRef(4, eCheckpoint.IsControlPoint());
		SetNativeCellRef(5, eCheckpoint.iTimestamp);
		SetNativeCellRef(6, eCheckpoint.GetTeam());
		SetNativeCellRef(7, eCheckpoint.GetClass());

		return true;
	}

	SetNativeCellRef(2, 0);
	SetNativeCellRef(3, 0);
	SetNativeCellRef(4, false);
	SetNativeCellRef(5, 0);
	SetNativeCellRef(6, TFTeam_Unassigned);
	SetNativeCellRef(7, TFClass_Unknown);
	
	return false;
}

public int Native_GetPlayerProgress(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);

	ArrayList hProgress = g_hProgress[iClient];
	if (hProgress == null) {
		return 0; // null
	}

	TFTeam iTeam = view_as<TFTeam>(GetClientTeam(iClient));
	TFClassType iClass = TF2_GetPlayerClass(iClient);

	ArrayList hList = new ArrayList(sizeof(Checkpoint));

	Checkpoint eCheckpoint;

	for (int i=0; i<hProgress.Length; i++) {
		hProgress.GetArray(i, eCheckpoint, sizeof(Checkpoint));

		if (eCheckpoint.GetTeam() != iTeam || eCheckpoint.GetClass() != iClass) {
			continue;
		}

		hList.PushArray(eCheckpoint);
	}

	return view_as<int>(hList);
}

public int Native_ResetPlayerProgress(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);
	ResetClient(iClient);
}

public int Native_ResolveCourseNumber(Handle hPlugin, int iArgC) {
	int iCourseNumber = GetNativeCell(1);
	Course iCourse = NULL_COURSE;

	for (int i=0; i<g_hCourses.Length; i++) {
		Course iCourseIter = g_hCourses.Get(i);
		if (iCourseIter.iNumber == iCourseNumber) {
			iCourse = iCourseIter;
			break;
		}
	}

	return view_as<int>(iCourse);
}

public int Native_ResolveJumpNumber(Handle hPlugin, int iArgC) {
	Course iCourse = GetNativeCell(1);
	int iJumpNumber = GetNativeCell(2);

	ArrayList hJumps = iCourse.hJumps;

	if (!iCourse || iJumpNumber <= 0 || iJumpNumber > hJumps.Length) {
		return view_as<int>(NULL_JUMP);
	}

	return view_as<int>(hJumps.Get(iJumpNumber-1));
}

public int Native_GetCourseDisplayName(Handle hPlugin, int iArgC) {
	Course iCourse = GetNativeCell(1);
	int iMaxLength = GetNativeCell(3);

	int iCourseNumber = iCourse.iNumber;

	char sBuffer[128];
	iCourse.GetName(sBuffer, sizeof(sBuffer));

	bool bCanHide = false;
	if (sBuffer[0]) {
		if (iCourseNumber <= 0) {
			Format(sBuffer, sizeof(sBuffer), "%s (Bonus)", sBuffer);
		}
	} else {
		if (iCourseNumber > 0) {
			if (g_iNormalCourses > 1) {
				FormatEx(sBuffer, sizeof(sBuffer), "Course %d", iCourse.iNumber);
			} else {
				FormatEx(sBuffer, sizeof(sBuffer), "Course");
				bCanHide = true;
			}
		} else {
			if (g_iBonusCourses > 1) {
				FormatEx(sBuffer, sizeof(sBuffer), "Bonus %d", -iCourse.iNumber);
			} else {
				FormatEx(sBuffer, sizeof(sBuffer), "Bonus");
			}
		}
	}

	SetNativeString(2, sBuffer, iMaxLength);

	return bCanHide;
}

public int Native_GetCheckpointDisplayName(Handle hPlugin, int iArgC) {
	Course iCourse = GetNativeCell(1);
	int iJumpNumber = GetNativeCell(2);
	bool bControlPoint = GetNativeCell(3);
	int iMaxLength = GetNativeCell(5);

	bool bCanHide = false;

	char sBuffer[128];
	if (bControlPoint) {
		FormatEx(sBuffer, sizeof(sBuffer), "End");
	} else {
		if (iCourse.hJumps.Length > 1) {
			FormatEx(sBuffer, sizeof(sBuffer), "Jump %d", iJumpNumber);
		} else {
			FormatEx(sBuffer, sizeof(sBuffer), "Jump");
			bCanHide = true;
		}
	}

	SetNativeString(4, sBuffer, iMaxLength);

	return bCanHide;
}

public int Native_GetCourseCheckpointDisplayName(Handle hPlugin, int iArgC) {
	Course iCourse = GetNativeCell(1);
	int iJumpNumber = GetNativeCell(2);
	bool bControlPoint = GetNativeCell(3);
	int iMaxLength = GetNativeCell(5);

	char sBuffer[256];

	char sCourseName[128];
	bool bCanHideCourseName = GetCourseDisplayName(iCourse, sCourseName, sizeof(sCourseName));

	char sCheckpointName[128];
	bool bCanHideCheckpointName = GetCheckpointDisplayName(iCourse, iJumpNumber, bControlPoint, sCheckpointName, sizeof(sCheckpointName));

	if (bControlPoint) {
		FormatEx(sBuffer, sizeof(sBuffer), "%s %s", sCourseName, sCheckpointName);
	} else if (bCanHideCourseName) {
		if (bCanHideCheckpointName) {
			FormatEx(sBuffer, sizeof(sBuffer), "%s", sCourseName);
		} else {
			FormatEx(sBuffer, sizeof(sBuffer), "%s", sCheckpointName);
		}
	} else {
		if (bCanHideCheckpointName) {
			FormatEx(sBuffer, sizeof(sBuffer), "%s", sCourseName);
		} else {
			FormatEx(sBuffer, sizeof(sBuffer), "%s %s", sCourseName, sCheckpointName);
		}
	}

	SetNativeString(4, sBuffer, iMaxLength);
}

// Timers

public Action Timer_Refetch(Handle hTimer) {
	FetchMapData();
	
	return Plugin_Handled;
}

public Action Timer_TrackPlayers(Handle hTimer, any aData) {
	int iTime = GetTime();
	float fGameTime = GetGameTime();

	float fGroundPos[MAXPLAYERS+1][3];

	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && IsPlayerAlive(i)) {
			GetClientGroundPosition(i, fGroundPos[i]);
			g_eNearestCheckpoint[i].Clear();
		}
	}

	int iClients[MAXPLAYERS];
	float fMinDist[MAXPLAYERS + 1] =  { view_as<float>(0x7F800000), ... }; // +inf
	Course iActiveCourse[MAXPLAYERS + 1];

	float fOrigin[3];
	for (int i=0; i<g_hCourses.Length; i++) {
		Course iCourseIter = g_hCourses.Get(i);
		int iCourseNumber = iCourseIter.iNumber;

		ArrayList hJumps = iCourseIter.hJumps;
		for (int j=1; j<=hJumps.Length; j++) {
			Jump iJumpIter = hJumps.Get(j-1);
			iJumpIter.GetOrigin(fOrigin);

			int iClientsCount = GetClientsInRange(fOrigin, RangeType_Visibility, iClients, sizeof(iClients));
			for (int k = 0; k < iClientsCount; k++) {
				int iClient = iClients[k];
				if (IsPlayerAlive(iClient) && (fGameTime - g_fLastTeleport[iClient]) > g_fTeleSettleTime) {
					float fDist = GetVectorDistance(fGroundPos[iClient], fOrigin);
					if ((fDist < g_fProximity) && (fDist < fMinDist[iClient]) && IsVisible(fGroundPos[iClient], fOrigin)) {
						g_eNearestCheckpoint[iClient].Init(
							iCourseNumber,
							j,
							false,
							view_as<TFTeam>(GetClientTeam(iClient)),
							TF2_GetPlayerClass(iClient)
						);
						g_eNearestCheckpoint[iClient].iTimestamp = iTime;
						iActiveCourse[iClient] = iCourseIter;
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
				if (IsPlayerAlive(iClient) && (fGameTime - g_fLastTeleport[iClient]) > g_fTeleSettleTime) {
					float fDist = GetVectorDistance(fGroundPos[iClient], fOrigin);
					if ((fDist < g_fProximity) && (fDist < fMinDist[iClient]) && IsVisible(fGroundPos[iClient], fOrigin)) {
						g_eNearestCheckpoint[iClient].Init(
							iCourseNumber,
							0,
							true,
							view_as<TFTeam>(GetClientTeam(iClient)),
							TF2_GetPlayerClass(iClient)
						);
						g_eNearestCheckpoint[iClient].iTimestamp = iTime;
						iActiveCourse[iClient] = iCourseIter;
						fMinDist[iClient] = fDist;
					}
				}
			}
		}
	}

	Checkpoint eCheckpoint;
	eCheckpoint.iTimestamp = iTime;

	for (int i=1; i<=MaxClients; i++) {
		if (!IsClientInGame(i) || !IsPlayerAlive(i) ||
		 	!g_eNearestCheckpoint[i].iTimestamp || g_eNearestCheckpoint[i].iHash == g_eNearestCheckpointLanded[i].iHash) {
			continue;
		}

		eCheckpoint.iHash = g_eNearestCheckpoint[i].iHash;
		eCheckpoint.iTimestamp = g_eNearestCheckpoint[i].iTimestamp;

		TFTeam iTeam = view_as<TFTeam>(GetClientTeam(i));
		TFClassType iClass = TF2_GetPlayerClass(i);

		int iHash = eCheckpoint.iHash;
		int iCourseNumber = eCheckpoint.GetCourseNumber();
		int iJumpNumber = eCheckpoint.GetJumpNumber();
		bool bIsControlPoint = eCheckpoint.IsControlPoint();

		if (GetEntityFlags(i) & FL_ONGROUND) {
			Call_StartForward(g_hCheckpointReachedForward);
			Call_PushCell(i);
			Call_PushCell(iCourseNumber);
			Call_PushCell(iJumpNumber);
			Call_PushCell(bIsControlPoint);
			Call_Finish();

			g_eNearestCheckpointLanded[i].iHash = iHash;
			g_eNearestCheckpointLanded[i].iTimestamp = iTime;
		}

		if (g_hProgress[i].FindValue(iHash, Checkpoint::iHash) != -1) {
			continue;
		}

		ArrayList hJumps = iActiveCourse[i].hJumps;
		
		if (bIsControlPoint) {	
			for (int j=1; j<=hJumps.Length; j++) {
				eCheckpoint.Init(
					iCourseNumber,
					j,
					false,
					iTeam,
					iClass
				);

				if (g_hProgress[i].FindValue(eCheckpoint.iHash, Checkpoint::iHash) == -1) {
					g_hProgress[i].PushArray(eCheckpoint);

					//SortADTArray(g_hProgress[i], Sort_Ascending, Sort_Integer);

					Call_StartForward(g_hNewCheckpointReachedForward);
					Call_PushCell(i);
					Call_PushCell(iCourseNumber);
					Call_PushCell(j);
					Call_PushCell(false);
					Call_Finish();
				}
			}
		} else {
			for (int j=1; j<iJumpNumber && j<=hJumps.Length; j++) {
				eCheckpoint.Init(
					iCourseNumber,
					j,
					false,
					iTeam,
					iClass
				);

				if (g_hProgress[i].FindValue(eCheckpoint.iHash, Checkpoint::iHash) == -1) {
					g_hProgress[i].PushArray(eCheckpoint);

					//SortADTArray(g_hProgress[i], Sort_Ascending, Sort_Integer);

					Call_StartForward(g_hNewCheckpointReachedForward);
					Call_PushCell(i);
					Call_PushCell(iCourseNumber);
					Call_PushCell(j);
					Call_PushCell(false);
					Call_Finish();
				}
			}
		}

		if (GetEntityFlags(i) & FL_ONGROUND) {
			eCheckpoint.iHash = iHash;

			g_hProgress[i].PushArray(eCheckpoint);

			//SortADTArray(g_hProgress[i], Sort_Ascending, Sort_Integer);

			Call_StartForward(g_hNewCheckpointReachedForward);
			Call_PushCell(i);
			Call_PushCell(iCourseNumber);
			Call_PushCell(iJumpNumber);
			Call_PushCell(bIsControlPoint);
			Call_Finish();
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

void ResetClient(int iClient) {
	g_eNearestCheckpoint[iClient].Clear();
	g_eNearestCheckpointLanded[iClient].Clear();

	if (g_hProgress[iClient] != null) {
		g_hProgress[iClient].Clear();
	}

	g_fLastTeleport[iClient] = 0.0;
}

void GetClientGroundPosition(int iClient, float fPos[3]) {
	float fAngDown[3] = {90.0, 0.0, 0.0};
	GetClientEyePosition(iClient, fPos);

	Handle hTr = TR_TraceRayFilterEx(fPos, fAngDown, MASK_SHOT_HULL, RayType_Infinite, TraceFilter_Environment);
	if (TR_DidHit(hTr)) {
		TR_GetEndPosition(fPos, hTr);
		fPos[2] += 20.0; // Prevent clipping through ground
	}
	CloseHandle(hTr);
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

void SetupTeleportHook() {
	int iEntity = INVALID_ENT_REFERENCE;
	while ((iEntity = FindEntityByClassname(iEntity, "trigger_teleport")) != INVALID_ENT_REFERENCE) {
		SDKHook(iEntity, SDKHook_StartTouch, Hook_TeleportStartTouch);
	}
}

void SetupTimer() {
	if (g_hTimer == null) {
		g_hTimer = CreateTimer(g_hCVInterval.FloatValue, Timer_TrackPlayers, INVALID_HANDLE, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

void TF2_GetClassName(TFClassType iClass, char[] sName, iLength) {
  static char sClass[10][10] = {"unknown", "scout", "sniper", "soldier", "demoman", "medic", "heavy", "pyro", "spy", "engineer"};
  strcopy(sName, iLength, sClass[view_as<int>(iClass)]);
}

void TF2_GetTeamName(TFTeam iTeam, char[] sName, iLength) {
  static char sTeam[4][11] = {"unassigned", "spectator", "red", "blue"};
  strcopy(sName, iLength, sTeam[view_as<int>(iTeam)]);
}

// Commands

public Action cmdWhereAmI(int iClient, int iArgC) {
	if (!iClient) {
		ReplyToCommand(iClient, "[jse] You cannot run this command from server console.");
		return Plugin_Handled;
	}

	if (g_eNearestCheckpoint[iClient].iTimestamp) {
		Checkpoint eCheckpoint;
		eCheckpoint.iHash = g_eNearestCheckpoint[iClient].iHash;

		Course iCourse = ResolveCourseNumber(eCheckpoint.GetCourseNumber());

		char sLocationName[256];
		GetCourseCheckpointDisplayName(iCourse, eCheckpoint.GetJumpNumber(), eCheckpoint.IsControlPoint(), sLocationName, sizeof(sLocationName));

		CReplyToCommand(iClient, "{dodgerblue}[jse] {white}You are on {yellow}%s{white}.", sLocationName);
	} else {
		CReplyToCommand(iClient, "{dodgerblue}[jse] {white}You are not near any jump."); 
	}

	return Plugin_Handled;
}

public Action cmdWhereIs(int iClient, int iArgC) {
	if (!iArgC) {
		CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Usage: sm_whereis <target>");
		return Plugin_Handled;
	}

	char sArg1[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));

	char sTargetName[MAX_TARGET_LENGTH];
	int iTargetList[MAXPLAYERS], iTargetCount;
	bool bTnIsML;

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

	if (iTargetCount == 1) {
		int iTarget = iTargetList[0];

		if (g_eNearestCheckpoint[iTarget].iTimestamp) {
			Checkpoint eCheckpoint;
			eCheckpoint.iHash = g_eNearestCheckpoint[iTarget].iHash;

			Course iCourse = ResolveCourseNumber(eCheckpoint.GetCourseNumber());

			char sLocationName[128];
			GetCourseCheckpointDisplayName(iCourse, eCheckpoint.GetJumpNumber(), eCheckpoint.IsControlPoint(), sLocationName, sizeof(sLocationName));

			CReplyToCommand(iClient, "{dodgerblue}[jse] {limegreen}%N {white}is on {yellow}%s{white}.", iTarget, sLocationName);
		} else {
			CReplyToCommand(iClient, "{dodgerblue}[jse] {limegreen}%N {white}is not found near any jump.", iTarget);
		}

		return Plugin_Handled;
	}

	if (bTnIsML) {
		CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Showing locations for {limegreen}%t{white}:", sTargetName);
	} else {
		CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Showing locations for {limegreen}%s{white}:", sTargetName);
	}

	for (int i = 0; i < iTargetCount; i++) {
		int iTarget = iTargetList[i];
	
		if (GetClientTeam(iTarget) <= view_as<int>(TFTeam_Spectator)) {
			CReplyToCommand(iClient, "\t{limegreen}%N {white}has not joined a team.", iTarget);
		} else if (g_eNearestCheckpoint[iTarget].iTimestamp) {
			Checkpoint eCheckpoint;
			eCheckpoint.iHash = g_eNearestCheckpoint[iTarget].iHash;

			Course iCourse = ResolveCourseNumber(eCheckpoint.GetCourseNumber());

			char sLocationName[128];
			GetCourseCheckpointDisplayName(iCourse, eCheckpoint.GetJumpNumber(), eCheckpoint.IsControlPoint(), sLocationName, sizeof(sLocationName));

			CReplyToCommand(iClient, "\t{limegreen}%N {white}is on {yellow}%s{white}.", iTarget, sLocationName);
		} else {
			CReplyToCommand(iClient, "\t{limegreen}%N {white}is not found near any jump.", iTarget);
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

	ArrayList hCourseList = g_hCourses.Clone();
	SortADTArrayCustom(hCourseList, Sort_Courses);

	char sBuffer[256];
	for (int i = 0; i < iTargetCount; i++) {
		int iTarget = iTargetList[i];

		TFTeam iTeam = view_as<TFTeam>(GetClientTeam(iTarget));
		TFClassType iClass = TF2_GetPlayerClass(iTarget);

		if (iArgC) {
			char sTeamName[11];
			TF2_GetTeamName(iTeam, sTeamName, sizeof(sTeamName));

			char sClassName[10];
			TF2_GetClassName(iClass, sClassName, sizeof(sClassName));

			FormatEx(sBuffer, sizeof(sBuffer), "{white}- %N (%s, %s):\n", iTarget, sTeamName, sClassName);
		}

		ArrayList hProgress = g_hProgress[iTarget];

		Checkpoint eCheckpoint;

		int iLineCount = 1;
		int iJumpCountTotal = 0;
		for (int j=0; j<hCourseList.Length; j++) {
			Course iCourse = hCourseList.Get(j);
			int iCourseID = iCourse.iNumber;

			char sCourseName[128];
			GetCourseDisplayName(iCourse, sCourseName, sizeof(sCourseName));

			if (!sCourseName[0]) {
				FormatEx(sCourseName, sizeof(sCourseName), "Course");
			}
			
			int iJumpCount = 0;
			int iJumpsTotal = iCourse.hJumps.Length;

			for (int k=0; k<hProgress.Length; k++) {
				hProgress.GetArray(k, eCheckpoint, sizeof(Checkpoint));

				if (eCheckpoint.GetTeam() != iTeam || eCheckpoint.GetClass() != iClass) {
					continue;
				}

				if (iCourseID == eCheckpoint.GetCourseNumber()) {
					if (eCheckpoint.IsControlPoint()) {
						Format(sBuffer, sizeof(sBuffer), "%s\t{white}%20s\t{lightgray}%2d/%2d\t\t{lime}Completed\n", sBuffer, sCourseName, iJumpsTotal, iJumpsTotal);
						iJumpCount = 0;
						iLineCount++;
						break;
					} else {
						iJumpCount++;
						iJumpCountTotal++;
					}
				}
			}

			if (iJumpCount) {
				Format(sBuffer, sizeof(sBuffer), "%s\t{white}%20s\t{lightgray}%2d/%2d\n", sBuffer, sCourseName, iJumpCount, iJumpsTotal);
				iLineCount++;
			}

			if (iLineCount >= 3) {
				int iLength = strlen(sBuffer);
				sBuffer[iLength-1] = '\0'; // Remove newline
				
				CReplyToCommand(iClient, sBuffer);

				sBuffer[0] = '\0';
				iLineCount = 0;
			}
		}

		if (!iJumpCountTotal) {
			Format(sBuffer, sizeof(sBuffer), "%s\t{lightgray}No progress recorded.\n", sBuffer);
			iLineCount++;
		}

		if (sBuffer[0]) {
			CReplyToCommand(iClient, sBuffer);
		}
	}

	delete hCourseList;

	return Plugin_Handled;
}
