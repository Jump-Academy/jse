#pragma semicolon 1

//#define DEBUG

#define PLUGIN_AUTHOR		"AI"
#define PLUGIN_VERSION		"0.3.0"

#define CAMERA_MODEL		"models/combine_scanner.mdl"

#include <sourcemod>
#include <sdktools>
#include <smlib/arrays>
#include <smlib/clients>
#include <smlib/entities>

#include "jse_foresight_camera.sp"

#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL	"http://jumpacademy.tf/plugins/jse/foresight/updatefile.txt"

ConVar g_hCVDuration;
ConVar g_hCVTurnRatio;
ConVar g_hCVSpeed;
ConVar g_hCVAccel;
ConVar g_hCVAlpha;

ArrayList g_hCameras;
FSCamera g_mActiveCamera[MAXPLAYERS+1] = {NULL_CAMERA, ...};

enum struct FOV {
	int iFOV;
	int iDefaultFOV;
	bool bForceTauntCam;
}

FOV g_eFOVBackup[MAXPLAYERS+1];

public Plugin myinfo = {
	name = "Jump Server Essentials - Foresight",
	author = PLUGIN_AUTHOR,
	description = "JSE foresight module for previewing the map ahead",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	CreateConVar("jse_foresight_version", PLUGIN_VERSION, "Jump Server Essentials foresight version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_hCVDuration = CreateConVar("jse_foresight_duration", "30.0", "Foresight max duration", FCVAR_NONE, true, -1.0);
	g_hCVTurnRatio = CreateConVar("jse_foresight_turn_ratio", "0.08", "Foresight mouse-to-angle turn ratio", FCVAR_NONE, true, 0.0);
	g_hCVSpeed = CreateConVar("jse_foresight_speed", "1000.0", "Foresight fly speed", FCVAR_NONE, true, 0.0);
	g_hCVAccel = CreateConVar("jse_foresight_accel", "0.075", "Foresight fly acceleration", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCVAlpha = CreateConVar("jse_foresight_alpha", "0.6", "Player body transparency ratio when using foresight", FCVAR_NONE, true, 0.0, true, 1.0);
	
	RegConsoleCmd("sm_foresight",	cmdForesight, "Explore in spirit form");
	RegConsoleCmd("sm_fs",			cmdForesight, "Explore in spirit form");

	HookEvent("player_death", Event_PlayerChangeState);
	HookEvent("player_spawn", Event_PlayerChangeState, EventHookMode_Pre);
	
	HookEvent("player_changeclass", Event_PlayerChangeState);
	HookEvent("player_team", Event_PlayerChangeState);

	LoadTranslations("common.phrases");

	g_hCameras = new ArrayList();

	if (LibraryExists("updater")) {
		Updater_AddPlugin(UPDATE_URL);
	}
}

public void OnPluginEnd() {
	Cleanup();
}

public void OnLibraryAdded(const char[] sName) {
	if (StrEqual(sName, "updater")) {
		Updater_AddPlugin(UPDATE_URL);
	}
}

public void OnMapStart() {
	PrecacheModel(CAMERA_MODEL);
}

public void OnMapEnd() {
	Cleanup();
}

public void OnClientDisconnect(int iClient) {
	FSCamera mCamera = g_mActiveCamera[iClient];
	if (mCamera) {
		DisableForesight(mCamera);
	}
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float vecVel[3], float vecAng[3], int &iWeapon, int& iSubType, int& iCmdNum, int& iTickCount, int& iSeed, int iMouse[2]) {
	if (!IsClientInGame(iClient)) {
		return Plugin_Continue;
	}

	FSCamera mCamera = g_mActiveCamera[iClient];
	if (!mCamera) {
		return Plugin_Continue;
	}

	float fTimeLeft = 1.0;
	float fStartTime = mCamera.fStartTime;
	if (g_hCVDuration.IntValue != -1 && fStartTime > 0.0) {
		fTimeLeft = g_hCVDuration.FloatValue - (GetGameTime()-fStartTime);
	}

	if (iButtons & IN_ATTACK || fTimeLeft <= 0.0) {
		DisableForesight(mCamera);
		return Plugin_Continue;
	}

	if (GetEntProp(iClient, Prop_Send, "m_nForceTauntCam")) {
		SetEntProp(iClient, Prop_Send, "m_nForceTauntCam", 0);
	}

	int iEntity = mCamera.iEntity;
	float fAlpha = g_hCVTurnRatio.FloatValue;
	float vecAngDesired[3];
	Entity_GetAbsAngles(iEntity, vecAngDesired);
	vecAngDesired[0] = Clamp(vecAngDesired[0] + fAlpha*float(iMouse[1]), -90.0, 90.0);
	vecAngDesired[1] -= fAlpha*float(iMouse[0]);
	if (vecAngDesired[1] > 180.0) {
		vecAngDesired[1] -= 360.0;
	} else if (vecAngDesired[1] < -180.0) {
		vecAngDesired[1] += 360.0;
	}
	Entity_SetAbsAngles(iEntity, vecAngDesired);

	float vecVelDesired[3];

	float vecFwd[3], vecRight[3];
	GetAngleVectors(vecAngDesired, vecFwd, vecRight, NULL_VECTOR);

	float vecUp[3] = {0.0, 0.0, 1.0};

	float fSpeed = g_hCVSpeed.FloatValue;
	ScaleVector(vecFwd, fSpeed * (float((iButtons & IN_FORWARD) != 0) - float((iButtons & IN_BACK) != 0)));
	ScaleVector(vecRight, fSpeed * (float((iButtons & IN_MOVERIGHT) != 0) - float((iButtons & IN_MOVELEFT) != 0)));
	ScaleVector(vecUp, fSpeed * (float((iButtons & IN_JUMP) != 0) - float((iButtons & IN_DUCK) != 0)));
	
	AddVectors(vecFwd, vecRight, vecVelDesired);
	AddVectors(vecVelDesired, vecUp, vecVelDesired);

	if (GetGameTickCount() % 33 == 0) {
		if (fStartTime) {
			PrintHintText(iClient, "Press %s to exit foresight (%.0f)", "%+attack%", fTimeLeft);
		} else {
			PrintHintText(iClient, "Press %s to exit foresight", "%+attack%");
		}
		
		StopSound(iClient, SNDCHAN_STATIC, "ui/hint.wav");
	}
	
	float vecVelCurrent[3], vecVelDiff[3];
	Entity_GetAbsVelocity(iEntity, vecVelCurrent);
	SubtractVectors(vecVelDesired, vecVelCurrent, vecVelDiff);

	ScaleVector(vecVelDiff, g_hCVAccel.FloatValue);
	AddVectors(vecVelCurrent, vecVelDiff, vecVelDesired);
	Entity_SetAbsVelocity(iEntity, vecVelDesired);

	return Plugin_Continue;
}

// Custom callbacks

public Action Event_PlayerChangeState(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!iClient) {
		return Plugin_Handled;
	}
	
	if (g_mActiveCamera[iClient]) {
		DisableForesight(g_mActiveCamera[iClient]);
	}	
	
	return Plugin_Continue;
}

// Commands

public Action cmdForesight(int iClient, int iArgC) {
	if (g_mActiveCamera[iClient]) {
		DisableForesight(g_mActiveCamera[iClient]);

		return Plugin_Handled;
	}

	if (!IsPlayerAlive(iClient) || !(GetEntityFlags(iClient) & FL_ONGROUND)) {
		return Plugin_Handled;
	}

	int iEntity = CreateEntityByName("prop_dynamic_override");
	if (iEntity == -1) {
		return Plugin_Handled;
	}

	int iViewControl = CreateEntityByName("point_viewcontrol");
	if (iViewControl == -1) {
		Entity_Kill(iEntity);
		return Plugin_Handled;
	}

	g_eFOVBackup[iClient].iFOV = GetEntProp(iClient, Prop_Send, "m_iFOV");
	g_eFOVBackup[iClient].iDefaultFOV = GetEntProp(iClient, Prop_Send, "m_iDefaultFOV");
	g_eFOVBackup[iClient].bForceTauntCam = view_as<bool>(GetEntProp(iClient, Prop_Send, "m_nForceTauntCam"));
	
	SetEntityModel(iEntity, CAMERA_MODEL);
	SetEntityRenderMode(iEntity, RENDER_TRANSALPHA);
	#if defined DEBUG
	SetEntityRenderColor(iEntity, 255, 255, 255, 50);
	#else
	SetEntityRenderMode(iEntity, RENDER_NONE);
	SetEntityRenderColor(iEntity, 0, 0, 0, 0);
	#endif
	DispatchSpawn(iEntity);
	SetEntityMoveType(iEntity, MOVETYPE_NOCLIP);

	if (g_hCVAlpha.FloatValue < 1.0) {
		SetEntityRenderMode(iClient, RENDER_TRANSALPHA);
		int iR, iG, iB, iA;
		GetEntityRenderColor(iClient, iR, iG, iB, iA);
		SetEntityRenderColor(iClient, iR, iG, iB, RoundToNearest(255*g_hCVAlpha.FloatValue));
	}

	SetVariantString("!activator");
	AcceptEntityInput(iViewControl, "SetParent", iEntity, iViewControl);
	DispatchSpawn(iViewControl);

	FSCamera mCamera = FSCamera.Instance();
	mCamera.iClient = iClient;
	mCamera.iEntity = iEntity;
	mCamera.iViewControl = iViewControl;

	if (!CheckCommandAccess(iClient, "jse_foresight_untimed", ADMFLAG_RESERVATION)) {
		mCamera.fStartTime = GetGameTime();
	}
	
	float vecPos[3], vecAng[3], vecDir[3];
	GetClientEyePosition(iClient, vecPos);
	GetClientEyeAngles(iClient, vecAng);
	
	GetAngleVectors(vecAng, vecDir, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(vecDir, 50.0);
	AddVectors(vecPos, vecDir, vecPos);
	NormalizeVector(vecDir, vecDir);
	ScaleVector(vecDir, 0.5*g_hCVSpeed.FloatValue);
	
	TeleportEntity(iEntity, vecPos, vecAng, vecDir);

	g_hCameras.Push(mCamera);
	g_mActiveCamera[iClient] = mCamera;

	#if !defined DEBUG
	SetClientViewEntity(iClient, iViewControl);
	SetEntityFlags(iClient, GetEntityFlags(iClient) | FL_FROZEN | FL_ATCONTROLS);
	AcceptEntityInput(iViewControl, "Enable", iClient, iViewControl, 0);
	Client_SetHideHud(iClient, HIDEHUD_HEALTH | HIDEHUD_WEAPONSELECTION | HIDEHUD_MISCSTATUS);

	Client_SetObserverTarget(iClient, 0);
	Client_SetObserverMode(iClient, OBS_MODE_DEATHCAM, false);

	SetEntProp(iClient, Prop_Send, "m_iFOV", g_eFOVBackup[iClient].iFOV);
	SetEntProp(iClient, Prop_Send, "m_iDefaultFOV", g_eFOVBackup[iClient].iDefaultFOV);

	#endif

	return Plugin_Handled;
}

// Helpers

float Clamp(float fValue, float fMin, float fMax) {
	if (fValue < fMin) {
		fValue = fMin;
	} else if (fValue > fMax) {
		fValue = fMax;
	}

	return fValue;
}

void Cleanup() {
	while (g_hCameras.Length) {
		DisableForesight(g_hCameras.Get(0));
	}

	Array_Fill(g_mActiveCamera, sizeof(g_mActiveCamera), NULL_CAMERA);
}

void DisableCamera(FSCamera mCamera) {
	if (!mCamera) {
		return;
	}

	int iClient = mCamera.iClient;
	if (Client_IsValid(iClient) && IsClientInGame(iClient)) {
		int iViewControl = mCamera.iViewControl;
		if (IsValidEntity(iViewControl)) {
			AcceptEntityInput(iViewControl, "Disable");
			Entity_Kill(iViewControl);
		}

		SetEntityFlags(iClient, GetEntityFlags(iClient) & ~(FL_FROZEN | FL_ATCONTROLS));

		int hViewEntity = GetEntPropEnt(iClient, Prop_Data, "m_hViewEntity");
		if (IsValidEntity(hViewEntity) && HasEntProp(hViewEntity, Prop_Data, "m_hPlayer") && GetEntPropEnt(hViewEntity, Prop_Data, "m_hPlayer")  != iClient) {
			SetEntPropEnt(hViewEntity, Prop_Data, "m_hPlayer", iClient);
			AcceptEntityInput(hViewEntity, "Disable");
		}

		if (g_hCVAlpha.FloatValue < 1.0) {
			SetEntityRenderMode(iClient, RENDER_TRANSALPHA);
			int iR, iG, iB, iA;
			GetEntityRenderColor(iClient, iR, iG, iB, iA);
			SetEntityRenderColor(iClient, iR, iG, iB, 255);
		}
	}

	int iEntiy = mCamera.iEntity;
	if (IsValidEntity(iEntiy)) {
		Entity_Kill(iEntiy, true);
	}
	
	mCamera.iEntity = INVALID_ENT_REFERENCE;
	mCamera.iViewControl = INVALID_ENT_REFERENCE;
}

void DisableForesight(FSCamera mCamera) {
	if (!mCamera) {
		return;
	}

	int iCameraIdx = g_hCameras.FindValue(mCamera);
	if (iCameraIdx != -1) {
		g_hCameras.Erase(iCameraIdx);
	}

	DisableCamera(mCamera);

	int iClient = mCamera.iClient;
	if (IsClientInGame(iClient)) {
		Client_SetObserverTarget(iClient, -1);
		Client_SetObserverMode(iClient, OBS_MODE_NONE);
		Client_SetHideHud(iClient, 0);
		ResetFOV(iClient);

		SetEntityMoveType(iClient, MOVETYPE_WALK);

		PrintHintText(iClient, " ");
		StopSound(iClient, SNDCHAN_STATIC, "ui/hint.wav");
	}

	FSCamera.Destroy(mCamera);
	g_mActiveCamera[iClient] = NULL_CAMERA;
}

void ResetFOV(int iClient) {
	SetEntProp(iClient, Prop_Send, "m_iFOV", g_eFOVBackup[iClient].iFOV);
	SetEntProp(iClient, Prop_Send, "m_iDefaultFOV", g_eFOVBackup[iClient].iDefaultFOV);
	SetEntProp(iClient, Prop_Send, "m_nForceTauntCam", g_eFOVBackup[iClient].bForceTauntCam);
}
