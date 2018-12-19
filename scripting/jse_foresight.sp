#pragma semicolon 1

//#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.2.1"

#define CAMERA_MODEL	"models/combine_scanner.mdl"

#include <sourcemod>
#include <sdktools>
#include <smlib/arrays>
#include <smlib/clients>
#include <smlib/entities>

#include <jse_foresight>
#include "jse_foresight_camera.sp"

#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL	"http://jumpacademy.tf/plugins/jse/foresight/updatefile.txt"

ConVar g_hDuration;
ConVar g_hTurnRatio;
ConVar g_hSpeed;
ConVar g_hAccel;
ConVar g_hAlpha;

ArrayList g_hCameras;
FSCamera g_iActiveCamera[MAXPLAYERS+1] = {NULL_CAMERA, ...};

public Plugin myinfo = {
	name = "Jump Server Essentials - Foresight",
	author = PLUGIN_AUTHOR,
	description = "JSE foresight module for previewing the map ahead",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	CreateConVar("jse_foresight_version", PLUGIN_VERSION, "Jump Server Essentials foresight version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_hDuration = CreateConVar("jse_foresight_duration", "30.0", "Foresight max duration", FCVAR_NONE, true, -1.0);
	g_hTurnRatio = CreateConVar("jse_foresight_turn_ratio", "0.08", "Foresight mouse-to-angle turn ratio", FCVAR_NONE, true, 0.0);
	g_hSpeed = CreateConVar("jse_foresight_speed", "1000.0", "Foresight fly speed", FCVAR_NONE, true, 0.0);
	g_hAccel = CreateConVar("jse_foresight_accel", "0.075", "Foresight fly acceleration", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hAlpha = CreateConVar("jse_foresight_alpha", "0.6", "Player body transparency ratio when using foresight", FCVAR_NONE, true, 0.0, true, 1.0);
	
	RegConsoleCmd("sm_foresight",	cmdForesight, "Explore in spirit form");
	RegConsoleCmd("sm_fs",			cmdForesight, "Explore in spirit form");

	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Pre);
	
	HookEvent("player_changeclass", Event_PlayerChangeClass);

	LoadTranslations("common.phrases");

	g_hCameras = new ArrayList();
}

public void OnPluginEnd() {
	Cleanup();
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int sErrMax) {
	RegPluginLibrary("jse_foresight");
	Camera_SetupNatives();
}

public void OnMapStart() {
	PrecacheModel(CAMERA_MODEL);
}

public void OnMapEnd() {
	Cleanup();
}

public void OnClientDisconnect(int iClient) {
	FSCamera iCamera = g_iActiveCamera[iClient];
	if (iCamera != NULL_CAMERA) {
		g_iActiveCamera[iClient] = NULL_CAMERA;
		int iCameraIdx = g_hCameras.FindValue(iCamera);
		if (iCameraIdx != -1) {
			g_hCameras.Erase(iCameraIdx);
		}
		
		DisableCamera(iCamera);
		FSCamera.Destroy(iCamera);
	}
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float fVel[3], float fAng[3], int &iWeapon, int& iSubType, int& iCmdNum, int& iTickCount, int& iSeed, int iMouse[2]) {
	FSCamera iCamera = g_iActiveCamera[iClient];
	if (iCamera == NULL_CAMERA) {
		return Plugin_Continue;
	}

	float fTimeLeft = 1.0;
	float fStartTime = iCamera.StartTime;
	if (g_hDuration.IntValue != -1 && fStartTime > 0.0) {
		fTimeLeft = g_hDuration.FloatValue - (GetGameTime()-fStartTime);
	}

	if (iButtons & IN_ATTACK || fTimeLeft <= 0.0) {
		DisableForesight(iCamera);
		return Plugin_Continue;
	}

	int iEntity = EntRefToEntIndex(iCamera.Entity);
	float fAlpha = g_hTurnRatio.FloatValue;
	float fAngDesired[3];
	Entity_GetAbsAngles(iEntity, fAngDesired);
	fAngDesired[0] = Clamp(fAngDesired[0] + fAlpha*float(iMouse[1]), -90.0, 90.0);
	fAngDesired[1] -= fAlpha*float(iMouse[0]);
	if (fAngDesired[1] > 180.0) {
		fAngDesired[1] -= 360.0;
	} else if (fAngDesired[1] < -180.0) {
		fAngDesired[1] += 360.0;
	}
	Entity_SetAbsAngles(iEntity, fAngDesired);

	float fVelDesired[3];

	float fFwd[3], fRight[3], fUp[3];
	GetAngleVectors(fAngDesired, fFwd, fRight, fUp);

	float fSpeed = g_hSpeed.FloatValue;
	ScaleVector(fFwd, fSpeed * (float((iButtons & IN_FORWARD) != 0) - float((iButtons & IN_BACK) != 0)));
	ScaleVector(fRight, fSpeed * (float((iButtons & IN_MOVERIGHT) != 0) - float((iButtons & IN_MOVELEFT) != 0)));
	ScaleVector(fUp, fSpeed * (float((iButtons & IN_JUMP) != 0) - float((iButtons & IN_DUCK) != 0)));
	
	AddVectors(fFwd, fRight, fVelDesired);
	AddVectors(fVelDesired, fUp, fVelDesired);

	if (GetGameTickCount() % 33 == 0) {
		if (fStartTime) {
			PrintHintText(iClient, "Press %s to exit foresight (%.0f)", "%+attack%", fTimeLeft);
		} else {
			PrintHintText(iClient, "Press %s to exit foresight", "%+attack%");
		}
		
		StopSound(iClient, SNDCHAN_STATIC, "ui/hint.wav");
	}
	
	float fVelCurrent[3], fVelDiff[3];
	Entity_GetAbsVelocity(iEntity, fVelCurrent);
	SubtractVectors(fVelDesired, fVelCurrent, fVelDiff);

	ScaleVector(fVelDiff, g_hAccel.FloatValue);
	AddVectors(fVelCurrent, fVelDiff, fVelDesired);
	Entity_SetAbsVelocity(iEntity, fVelDesired);

	return Plugin_Continue;
}

// Custom callbacks

public Action Event_PlayerChangeClass(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (g_iActiveCamera[iClient]) {
		DisableCamera(g_iActiveCamera[iClient]);
	}	
	
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (g_iActiveCamera[iClient]) {
		DisableCamera(g_iActiveCamera[iClient]);
	}

	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (g_iActiveCamera[iClient]) {
		DisableCamera(g_iActiveCamera[iClient]);
	}
	
	return Plugin_Continue;
}

// Commands

public Action cmdForesight(int iClient, int iArgC) {
	if (g_iActiveCamera[iClient] != NULL_CAMERA) {
		DisableForesight(g_iActiveCamera[iClient]);
		return Plugin_Handled;
	}

	if (!(GetEntityFlags(iClient) & FL_ONGROUND)) {
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

	if (g_hAlpha.FloatValue < 1.0) {
		SetEntityRenderMode(iClient, RENDER_TRANSALPHA);
		int iR, iG, iB, iA;
		GetEntityRenderColor(iClient, iR, iG, iB, iA);
		SetEntityRenderColor(iClient, iR, iG, iB, RoundToNearest(255*g_hAlpha.FloatValue));
	}

	SetVariantString("!activator");
	AcceptEntityInput(iViewControl, "SetParent", iEntity, iViewControl);
	DispatchSpawn(iViewControl);

	FSCamera iCamera = FSCamera.Instance();
	iCamera.Client = iClient;
	iCamera.Entity = EntIndexToEntRef(iEntity);
	iCamera.ViewControl = EntIndexToEntRef(iViewControl);

	if (!CheckCommandAccess(iClient, "jse_foresight_untimed", ADMFLAG_RESERVATION)) {
		iCamera.StartTime = GetGameTime();
	}
	
	float fPos[3], fAng[3], fDir[3];
	GetClientEyePosition(iClient, fPos);
	GetClientEyeAngles(iClient, fAng);
	
	GetAngleVectors(fAng, fDir, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(fDir, 50.0);
	AddVectors(fPos, fDir, fPos);
	NormalizeVector(fDir, fDir);
	ScaleVector(fDir, 0.5*g_hSpeed.FloatValue);
	
	TeleportEntity(iEntity, fPos, fAng, fDir);

	g_hCameras.Push(iCamera);
	g_iActiveCamera[iClient] = iCamera;

	#if !defined DEBUG
	SetClientViewEntity(iClient, iViewControl);
	SetEntityFlags(iClient, GetEntityFlags(iClient) | FL_FROZEN | FL_ATCONTROLS);
	AcceptEntityInput(iViewControl, "Enable", iClient, iViewControl, 0);
	Client_SetHideHud(iClient, HIDEHUD_HEALTH | HIDEHUD_WEAPONSELECTION | HIDEHUD_MISCSTATUS);

	Client_SetObserverTarget(iClient, 0);
	Client_SetObserverMode(iClient, OBS_MODE_DEATHCAM, false);

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
	for (int i=0; i<g_hCameras.Length; i++) {
		FSCamera iCamera = g_hCameras.Get(i);
		DisableCamera(iCamera);
		FSCamera.Destroy(iCamera);
	}
	g_hCameras.Clear();

	Array_Fill(g_iActiveCamera, sizeof(g_iActiveCamera), NULL_CAMERA);
}

void DisableCamera(FSCamera iCamera) {
	if (iCamera == NULL_CAMERA) {
		return;
	}

	int iClient = iCamera.Client;
	if (Client_IsValid(iClient) && IsClientInGame(iClient)) {
		int iViewControl = EntRefToEntIndex(iCamera.ViewControl);
		if (IsValidEntity(iViewControl)) {
			AcceptEntityInput(iViewControl, "Disable");
		}

		SetEntityFlags(iClient, GetEntityFlags(iClient) & ~(FL_FROZEN | FL_ATCONTROLS));

		int hViewEntity = GetEntPropEnt(iClient, Prop_Data, "m_hViewEntity");
		if (IsValidEntity(hViewEntity) && HasEntProp(hViewEntity, Prop_Data, "m_hPlayer") && GetEntPropEnt(hViewEntity, Prop_Data, "m_hPlayer")  != iClient) {
			SetEntPropEnt(hViewEntity, Prop_Data, "m_hPlayer", iClient);
			AcceptEntityInput(hViewEntity, "Disable");
		}

		if (g_hAlpha.FloatValue > 1.0) {
			SetEntityRenderMode(iClient, RENDER_TRANSALPHA);
			int iR, iG, iB, iA;
			GetEntityRenderColor(iClient, iR, iG, iB, iA);
			SetEntityRenderColor(iClient, iR, iG, iB, 255);
		}
	}

	int iEntiy = EntRefToEntIndex(iCamera.Entity);
	if (IsValidEntity(iEntiy)) {
		Entity_Kill(iEntiy, true);
	}
	
	iCamera.Entity = INVALID_ENT_REFERENCE;
	iCamera.ViewControl = INVALID_ENT_REFERENCE;
}

void DisableForesight(FSCamera iCamera) {
	g_hCameras.Erase(g_hCameras.FindValue(iCamera));
	DisableCamera(iCamera);
	FSCamera.Destroy(iCamera);

	int iClient = iCamera.Client;
	Client_SetObserverTarget(iClient, -1);
	Client_SetObserverMode(iClient, OBS_MODE_NONE);
	SetEntityMoveType(iClient, MOVETYPE_WALK);

	g_iActiveCamera[iClient] = NULL_CAMERA;
	Client_SetHideHud(iClient, 0);

	PrintHintText(iClient, " ");
	StopSound(iClient, SNDCHAN_STATIC, "ui/hint.wav");
}
