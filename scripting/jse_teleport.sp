#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR	"AI"
#define PLUGIN_VERSION	"0.1.0"

#include <jse_tracker>
#include <smlib/clients>
#include <multicolors>

#define JUMPS_OVERRIDE 			"jse_teleport_jumps"
#define MULTITARGET_OVERRIDE	"jse_teleport_multitarget"

public Plugin myinfo = {
	name = "Jump Server Essentials - Teleport",
	author = PLUGIN_AUTHOR,
	description = "JSE player teleport component",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	CreateConVar("jse_teleport_version", PLUGIN_VERSION, "Jump Server Essentials teleport version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	RegAdminCmd("sm_goto", cmdGoto, ADMFLAG_GENERIC, "Teleport self");
	RegAdminCmd("sm_bring", cmdBring, ADMFLAG_GENERIC, "Teleport player to aim");
	RegAdminCmd("sm_send", cmdSend, ADMFLAG_GENERIC, "Teleport player");

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

void GotoJump(int iClient, Course iCourse, Jump iJump, bool bNotify=true) {
	float fOrigin[3];
	iJump.GetOrigin(fOrigin);
	fOrigin[2] += 10.0;

	TeleportEntity(iClient, fOrigin, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));

	char sBuffer[128];
	GetCourseName(iCourse, sBuffer, sizeof(sBuffer));

	if (bNotify) {
		if (iCourse.hJumps.Length > 1) {
			CPrintToChat(iClient, "{dodgerblue}[jse] {white}You have been teleported to {limegreen}%s, Jump %d", sBuffer, iJump.iNumber);
		} else {
			CPrintToChat(iClient, "{dodgerblue}[jse] {white}You have been teleported to {limegreen}%s", sBuffer);
		}
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
			COMMAND_FILTER_NO_IMMUNITY,
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
		CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Teleported %s to aim", sTargetName);
	}

	return Plugin_Handled;
}

public Action cmdGoto(int iClient, int iArgC) {
	if (!iClient) {
		ReplyToCommand(iClient, "[jse] You cannot run this command from server console.");
		return Plugin_Handled;
	}

	switch (iArgC) {
		case 1: {
			char sArg1[MAX_NAME_LENGTH];
			GetCmdArg(1, sArg1, sizeof(sArg1));

			int iTarget = FindTarget(iClient, sArg1, false, true);
			if (iTarget != -1) {
				GotoPlayer(iClient, iTarget);
			}
		}
		case 2: {
			if (!CheckCommandAccess(iClient, JUMPS_OVERRIDE, ADMFLAG_GENERIC)) {
				ReplyToCommand(iClient, "{dodgerblue}[jse] {white}You do not have permission to teleport to jumps.");
				return Plugin_Handled;
			}

			char sArg1[8], sArg2[8];
			GetCmdArg(1, sArg1, sizeof(sArg1));
			GetCmdArg(2, sArg2, sizeof(sArg2));

			int iCourseNumber = StringToInt(sArg1);
			int iJumpNumber = StringToInt(sArg2);

			ArrayList hCourses = GetTrackerCourses();
			Course iCourse;
			for (int i=0; i<hCourses.Length && !iCourse; i++) {
				Course iCourseItr = hCourses.Get(i);
				if (iCourseItr.iNumber == iCourseNumber) {
					iCourse = iCourseItr;
				}
			}

			if (iCourse) {
				ArrayList hJumps = iCourse.hJumps;
				if (1 <= iJumpNumber && iJumpNumber <= hJumps.Length) {
					GotoJump(iClient, iCourse, hJumps.Get(iJumpNumber-1));
				} else {
					CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Cannot find specified jump number.");
				}
			} else {
				CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Cannot find specified course number.");
			}
		}
		default: {
			PrintToConsole(iClient, "[jse] Usage: sm_goto [target]");

			if (CheckCommandAccess(iClient, JUMPS_OVERRIDE, ADMFLAG_GENERIC)) {
				PrintToConsole(iClient, "[jse] Usage: sm_goto <course #> <jump #>");
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
					COMMAND_FILTER_NO_IMMUNITY,
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
					CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Teleported %s to %N", sTargetName, iTarget);
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
					COMMAND_FILTER_NO_IMMUNITY,
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

			ArrayList hCourses = GetTrackerCourses();
			Course iCourse;
			for (int i=0; i<hCourses.Length && !iCourse; i++) {
				Course iCourseItr = hCourses.Get(i);
				if (iCourseItr.iNumber == iCourseNumber) {
					iCourse = iCourseItr;
				}
			}

			if (iCourse) {
				ArrayList hJumps = iCourse.hJumps;
				if (1 <= iJumpNumber && iJumpNumber <= hJumps.Length) {
					Jump iJump = hJumps.Get(iJumpNumber-1);

					for (int i = 0; i < iTargetCount; i++) {
						GotoJump(iTargetList[i], iCourse, iJump, iTargetList[i] != iClient);
					}

					char sBuffer[128];
					GetCourseName(iCourse, sBuffer, sizeof(sBuffer));

					if (bTnIsML) {
						CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Teleported %t to {limegreen}%s, Jump %d", sTargetName, sBuffer, iJump.iNumber);
					} else {
						CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Teleported %s to {limegreen}%s, Jump %d", sTargetName, sBuffer, iJump.iNumber);
					}
				} else {
					CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Cannot find specified jump number.");
				}
			} else {
				CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Cannot find specified course number.");
			}
		}
		default: {
			CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Usage: sm_send <target> <to target>");
			CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Usage: sm_send <target> <course #> <jump #>");
		}
	}

	return Plugin_Handled;
}

// Menus

void SendMainMenu(int iClient, MenuHandler fnMainHandler, MenuHandler fnPlayerHandler) {
	if (!IsTrackerLoaded() || !CheckCommandAccess(iClient, JUMPS_OVERRIDE, ADMFLAG_GENERIC)) {
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
		if (IsClientInGame(i) && i != iClient) {
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
		hMenu.AddItem(sKey, sBlock, CanUserTarget(iClient, iTarget) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}

	delete hPlayers;

	hMenu.Display(iClient, 0);
}

void SendCourseMenu(int iClient, MenuHandler fnCourseHandler, MenuHandler fnJumpHandler) {
	ArrayList hCourses = GetTrackerCourses();

	if (hCourses.Length == 1) {
		SendJumpMenu(iClient, fnJumpHandler, hCourses.Get(0));
		return;
	}

	Menu hMenu = new Menu(fnCourseHandler);
	hMenu.SetTitle("Select Course");
	hMenu.ExitBackButton = true;
	hMenu.ExitButton = true;

	ArrayList hBonusCourses = new ArrayList();

	char sKey[8], sBuffer[128];
	for (int i=0; i<hCourses.Length; i++) {
		Course iCourse = hCourses.Get(i);
		if (iCourse.iNumber < 0) {
			hBonusCourses.Push(iCourse);
			continue;
		}
		
		GetCourseName(iCourse, sBuffer, sizeof(sBuffer));

		IntToString(view_as<int>(iCourse), sKey, sizeof(sKey));
		hMenu.AddItem(sKey, sBuffer);
	}

	for (int i=hBonusCourses.Length-1; i>=0; i--) {
		Course iCourse = hBonusCourses.Get(i);
		GetCourseName(iCourse, sBuffer, sizeof(sBuffer));

		IntToString(view_as<int>(iCourse), sKey, sizeof(sKey));
		hMenu.AddItem(sKey, sBuffer);
	}

	delete hBonusCourses;

	hMenu.Display(iClient, 0);

}

void SendJumpMenu(int iClient, MenuHandler fnHandler, Course iCourse) {
	ArrayList hJumps = iCourse.hJumps;

	Menu hMenu = new Menu(fnHandler);
	hMenu.SetTitle("Select Jump");
	hMenu.ExitBackButton = true;
	hMenu.ExitButton = true;

	char sKey[8], sBuffer[128];
	for (int i=0; i<hJumps.Length; i++) {
		Jump iJump = hJumps.Get(i);
		FormatEx(sBuffer, sizeof(sBuffer), "Jump %d", iJump.iNumber);

		int iKey = view_as<int>(iJump) << 16 | view_as<int>(iCourse);
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

			GotoPlayer(iClient, StringToInt(sKey));
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

			Course iCourse = view_as<Course>(StringToInt(sKey));
			ArrayList hJumps = iCourse.hJumps;
			if (hJumps.Length == 1) {
				GotoJump(iClient, iCourse, hJumps.Get(0));
			} else {
				SendJumpMenu(iClient, MenuHandler_GotoJump, iCourse);
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

public int MenuHandler_GotoJump(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			char sKey[8];
			hMenu.GetItem(iOption, sKey, sizeof(sKey));

			int iKey = StringToInt(sKey);
			Course iCourse = view_as<Course>(iKey & 0xFFFF);
			Jump iJump = view_as<Jump>((iKey >> 16) & 0xFFFF);
			GotoJump(iClient, iCourse, iJump);
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
