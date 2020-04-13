#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR	"AI"
#define PLUGIN_VERSION	"0.3.0"

#include <tf2>
#include <tf2_stocks>

#include <jse_tracker>
#include <smlib/clients>
#include <multicolors>

#define JUMPS_OVERRIDE 			"jse_teleport_jumps"
#define PLAYERS_OVERRIDE 		"jse_teleport_players"
#define MULTITARGET_OVERRIDE	"jse_teleport_multitarget"

ConVar g_hCVGotoProgressed;
ConVar g_hCVGotoPlayerProgressed;

public Plugin myinfo = {
	name = "Jump Server Essentials - Teleport",
	author = PLUGIN_AUTHOR,
	description = "JSE player teleport component",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	CreateConVar("jse_teleport_version", PLUGIN_VERSION, "Jump Server Essentials teleport version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_hCVGotoProgressed = CreateConVar("jse_teleport_goto_progressed", "1", "Allow goto teleport to jumps reached by player", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCVGotoPlayerProgressed = CreateConVar("jse_teleport_goto_player_progressed", "1", "Allow goto teleport to players on jumps reached by player", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	RegConsoleCmd("sm_goto", cmdGoto, "Teleport self");

	RegAdminCmd("sm_bring", cmdBring, ADMFLAG_GENERIC, "Teleport player to aim");
	RegAdminCmd("sm_send", cmdSend, ADMFLAG_GENERIC, "Teleport player");

	LoadTranslations("core.phrases");
	LoadTranslations("common.phrases");
}

// Custom callbacks

public bool TraceFilter_Environment(int iEntity, int iMask) {
	return false;
}

// Helpers

void GetAimPos(int iClient, float fAimPos[3]) {
	float fPos[3], fAng[3];
	GetClientEyePosition(iClient, fPos);
	GetClientEyeAngles(iClient, fAng);

	Handle hTr = TR_TraceRayFilterEx(fPos, fAng, MASK_SHOT_HULL, RayType_Infinite, TraceFilter_Environment);
	if (TR_DidHit(hTr)) {
		TR_GetEndPosition(fAimPos, hTr);	
	}
	delete hTr;
}

void AdjustHullPos(int iTarget, float fSrcPos[3], float fAimPos[3]) {
	float fMin[3], fMax[3];
	Entity_GetMinSize(iTarget, fMin);
	Entity_GetMaxSize(iTarget, fMax);
	Handle hTr = TR_TraceHullFilterEx(fSrcPos, fAimPos, fMin, fMax, MASK_SHOT_HULL, TraceFilter_Environment);
	if (TR_DidHit(hTr)) {
		TR_GetEndPosition(fAimPos, hTr);
	}
	delete hTr;
}

void BringPlayer(int iClient, int iTarget, float fPos[3], bool bNotify=true) {
	if (!IsClientInGame(iTarget)) {
		return;
	}

	TeleportEntity(iTarget, fPos, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));

	if (bNotify) {
		CPrintToChat(iTarget, "{dodgerblue}[jse] {white}You have been teleported to %N.", iClient);
	}
}

void GotoPlayer(int iClient, int iTarget, bool bNotify=true) {
	if (!IsClientInGame(iTarget)) {
		return;
	}

	float fOrigin[3], fAngles[3];
	GetClientAbsOrigin(iTarget, fOrigin);
	GetClientEyeAngles(iClient, fAngles);
	fAngles[1] = 0.0;
	fAngles[2] = 0.0;

	TeleportEntity(iClient, fOrigin, fAngles, view_as<float>({0.0, 0.0, 0.0}));

	if (bNotify) {
		CPrintToChat(iClient, "{dodgerblue}[jse] {white}You have been teleported to {limegreen}%N.", iTarget);
		CPrintToChat(iTarget, "{dodgerblue}[jse] {limegreen}%N {white}has teleported to you.", iClient);
	}
}

void GotoJump(int iClient, Course iCourse, int iJumpNumber, bool bNotify=true) {
	Jump iJump = ResolveJumpNumber(iCourse, iJumpNumber);

	float fOrigin[3];
	iJump.GetOrigin(fOrigin);
	fOrigin[2] += 10.0;

	TeleportEntity(iClient, fOrigin, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));

	char sBuffer[128];
	GetCourseName(iCourse, sBuffer, sizeof(sBuffer));

	if (bNotify) {
		if (iCourse.hJumps.Length > 1) {
			CPrintToChat(iClient, "{dodgerblue}[jse] {white}You have been teleported to {limegreen}%s, Jump %d.", sBuffer, iJump.iNumber);
		} else {
			CPrintToChat(iClient, "{dodgerblue}[jse] {white}You have been teleported to {limegreen}%s.", sBuffer);
		}
	}
}

void GotoControlPoint(int iClient, Course iCourse, bool bNotify=true) {
	float fOrigin[3];
	iCourse.iControlPoint.GetOrigin(fOrigin);
	fOrigin[2] += 10.0;

	TeleportEntity(iClient, fOrigin, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));

	char sBuffer[128];
	GetCourseName(iCourse, sBuffer, sizeof(sBuffer));

	if (bNotify) {
		CPrintToChat(iClient, "{dodgerblue}[jse] {white}You have been teleported to the end of {limegreen}%s.", sBuffer);
	}
}

void GetCourseName(Course iCourse, char[] sBuffer, int iLength) {
	iCourse.GetName(sBuffer, iLength);
	int iCourseNumber = iCourse.iNumber;

	if (sBuffer[0]) {
		if (iCourseNumber < 0) {
			Format(sBuffer, iLength, "Bonus %d (%s)", -iCourseNumber, sBuffer);
		}
	} else {
		if (iCourseNumber < 0) {
			FormatEx(sBuffer, iLength, "Bonus %d", -iCourseNumber);
		} else {
			FormatEx(sBuffer, iLength, "Course %d", iCourseNumber);
		}
	}
}

void GetCourseLocationString(char[] sBuffer, int iLength, Course iCourse, int iJumpNumber, bool bControlPoint) {
	char sCourseName[128];
	iCourse.GetName(sCourseName, sizeof(sCourseName));

	if (!sCourseName[0]) {
		FormatEx(sCourseName, sizeof(sCourseName), "Course %d", iCourse.iNumber);
	}

	char sLocationName[128];
	FormatEx(sLocationName, sizeof(sLocationName), bControlPoint ? "control point" : "jump %d", iJumpNumber);

	Format(sBuffer, iLength, "%s %s", sCourseName, sLocationName);
}

bool CheckProgress(int iClient, int iCourseNumber, int iJumpNumber, bool bControlPoint=false) {
	if (!iJumpNumber && !bControlPoint) {
		return false;
	}

	TFTeam iTeam = view_as<TFTeam>(GetClientTeam(iClient));
	TFClassType iClass = TF2_GetPlayerClass(iClient);

	ArrayList hProgress = GetPlayerProgress(iClient);

	bool bFound = false;
	for (int i=0; i<hProgress.Length && !bFound; i++) {
		Checkpoint eCheckpoint;
		hProgress.GetArray(i, eCheckpoint, sizeof(Checkpoint));

		bFound = eCheckpoint.GetTeam() == iTeam && 
			eCheckpoint.GetClass() == iClass &&
			eCheckpoint.GetCourseNumber() == iCourseNumber &&
			(bControlPoint && eCheckpoint.IsControlPoint() ||
			 eCheckpoint.GetJumpNumber() == iJumpNumber);
	}

	delete hProgress;

	return bFound;
}

bool CheckSafeTeleportTarget(int iClient, int iTarget, bool bNotify=true) {
	if (!(IsClientInGame(iTarget) && IsPlayerAlive(iTarget))) {
		if (bNotify) {
			CPrintToChat(iClient, "{dodgerblue}[jse] {white}%t", "Target must be alive");
		}

		return false;
	}

	if (CheckCommandAccess(iClient, "sm_bring", ADMFLAG_GENERIC, true)) {
		return true;
	}

	if (GetClientTeam(iTarget) != GetClientTeam(iClient)) {
		if (bNotify) {
			CPrintToChat(iClient, "{dodgerblue}[jse] {white}Player team does not match.");
		}

		return false;
	}

	if (!CheckCommandAccess(iClient, PLAYERS_OVERRIDE, ADMFLAG_GENERIC) && TF2_GetPlayerClass(iTarget) != TF2_GetPlayerClass(iClient)) {
		if (bNotify) {
			CPrintToChat(iClient, "{dodgerblue}[jse] {white}Player class does not match.");
		}
		
		return false;
	}

	return true;
}

// Commands

public Action cmdBring(int iClient, int iArgC) {
	if (!iClient) {
		ReplyToCommand(iClient, "[jse] You cannot run this command from server console.");
		return Plugin_Handled;
	}

	if (iArgC == 0) {
		PrintToConsole(iClient, "[jse] Usage: sm_bring [target]");
		SendPlayerMenu(iClient, MenuHandler_BringPlayer, false);
		return Plugin_Handled;
	}

	char sArg1[MAX_NAME_LENGTH];
	GetCmdArg(1, sArg1, sizeof(sArg1));

	char sTargetName[MAX_TARGET_LENGTH];
	int iTargetList[MAXPLAYERS], iTargetCount;
	bool bTnIsML;
 
	if ((iTargetCount = ProcessTargetString(
			sArg1,
			iClient,
			iTargetList,
			MAXPLAYERS,
			COMMAND_FILTER_ALIVE,
			sTargetName,
			sizeof(sTargetName),
			bTnIsML)) <= 0) {
		ReplyToTargetError(iClient, iTargetCount);
		return Plugin_Handled;
	}

	if (iTargetCount > 1 && !CheckCommandAccess(iClient, MULTITARGET_OVERRIDE, ADMFLAG_GENERIC)) {
		ReplyToCommand(iClient, "{dodgerblue}[jse] {white}You do not have permission to multi-target.");
		return Plugin_Handled;
	}

	float fPos[3];
	GetClientEyePosition(iClient, fPos);

	float fAimPos[3];
	GetAimPos(iClient, fAimPos);

	for (int i = 0; i < iTargetCount; i++) {
		AdjustHullPos(iTargetList[i], fPos, fAimPos);
		BringPlayer(iClient, iTargetList[i], fAimPos, iTargetList[i] != iClient);
	}

	if (bTnIsML) {
		CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Teleported %t to aim.", sTargetName);
	} else {
		CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Teleported %s to aim.", sTargetName);
	}

	return Plugin_Handled;
}

public Action cmdGoto(int iClient, int iArgC) {
	if (!iClient) {
		ReplyToCommand(iClient, "[jse] You cannot run this command from server console.");
		return Plugin_Handled;
	}

	bool bCanTeleToPlayers = CheckCommandAccess(iClient, PLAYERS_OVERRIDE, ADMFLAG_GENERIC);
	bool bCanTeleToAllJumps = CheckCommandAccess(iClient, JUMPS_OVERRIDE, ADMFLAG_GENERIC);

	switch (iArgC) {
		case 1: {
			char sArg1[MAX_NAME_LENGTH];
			GetCmdArg(1, sArg1, sizeof(sArg1));

			int iTarget = FindTarget(iClient, sArg1, false, false);
			if (iTarget != -1) {
				if (!CheckSafeTeleportTarget(iClient, iTarget)) {
					return Plugin_Handled;		
				}

				if (!g_hCVGotoPlayerProgressed.BoolValue && !bCanTeleToPlayers) {
					CReplyToCommand(iClient, "{dodgerblue}[jse] {white}%t", "No Access");
					return Plugin_Handled;
				}

				if (bCanTeleToPlayers) {
					GotoPlayer(iClient, iTarget);
				} else {
					int iCourseNumber;
					int iJumpNumber;
					bool bControlPoint;

					if (GetPlayerNearestCheckpoint(iTarget, iCourseNumber, iJumpNumber, bControlPoint)) {
						Course iCourse = ResolveCourseNumber(iCourseNumber);

						if (CheckProgress(iClient, iCourseNumber, iJumpNumber, bControlPoint)) {
							if (bControlPoint) {
								GotoControlPoint(iClient, iCourse);
							} else {
								GotoJump(iClient, iCourse, iJumpNumber);
							}
						} else {
							char sBuffer[256];
							GetCourseLocationString(sBuffer, sizeof(sBuffer), iCourse, iJumpNumber, bControlPoint);

							CPrintToChat(iClient, "{dodgerblue}[jse] {white}You have not been to %N's location before: %s", iTarget, sBuffer);
						}
					} else {
						CPrintToChat(iClient, "{dodgerblue}[jse] {white}%N is not found near any jump.", iTarget);
					}
				}
			}
		}
		case 2: {
			if (!g_hCVGotoProgressed.BoolValue && !bCanTeleToAllJumps) {
				CReplyToCommand(iClient, "{dodgerblue}[jse] {white}%t", "No Access");
				return Plugin_Handled;
			}

			char sArg1[8], sArg2[8];
			GetCmdArg(1, sArg1, sizeof(sArg1));
			GetCmdArg(2, sArg2, sizeof(sArg2));

			int iCourseNumber = StringToInt(sArg1);
			int iJumpNumber = StringToInt(sArg2);

			Course iCourse = ResolveCourseNumber(iCourseNumber);
			if (iCourse) {
				if (iJumpNumber == 0) {
					if (!bCanTeleToAllJumps && !CheckProgress(iClient, iCourseNumber, 0, true)) {
						char sBuffer[256];
						GetCourseName(iCourse, sBuffer, sizeof(sBuffer));

						CReplyToCommand(iClient, "{dodgerblue}[jse] {white}You have not yet finished %s.", sBuffer);
						return Plugin_Handled;
					}

					GotoControlPoint(iClient, iCourse);
				} else {
					Jump iJump = ResolveJumpNumber(iCourse, iJumpNumber);
					if (iJump) {
						if (!bCanTeleToAllJumps && !CheckProgress(iClient, iCourseNumber, iJumpNumber)) {
							char sBuffer[256];
							GetCourseLocationString(sBuffer, sizeof(sBuffer), iCourse, iJumpNumber, false);

							CReplyToCommand(iClient, "{dodgerblue}[jse] {white}You have not yet reached %s.", sBuffer);
							return Plugin_Handled;
						}

						GotoJump(iClient, iCourse, iJumpNumber);
					} else {
						CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Cannot find specified jump number.");
					}
				}
			} else {
				CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Cannot find specified course number.");
			}
		}
		default: {
			if (!(g_hCVGotoProgressed.BoolValue || bCanTeleToAllJumps || g_hCVGotoPlayerProgressed.BoolValue || bCanTeleToPlayers)) {
				CReplyToCommand(iClient, "{dodgerblue}[jse] {white}%t", "No Access");
				return Plugin_Handled;
			}

			if (g_hCVGotoProgressed.BoolValue || bCanTeleToAllJumps) {
				PrintToConsole(iClient, "[jse] Usage: sm_goto <course #> <jump # | 0 for end>");
			}

			if (g_hCVGotoPlayerProgressed.BoolValue || bCanTeleToPlayers) {
				PrintToConsole(iClient, "[jse] Usage: sm_goto [target]");
			}

			SendMainMenu(iClient, MenuHandler_GotoMain, MenuHandler_GotoPlayer);
		}
	}	

	return Plugin_Handled;
}

public Action cmdSend(int iClient, int iArgC) {
	switch (iArgC) {
		case 2: {
			char sArg1[MAX_NAME_LENGTH];
			GetCmdArg(1, sArg1, sizeof(sArg1));

			char sArg2[MAX_NAME_LENGTH];
			GetCmdArg(2, sArg2, sizeof(sArg2));

			char sTargetName[MAX_TARGET_LENGTH];
			int iTargetList[MAXPLAYERS], iTargetCount;
			bool bTnIsML;
		 
			if ((iTargetCount = ProcessTargetString(
					sArg1,
					iClient,
					iTargetList,
					MAXPLAYERS,
					COMMAND_FILTER_ALIVE,
					sTargetName,
					sizeof(sTargetName),
					bTnIsML)) <= 0) {
				ReplyToTargetError(iClient, iTargetCount);
				return Plugin_Handled;
			}

			if (iTargetCount > 1 && !CheckCommandAccess(iClient, MULTITARGET_OVERRIDE, ADMFLAG_GENERIC)) {
				ReplyToCommand(iClient, "{dodgerblue}[jse] {white}You do not have permission to multi-target.");
				return Plugin_Handled;
			}

			int iTarget = FindTarget(iClient, sArg2, false, true);
			if (iTarget != -1) {
				float fPos[3];
				GetClientAbsOrigin(iTarget, fPos);

				for (int i = 0; i < iTargetCount; i++) {
					GotoPlayer(iTargetList[i], iTarget, iTargetList[i] != iClient);
				}

				if (bTnIsML) {
					CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Teleported %t to %N.", sTargetName, iTarget);
				} else {
					CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Teleported %s to %N.", sTargetName, iTarget);
				}
			}
		}
		case 3: {
			char sArg1[MAX_NAME_LENGTH], sArg2[8], sArg3[8];
			GetCmdArg(1, sArg1, sizeof(sArg1));
			GetCmdArg(2, sArg2, sizeof(sArg2));
			GetCmdArg(3, sArg3, sizeof(sArg3));

			char sTargetName[MAX_TARGET_LENGTH];
			int iTargetList[MAXPLAYERS], iTargetCount;
			bool bTnIsML;
		 
			if ((iTargetCount = ProcessTargetString(
					sArg1,
					iClient,
					iTargetList,
					MAXPLAYERS,
					COMMAND_FILTER_ALIVE,
					sTargetName,
					sizeof(sTargetName),
					bTnIsML)) <= 0) {
				ReplyToTargetError(iClient, iTargetCount);
				return Plugin_Handled;
			}

			if (iTargetCount > 1 && !CheckCommandAccess(iClient, MULTITARGET_OVERRIDE, ADMFLAG_GENERIC)) {
				ReplyToCommand(iClient, "{dodgerblue}[jse] {white}You do not have permission to multi-target.");
				return Plugin_Handled;
			}

			int iCourseNumber = StringToInt(sArg2);
			int iJumpNumber = StringToInt(sArg3);

			Course iCourse = ResolveCourseNumber(iCourseNumber);
			if (iCourse) {
				char sBuffer[128];
				GetCourseName(iCourse, sBuffer, sizeof(sBuffer));

				if (iJumpNumber == 0) {
					for (int i = 0; i < iTargetCount; i++) {
						GotoControlPoint(iTargetList[i], iCourse, iTargetList[i] != iClient);
					}

					if (bTnIsML) {
						CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Teleported %t to the end of {limegreen}%s.", sTargetName, sBuffer);
					} else {
						CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Teleported %s to the end of {limegreen}%s.", sTargetName, sBuffer);
					}
				} else {
					Jump iJump = ResolveJumpNumber(iCourse, iJumpNumber);
					if (iJump) {
						for (int i = 0; i < iTargetCount; i++) {
							GotoJump(iTargetList[i], iCourse, iJumpNumber, iTargetList[i] != iClient);
						}

						if (bTnIsML) {
							CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Teleported %t to {limegreen}%s, Jump %d.", sTargetName, sBuffer, iJumpNumber);
						} else {
							CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Teleported %s to {limegreen}%s, Jump %d.", sTargetName, sBuffer, iJumpNumber);
						}
					} else {
						CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Cannot find specified jump number.");
					}
				}
			} else {
				CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Cannot find specified course number.");
			}
		}
		default: {
			CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Usage: sm_send <target> <to target>");
			CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Usage: sm_send <target> <course #> <jump # | 0 for end>");
		}
	}

	return Plugin_Handled;
}

// Menus

void SendMainMenu(int iClient, MenuHandler fnMainHandler, MenuHandler fnPlayerHandler) {
	if (!IsTrackerLoaded()) {
		SendPlayerMenu(iClient, fnPlayerHandler);

		return;
	}

	Menu hMenu = new Menu(fnMainHandler);
	hMenu.SetTitle("Select Destination");

	ArrayList hCourses = GetTrackerCourses();

	hMenu.AddItem(NULL_STRING, "Player", Client_GetCount() > 1 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	hMenu.AddItem(NULL_STRING, "Jump", hCourses.Length ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	hMenu.Display(iClient, 5);
}

void SendPlayerMenu(int iClient, MenuHandler fnHandler, bool bBackButton=true) {
	if (GetClientCount() < 2) {
		CReplyToCommand(iClient, "{dodgerblue}[jse] {white}No other players to go to.");
		return;
	}

	Menu hMenu = new Menu(fnHandler);
	hMenu.SetTitle("Select Player");
	hMenu.ExitBackButton = bBackButton;
	hMenu.ExitButton = true;

	ArrayList hPlayers = new ArrayList(ByteCountToCells(1+MAX_NAME_LENGTH));

	char sKey[8], sBlock[1+MAX_NAME_LENGTH];
	for (int i=1; i<=MaxClients; i++) {
		if (i != iClient && CheckSafeTeleportTarget(iClient, i, false)) {
			GetClientName(i, sBlock, MAX_NAME_LENGTH);
			sBlock[MAX_NAME_LENGTH] = i & 0xFF;
			hPlayers.PushArray(view_as<any>(sBlock));
		}
	}

	SortADTArray(hPlayers, Sort_Ascending, Sort_String);

	for (int i=0; i<hPlayers.Length; i++) {
		hPlayers.GetArray(i, view_as<any>(sBlock), 4*sizeof(sBlock));

		int iTarget = sBlock[MAX_NAME_LENGTH] & 0xFF;
		IntToString(iTarget, sKey, sizeof(sKey));
		hMenu.AddItem(sKey, sBlock);
	}

	delete hPlayers;

	hMenu.Display(iClient, 0);
}

void SendCourseMenu(int iClient, MenuHandler fnCourseHandler, MenuHandler fnJumpHandler, bool bBackButton=true) {
	ArrayList hCourses = GetTrackerCourses();

	if (!hCourses.Length) {
		return;
	}

	ArrayList hCourseNumbers = new ArrayList();

	bool bOverride = CheckCommandAccess(iClient, JUMPS_OVERRIDE, ADMFLAG_GENERIC);

	if (bOverride) {
		for (int i=0; i<hCourses.Length; i++) {
			Course iCourse = hCourses.Get(i);
			hCourseNumbers.Push(iCourse.iNumber);
		}
	} else {
		ArrayList hProgress = GetPlayerProgress(iClient);
		for (int i=0; i<hProgress.Length; i++) {
			Checkpoint eCheckpoint;
			hProgress.GetArray(i, eCheckpoint, sizeof(Checkpoint));

			int iCourseNumber = eCheckpoint.GetCourseNumber();

			if (hCourseNumbers.FindValue(iCourseNumber) == -1) {
				hCourseNumbers.Push(iCourseNumber);
			}
		}
		delete hProgress;
	
		if (!hCourseNumbers.Length) {
			CPrintToChat(iClient, "{dodgerblue}[jse] {white}You have not been to any courses.");
		}
	}

	if (hCourses.Length == 1 && hCourseNumbers.Length) {
		SendJumpMenu(iClient, fnJumpHandler, hCourses.Get(0));
		delete hCourseNumbers;

		return;
	}

	Menu hMenu = new Menu(fnCourseHandler);
	hMenu.SetTitle("Select Course");
	hMenu.ExitBackButton = bBackButton;
	hMenu.ExitButton = true;

	ArrayList hBonusCourses = new ArrayList();

	char sKey[8], sBuffer[128];
	for (int i=0; i<hCourses.Length; i++) {
		Course iCourse = hCourses.Get(i);
		int iCourseNumber = iCourse.iNumber;

		if (iCourseNumber < 0) {
			hBonusCourses.Push(iCourse);
			continue;
		}
		
		GetCourseName(iCourse, sBuffer, sizeof(sBuffer));

		IntToString(iCourseNumber, sKey, sizeof(sKey));
		hMenu.AddItem(sKey, sBuffer, hCourseNumbers.FindValue(iCourseNumber) == -1 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}

	for (int i=hBonusCourses.Length-1; i>=0; i--) {
		Course iCourse = hBonusCourses.Get(i);
		int iCourseNumber = iCourse.iNumber;

		GetCourseName(iCourse, sBuffer, sizeof(sBuffer));

		IntToString(iCourseNumber, sKey, sizeof(sKey));
		hMenu.AddItem(sKey, sBuffer, hCourseNumbers.FindValue(iCourseNumber) == -1 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}

	delete hBonusCourses;
	delete hCourseNumbers;

	hMenu.Display(iClient, 0);
}

void SendJumpMenu(int iClient, MenuHandler fnHandler, Course iCourse) {
	int iCourseNumber = iCourse.iNumber;

	ArrayList hJumps = iCourse.hJumps;

	Menu hMenu = new Menu(fnHandler);
	hMenu.SetTitle("Select Jump");
	hMenu.ExitBackButton = true;
	hMenu.ExitButton = true;

	bool bCompleted = false;

	char sKey[12], sBuffer[128];

	if (CheckCommandAccess(iClient, JUMPS_OVERRIDE, ADMFLAG_GENERIC)) {
		for (int i=1; i<=hJumps.Length; i++) {
			FormatEx(sBuffer, sizeof(sBuffer), "Jump %d", i);

			int iKey = (i & 0xFFFF) << 16 | iCourseNumber & 0xFFFF;
			IntToString(iKey, sKey, sizeof(sKey));
			hMenu.AddItem(sKey, sBuffer);
		}

		bCompleted = true;
	} else {
		int iFurthestJumpNumber = 0;

		ArrayList hProgress = GetPlayerProgress(iClient);
		for (int i=0; i<hProgress.Length; i++) {
			Checkpoint eCheckpoint;
			hProgress.GetArray(i, eCheckpoint, sizeof(Checkpoint));

			if (eCheckpoint.GetCourseNumber() == iCourseNumber) {
				if (eCheckpoint.IsControlPoint()) {
					bCompleted = true;
					continue;
				}

				int iJumpNumber = eCheckpoint.GetJumpNumber();
				if (iJumpNumber > iFurthestJumpNumber) {
					iFurthestJumpNumber = iJumpNumber;
				}
			}
		}
		delete hProgress;

		for (int i=1; i<=iFurthestJumpNumber; i++) {
			FormatEx(sBuffer, sizeof(sBuffer), "Jump %d", i);

			int	iKey = (i & 0xFFFF) << 16 | iCourseNumber & 0xFFFF;

			IntToString(iKey, sKey, sizeof(sKey));
			hMenu.AddItem(sKey, sBuffer);
		}
	}

	if (bCompleted) {
		FormatEx(sBuffer, sizeof(sBuffer), "Control Point");
		int iKey = iCourseNumber & 0xFFFF;

		IntToString(iKey, sKey, sizeof(sKey));
		hMenu.AddItem(sKey, sBuffer);
	}

	hMenu.Display(iClient, 0);
}

// Menu handlers

public int MenuHandler_BringPlayer(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			char sKey[8];
			hMenu.GetItem(iOption, sKey, sizeof(sKey));

			int iTarget = StringToInt(sKey);			
			if (!IsClientInGame(iTarget)) {
				return;
			}

			float fPos[3];
			GetClientEyePosition(iClient, fPos);

			float fAimPos[3];
			GetAimPos(iClient, fAimPos);

			AdjustHullPos(iTarget, fPos, fAimPos);

			BringPlayer(iClient, iTarget, fAimPos);
		}

		case MenuAction_End: {
			delete hMenu;
		}
	}
}

public int MenuHandler_GotoMain(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			switch (iOption) {
				case 0: SendPlayerMenu(iClient, MenuHandler_GotoPlayer);
				case 1: SendCourseMenu(iClient, MenuHandler_GotoCourse, MenuHandler_GotoJump);
			}
		}

		case MenuAction_End: {
			delete hMenu;
		}
	}
}

public int MenuHandler_GotoPlayer(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			char sKey[8];
			hMenu.GetItem(iOption, sKey, sizeof(sKey));

			int iTarget = StringToInt(sKey);

			if (CheckSafeTeleportTarget(iClient, iTarget)) {
				if (CheckCommandAccess(iClient, JUMPS_OVERRIDE, ADMFLAG_GENERIC)) {
					GotoPlayer(iClient, iTarget);
				} else {
					int iCourseNumber;
					int iJumpNumber;
					bool bControlPoint;

					if (GetPlayerNearestCheckpoint(iTarget, iCourseNumber, iJumpNumber, bControlPoint)) {
						Course iCourse = ResolveCourseNumber(iCourseNumber);

						if (CheckProgress(iClient, iCourseNumber, iJumpNumber, bControlPoint)) {
							if (bControlPoint) {
								GotoControlPoint(iClient, iCourse);
							} else {
								GotoJump(iClient, iCourse, iJumpNumber);
							}
						} else {
							char sBuffer[256];
							GetCourseLocationString(sBuffer, sizeof(sBuffer), iCourse, iJumpNumber, bControlPoint);

							CPrintToChat(iClient, "{dodgerblue}[jse] {white}You have not been to %N's location before: %s", iTarget, sBuffer);

							SendPlayerMenu(iClient, MenuHandler_GotoPlayer);
						}
					} else {
						CPrintToChat(iClient, "{dodgerblue}[jse] {white}%N is not found near any jump.", iTarget);

						SendPlayerMenu(iClient, MenuHandler_GotoPlayer);
					}
				}
			}
		}

		case MenuAction_Cancel: {
			if (iOption == MenuCancel_ExitBack) {
				SendMainMenu(iClient, MenuHandler_GotoMain, MenuHandler_GotoPlayer);
			}
		}

		case MenuAction_End: {
			delete hMenu;
		}
	}
}

public int MenuHandler_GotoCourse(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			char sKey[8];
			hMenu.GetItem(iOption, sKey, sizeof(sKey));

			Course iCourse = ResolveCourseNumber(StringToInt(sKey));
			SendJumpMenu(iClient, MenuHandler_GotoJump, iCourse);
		}

		case MenuAction_Cancel: {
			if (iOption == MenuCancel_ExitBack) {
				SendMainMenu(iClient, MenuHandler_GotoMain, MenuHandler_GotoPlayer);
			}
		}

		case MenuAction_End: {
			delete hMenu;
		}
	}
}

public int MenuHandler_GotoJump(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			char sKey[12];
			hMenu.GetItem(iOption, sKey, sizeof(sKey));

			int iKey = StringToInt(sKey);
			Course iCourse = ResolveCourseNumber(iKey & 0xFFFF);
			int iJumpNumber = (iKey >> 16) & 0xFFFF;

			if (iJumpNumber) {
				GotoJump(iClient, iCourse, iJumpNumber);
			} else {
				GotoControlPoint(iClient, iCourse);
			}
		}

		case MenuAction_Cancel: {
			if (iOption == MenuCancel_ExitBack) {
				SendMainMenu(iClient, MenuHandler_GotoMain, MenuHandler_GotoPlayer);
			}
		}

		case MenuAction_End: {
			delete hMenu;
		}
	}
}
