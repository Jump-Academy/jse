#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.1"

#include <sourcemod>
#include <clientprefs>
#include <smlib/clients>
#include <tf2>
#include <multicolors>

#undef REQUIRE_PLUGIN
#include <jse_tracker>

GlobalForward g_hAutosavePreLoadForward;
GlobalForward g_hAutosaveLoadForward;

ConVar g_hCVBackupInterval;
ConVar g_hCVSpawnPopup;

Cookie g_hCookieRespawnPopup;

ArrayList g_hAutosave[MAXPLAYERS+1][2][9];
Checkpoint g_eCheckpointSelected[MAXPLAYERS+1];

Handle g_hBackupTimer;
int g_iLastBackupTime;

#include "jse_autosave_database.sp"

public Plugin myinfo = {
	name = "Jump Server Essentials - Autosave",
	author = PLUGIN_AUTHOR,
	description = "JSE course progression autosave module",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	CreateConVar("jse_autosave_version", PLUGIN_VERSION, "Jump Server Essentials snapshot version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_hCVBackupInterval = CreateConVar("jse_autosave_backup_interval", "300.0", "Time in seconds between database backups", FCVAR_NOTIFY, true, 0.0);
	g_hCVSpawnPopup = CreateConVar("jse_autosave_spawnpopup", "5", "Time in seconds to show autosave panel after player spawn (0 to disable)", FCVAR_NOTIFY, true, 0.0);

	RegConsoleCmd("sm_as", cmdAutosave, "List autosaves");
	RegConsoleCmd("sm_autosave", cmdAutosave, "List autosaves");

	g_hCookieRespawnPopup = new Cookie("jse_autosave_spawnpopup", "Set automatic autosave popup on spawn", CookieAccess_Private);
	SetCookiePrefabMenu(g_hCookieRespawnPopup, CookieMenu_OnOff_Int, "Autosave Menu on Spawn");

	HookEvent("player_spawn", Event_PlayerSpawn);

	g_hAutosavePreLoadForward = new GlobalForward("OnAutosavePreLoad", ET_Hook, Param_Cell);
	g_hAutosaveLoadForward = new GlobalForward("OnAutosaveLoad", ET_Hook, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	DB_CreateTables(GetTrackerDatabase());

	AutoExecConfig(true, "jse_autosave");
}

public void OnPluginEnd() {
	DB_BackupAutosaves();
}

public void OnMapStart() {
	if (Client_GetCount(true, false)) {
		SetupTimer();
	}
}

public void OnMapEnd() {
	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i)) {
			DB_BackupAutosaves(i);
			ResetClient(i);
		}
	}

	g_iLastBackupTime = GetTime();

	delete g_hBackupTimer;
}

public void OnClientPostAdminCheck(int iClient) {
	if (!IsFakeClient(iClient)) {
		DB_LoadAutosaves(iClient);

		SetupTimer();
	}
}

public void OnClientDisconnect(int iClient) {
	if (!IsFakeClient(iClient)) {
		DB_BackupAutosaves(iClient);
		ResetClient(iClient);
	}

	if (!Client_GetCount(true, false)) {
		delete g_hBackupTimer;
	}
}

// Custom callbacks

public void OnTrackerDatabaseConnected(Database hDatabase) {
	DB_CreateTables(hDatabase);
}

public void OnCheckpointReached(int iClient, int iCourseNumber, int iJumpNumber, bool bControlPoint) {
	if (IsFakeClient(iClient) || !IsPlayerAlive(iClient)) {
		return;
	}

	TFTeam iTeam = TF2_GetClientTeam(iClient);
	TFClassType iClass = TF2_GetPlayerClass(iClient);

	if (iTeam <= TFTeam_Spectator || iClass == TFClass_Unknown) {
		return;
	}

	ArrayList hCheckpoint = g_hAutosave[iClient][view_as<int>(iTeam)-view_as<int>(TFTeam_Red)][view_as<int>(iClass)-1];
	if (!hCheckpoint) {
		hCheckpoint = new ArrayList(sizeof(Checkpoint));
		g_hAutosave[iClient][view_as<int>(iTeam)-view_as<int>(TFTeam_Red)][view_as<int>(iClass)-1] = hCheckpoint;
	}

	Checkpoint eCheckpoint;
	for (int i=0; i<hCheckpoint.Length; i++) {
		hCheckpoint.GetArray(i, eCheckpoint);

		if (eCheckpoint.GetCourseNumber() == iCourseNumber) {
			if (bControlPoint) {
				eCheckpoint.SetControlPoint();
			} else {
				eCheckpoint.SetJumpNumber(iJumpNumber);
			}

			eCheckpoint.iTimestamp = GetTime();

			hCheckpoint.SetArray(i, eCheckpoint);
			return;
		}
	}

	eCheckpoint.Init(iCourseNumber, iJumpNumber, bControlPoint, iTeam, iClass);
	eCheckpoint.iTimestamp = GetTime();

	hCheckpoint.PushArray(eCheckpoint);
}

public Action Event_PlayerSpawn(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));

	if (IsFakeClient(iClient) || !g_hCVSpawnPopup.IntValue) {
		return Plugin_Continue;
	}

	TFTeam iTeam = TF2_GetClientTeam(iClient);
	TFClassType iClass = TF2_GetPlayerClass(iClient);

	if (iTeam > TFTeam_Spectator && iClass > TFClass_Unknown && CheckRespawnPopup(iClient)) {
		Call_StartForward(g_hAutosavePreLoadForward);
		Call_PushCell(iClient);

		any aResult;
		if (Call_Finish(aResult) == SP_ERROR_NONE && aResult != Plugin_Continue) {
			return Plugin_Continue;
		}

		SendLastSavePanel(iClient);
	}

	return Plugin_Continue;
}

public Action Timer_Backup(Handle hTimer, any aData) {
	DB_BackupAutosaves();

	return Plugin_Continue;
}

// Helpers

void ResetClient(int iClient) {
	for (int i=0; i<sizeof(g_hAutosave[][]); i++) {
		delete g_hAutosave[iClient][0][i];
		delete g_hAutosave[iClient][1][i];
	}
}

void SetupTimer() {
	if (g_hBackupTimer == null) {
		g_hBackupTimer = CreateTimer(g_hCVBackupInterval.FloatValue, Timer_Backup, 0, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

bool CheckRespawnPopup(int iClient) {
	char sBuffer[8];
	g_hCookieRespawnPopup.Get(iClient, sBuffer, sizeof(sBuffer));

	return !sBuffer[0] || StringToInt(sBuffer) != 0;
}

void DrawCheckpointInfo(Panel hPanel, int iCourseNumber, int iJumpNumber, bool bControlPoint, int iTimestamp) {
	Course iCourse = ResolveCourseNumber(iCourseNumber);
	Jump iJump = ResolveJumpNumber(iCourse, iJumpNumber);

	char sBuffer[1024];

	if (!GetCourseDisplayName(iCourse, sBuffer, sizeof(sBuffer))) {
		Format(sBuffer, sizeof(sBuffer), "Course: %s%s", sBuffer, bControlPoint ? " (END)" : NULL_STRING);
		hPanel.DrawText(sBuffer);
	}

	if (iJump) {
		Format(sBuffer, sizeof(sBuffer), "Jump:   %2d/%2d", iJump.iNumber, iCourse.hJumps.Length);
		hPanel.DrawText(sBuffer);
	}

	hPanel.DrawText(" ");

	int iTimeDiff = GetTime() - iTimestamp;

	if (iTimeDiff < 86400) {
		FormatTime(sBuffer, sizeof(sBuffer), "%r", iTimestamp);
		Format(sBuffer, sizeof(sBuffer), "Today, %s", sBuffer);
	} else if (iTimeDiff < 2*86400) {
		FormatTime(sBuffer, sizeof(sBuffer), "%r", iTimestamp);
		Format(sBuffer, sizeof(sBuffer), "Yesterday, %s", sBuffer);
	} else {
		FormatTime(sBuffer, sizeof(sBuffer), "%A, %b %d, %Y", iTimestamp);
		Format(sBuffer, sizeof(sBuffer), "%s", sBuffer);
	}

	hPanel.DrawText(sBuffer);
}

void SendToCheckpoint(int iClient) {
	TFTeam iTeam = TF2_GetClientTeam(iClient);
	TFClassType iClass = TF2_GetPlayerClass(iClient);

	if (iTeam <= TFTeam_Spectator || iClass == TFClass_Unknown) {
		return;
	}

	Checkpoint eCheckpoint;
	eCheckpoint = g_eCheckpointSelected[iClient];

	if (eCheckpoint.GetTeam() != iTeam || eCheckpoint.GetClass() != iClass) {
		return;
	}

	int iCourseNumber = eCheckpoint.GetCourseNumber();
	int iJumpNumber = eCheckpoint.GetJumpNumber();
	bool bControlPoint = eCheckpoint.IsControlPoint();

	Course iCourse = ResolveCourseNumber(iCourseNumber);
	Jump iJump = ResolveJumpNumber(iCourse, iJumpNumber);
	ControlPoint iControlPoint = iCourse.iControlPoint;

	Call_StartForward(g_hAutosaveLoadForward);
	Call_PushCell(iClient);
	Call_PushCell(iTeam);
	Call_PushCell(iClass);
	Call_PushCell(iCourseNumber);
	Call_PushCell(iJumpNumber);
	Call_PushCell(bControlPoint);

	any aResult;
	if (Call_Finish(aResult) == SP_ERROR_NONE && (aResult == Plugin_Handled || aResult == Plugin_Stop)) {
		return;
	}

	float fPos[3], fAng[3], fVel[3];
	char sIdentifier[128];
	if (iJump) {
		iJump.GetIdentifier(sIdentifier, sizeof(sIdentifier));
		if (sIdentifier[0]) {
			int iEntity = Entity_FindByName(sIdentifier, "info_*");
			if (iEntity != INVALID_ENT_REFERENCE) {
				Entity_GetAbsOrigin(iEntity, fPos);
				fPos[2] += 10.0; // In case buried in ground

				Entity_GetAbsAngles(iEntity, fAng);
			}
		} else {
			iJump.GetOrigin(fPos);
		}
	} else {
		iControlPoint.GetIdentifier(sIdentifier, sizeof(sIdentifier));
		if (sIdentifier[0]) {
			int iEntity = Entity_FindByName(sIdentifier, "team_control_point");
			if (iEntity != INVALID_ENT_REFERENCE) {
				Entity_GetAbsOrigin(iEntity, fPos);
				fPos[2] += 10.0; // In case buried in ground

				Entity_GetAbsAngles(iEntity, fAng);
			}
		} else {
			iControlPoint.GetOrigin(fPos);
		}
	}

	TeleportEntity(iClient, fPos, fAng, fVel);
}

void DeleteCheckpoint(int iClient) {
	TFTeam iTeam = TF2_GetClientTeam(iClient);
	TFClassType iClass = TF2_GetPlayerClass(iClient);

	if (iTeam <= TFTeam_Spectator || iClass == TFClass_Unknown) {
		return;
	}

	ArrayList hCheckpoint = g_hAutosave[iClient][view_as<int>(iTeam)-view_as<int>(TFTeam_Red)][view_as<int>(iClass)-1];
	if (!hCheckpoint || !hCheckpoint.Length) {
		return;
	}

	Checkpoint eCheckpoint;
	eCheckpoint = g_eCheckpointSelected[iClient];

	if (eCheckpoint.GetTeam() != iTeam || eCheckpoint.GetClass() != iClass) {
		return;
	}

	for (int i=0; i<hCheckpoint.Length; i++) {
		if (eCheckpoint.iHash == hCheckpoint.Get(i, Checkpoint::iHash)) {
			hCheckpoint.Erase(i);
			CPrintToChat(iClient, "{dodgerblue}[jse] {white}Autosave has been deleted.");

			DB_DeleteAutosave(iClient, eCheckpoint.GetCourseNumber(), eCheckpoint.GetJumpNumber(), eCheckpoint.IsControlPoint(), iTeam, iClass);
			break;
		}
	}
}

// Commands

public Action cmdAutosave(int iClient, int iArgC) {
	if (iClient) {
		SendCourseListPanel(iClient);
	}

	return Plugin_Handled;
}

// Menus

void SendLastSavePanel(int iClient) {
	TFTeam iTeam = TF2_GetClientTeam(iClient);
	TFClassType iClass = TF2_GetPlayerClass(iClient);

	if (iTeam <= TFTeam_Spectator || iClass == TFClass_Unknown) {
		return;
	}

	ArrayList hCheckpoint = g_hAutosave[iClient][view_as<int>(iTeam)-view_as<int>(TFTeam_Red)][view_as<int>(iClass)-1];
	if (!hCheckpoint || !hCheckpoint.Length) {
		return;
	}

	int iLatestIdx = 0;
	int iLastTimestamp = hCheckpoint.Get(0, Checkpoint::iTimestamp);

	for (int i=1; i<hCheckpoint.Length; i++) {
		int iTimestamp = hCheckpoint.Get(i, Checkpoint::iTimestamp);
		if (iTimestamp > iLastTimestamp) {
			iLatestIdx = i;
			iLastTimestamp = iTimestamp;
		}
	}

	Checkpoint eCheckpoint;
	hCheckpoint.GetArray(iLatestIdx, eCheckpoint);

	g_eCheckpointSelected[iClient] = eCheckpoint;

	Panel hPanel = new Panel();
	hPanel.SetTitle("Teleport to autosave?");

	hPanel.DrawText(" ");

	DrawCheckpointInfo(hPanel, eCheckpoint.GetCourseNumber(), eCheckpoint.GetJumpNumber(), eCheckpoint.IsControlPoint(), eCheckpoint.iTimestamp);

	hPanel.DrawText(" ");

	hPanel.DrawItem("Yes");
	hPanel.DrawItem("No");

	if (hCheckpoint.Length > 1) {
		char sBuffer[32];
		FormatEx(sBuffer, sizeof(sBuffer), "More (%d)", hCheckpoint.Length);
		hPanel.DrawItem(sBuffer);
	}

	hPanel.Send(iClient, MenuHandler_Confirmation, g_hCVSpawnPopup.IntValue);
}

void SendCourseListPanel(int iClient) {
	TFTeam iTeam = TF2_GetClientTeam(iClient);
	TFClassType iClass = TF2_GetPlayerClass(iClient);

	if (iTeam <= TFTeam_Spectator || iClass == TFClass_Unknown) {
		return;
	}

	ArrayList hCheckpoint = g_hAutosave[iClient][view_as<int>(iTeam)-view_as<int>(TFTeam_Red)][view_as<int>(iClass)-1];
	if (!hCheckpoint || !hCheckpoint.Length) {
		CReplyToCommand(iClient, "{dodgerblue}[jse] {white}No autosaves were found for this class.");
		return;
	}

	if (hCheckpoint.Length == 1) {
		hCheckpoint.GetArray(0, g_eCheckpointSelected[iClient]);
		SendConfirmationPanel(iClient, hCheckpoint, 0);
		return;
	}

	SortADTArray(hCheckpoint, Sort_Ascending, Sort_Integer);

	int iLatestIdx = 0;
	int iLastTimestamp = hCheckpoint.Get(0, Checkpoint::iTimestamp);

	for (int i=1; i<hCheckpoint.Length; i++) {
		int iTimestamp = hCheckpoint.Get(i, Checkpoint::iTimestamp);
		if (iTimestamp > iLastTimestamp) {
			iLatestIdx = i;
			iLastTimestamp = iTimestamp;
		}
	}

	Menu hMenu = new Menu(MenuHandler_CourseList);
	hMenu.SetTitle("Autosaved Courses");

	char sBuffer[1024];

	Checkpoint eCheckpoint;

	for (int i=0; i<hCheckpoint.Length; i++) {
		hCheckpoint.GetArray(i, eCheckpoint);

		Course iCourse = ResolveCourseNumber(eCheckpoint.GetCourseNumber());
		Jump iJump = ResolveJumpNumber(iCourse, eCheckpoint.GetJumpNumber());

		GetCourseDisplayName(iCourse, sBuffer, sizeof(sBuffer));

		char sMark[3];
		if (i == iLatestIdx) {
			sMark = " *";
		}

		if (iJump) {
			Format(sBuffer, sizeof(sBuffer), "(%2d/%2d)  %s%s", iJump.iNumber, iCourse.hJumps.Length, sBuffer, sMark);
		} else {
			Format(sBuffer, sizeof(sBuffer), "(END)  %s%s", sBuffer, sMark);
		}

		char sKey[8];
		IntToString(i, sKey, sizeof(sKey));
		hMenu.AddItem(sKey, sBuffer);
	}

	hMenu.Display(iClient, 0);
}

void SendConfirmationPanel(int iClient, ArrayList hCheckpoint, int iIndex) {
	TFTeam iTeam = TF2_GetClientTeam(iClient);
	TFClassType iClass = TF2_GetPlayerClass(iClient);

	Checkpoint eCheckpoint;
	hCheckpoint.GetArray(iIndex, eCheckpoint);

	if (iTeam != eCheckpoint.GetTeam() || iClass != eCheckpoint.GetClass()) {
		return;
	}

	Panel hPanel = new Panel();
	hPanel.SetTitle("Teleport to autosave?");

	hPanel.DrawText(" ");

	DrawCheckpointInfo(hPanel, eCheckpoint.GetCourseNumber(), eCheckpoint.GetJumpNumber(), eCheckpoint.IsControlPoint(), eCheckpoint.iTimestamp);

	hPanel.DrawText(" ");

	hPanel.DrawItem("Yes");
	hPanel.DrawItem("No");

	hPanel.DrawText(" ");

	hPanel.CurrentKey = 4;
	hPanel.DrawItem("Delete");

	if (hCheckpoint.Length > 1) {
		hPanel.DrawText(" ");
		hPanel.CurrentKey = 8;
		hPanel.DrawItem("Back");
	}

	hPanel.Send(iClient, MenuHandler_Confirmation, 0);
}

// Menu handlers

public int MenuHandler_CourseList(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			TFTeam iTeam = TF2_GetClientTeam(iClient);
			TFClassType iClass = TF2_GetPlayerClass(iClient);

			if (iTeam <= TFTeam_Spectator || iClass == TFClass_Unknown) {
				return;
			}

			ArrayList hCheckpoint = g_hAutosave[iClient][view_as<int>(iTeam)-view_as<int>(TFTeam_Red)][view_as<int>(iClass)-1];
			if (!hCheckpoint || !hCheckpoint.Length) {
				return;
			}

			char sKey[8];
			hMenu.GetItem(iOption, sKey, sizeof(sKey));

			int iIndex = StringToInt(sKey);
			if (iIndex < 0 || hCheckpoint > hCheckpoint) {
				return;
			}

			hCheckpoint.GetArray(iIndex, g_eCheckpointSelected[iClient]);

			SendConfirmationPanel(iClient, hCheckpoint, iIndex);
		}
		case MenuAction_End: {
			delete hMenu;
		}
	}
}

public int MenuHandler_Confirmation(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			switch (iOption) {
				case 1: {
					SendToCheckpoint(iClient);
				}
				case 4: {
					DeleteCheckpoint(iClient);
				}
				case 3, 8: {
					SendCourseListPanel(iClient);
				}
			}
		}
		case MenuAction_End: {
			delete hMenu;
		}
	}
}
