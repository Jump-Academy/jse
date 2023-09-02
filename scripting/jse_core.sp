#pragma semicolon 1
#pragma newdecls required

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.3.5"

#define DATA_FOLDER "data/jse"

#define SND_REACH_CONTROL_POINT		"misc/freeze_cam.wav"

#include <sourcemod>
#include <sdktools>
#include <regex>
#include <sdkhooks>
#include <smlib/arrays>
#include <smlib/clients>
#include <smlib/entities>
#include <tf2>
#include <tf2_stocks>
#include <multicolors>
#include <tf2items>
#include <jse_core>

#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL	"http://jumpacademy.tf/plugins/jse/core/updatefile.txt"

ConVar g_hCVBlockSounds;
ConVar g_hCVBlockFXBlood;
ConVar g_hCVBlockFXExplosions;
ConVar g_hCVBlockFXShake;
ConVar g_hCVBlockFallDamage;

ConVar g_hCVRegenHP;
ConVar g_hCVRegenAmmo;
ConVar g_hCVRegenCaber;
ConVar g_hCVRegenShield;
ConVar g_hCVRegenHype;

ConVar g_hCVInstantRespawn;

ConVar g_hCVCapInterval;
ConVar g_hCVCriticals;
ConVar g_hCVEasyBuild;
ConVar g_hCVSentryAmmo;
ConVar g_hCVTeleporters;
ConVar g_hCVResetScore;

Handle g_hSDKResetScores;
Handle g_hSDKGetMaxClip1;
Handle g_hSDKFinishUpgrading;
Handle g_hSDKFinishBuilding;

Handle g_hCaptureForward;

ArrayList g_hBlockSounds;

StringMap g_hControlPoints;

bool g_bBlockEquip[MAXPLAYERS + 1];
bool g_bBlockRegen[MAXPLAYERS + 1];

bool g_bAmmoRegen[MAXPLAYERS + 1];

int g_iLastCapture[MAXPLAYERS + 1];
int g_iLastRegen[MAXPLAYERS + 1];
int g_iLastSpawn[MAXPLAYERS + 1];

int g_iObjectiveResource = INVALID_ENT_REFERENCE;

public Plugin myinfo = {
	name = "Jump Server Essentials - Core",
	author = PLUGIN_AUTHOR,
	description = "JSE core module for common jump server features",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int sErrMax) {
	RegPluginLibrary("jse_core");
	CreateNative("GetBlockEquip", Native_GetBlockEquip);
	CreateNative("GetBlockRegen", Native_GetBlockRegen);
	CreateNative("GetRegen", Native_GetRegen);
	CreateNative("SetBlockEquip", Native_SetBlockEquip);
	CreateNative("SetBlockRegen", Native_SetBlockRegen);
	CreateNative("SetRegen", Native_SetRegen);
	CreateNative("ClearControlPointCapture", Native_ClearControlPointCapture);
	CreateNative("ClearScore", Native_ClearScore);
}

public void OnPluginStart() {
	CreateConVar("jse_core_version", PLUGIN_VERSION, "Jump Server Essentials core version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	g_hCVBlockSounds = CreateConVar("jse_core_block_sounds", "regenerate, ammo_pickup, Pain, fallpain, vo/announcer, stickybomblauncher_det, wpn_denyselect", "Sounds to block", FCVAR_NONE);
	g_hCVBlockFXBlood = CreateConVar("jse_core_block_blood", "1", "Block blood effects", FCVAR_NONE);
	g_hCVBlockFXExplosions = CreateConVar("jse_core_block_explosions", "1", "Block explosion effects", FCVAR_NONE);
	g_hCVBlockFXShake = CreateConVar("jse_core_block_shake", "1", "Block screen shake effects", FCVAR_NONE);
	g_hCVBlockFallDamage = CreateConVar("jse_core_block_falldamage", "1", "Block fall damage", FCVAR_NONE, true, 0.0, true, 1.0);

	g_hCVRegenHP = CreateConVar("jse_core_regen_hp", "1", "Toggles per-tick health regen", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCVRegenAmmo = CreateConVar("jse_core_regen_ammo", "1", "Toggles global per-tick ammo regen", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCVRegenCaber = CreateConVar("jse_core_regen_caber", "1", "Toggles global Ullapool Caber regeneration", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCVRegenShield = CreateConVar("jse_core_regen_shield", "2.5", "Shield charge regeneration time interval (0 for disable))", FCVAR_NOTIFY, true, 0.0);
	g_hCVRegenHype = CreateConVar("jse_core_regen_hype", "1", "Toggles scout hype regeneration", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_hCVInstantRespawn = CreateConVar("jse_core_instant_respawn", "3", "Minimum seconds between instant respawns (-1 to disable instant respawn)", FCVAR_NONE, true, -1.0, true, 30.0);

	g_hCVCapInterval = CreateConVar("jse_core_cap_interval", "5", "Minimum time between control point captures in seconds", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCVCriticals = CreateConVar("jse_core_criticals", "0", "Toggles weapon criticals", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCVEasyBuild = CreateConVar("jse_core_easybuild", "1", "Toggles engineer building fast and cheap build", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCVSentryAmmo = CreateConVar("jse_core_sentryammo", "1", "Toggles engineer sentry ammo auto refill", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCVTeleporters = CreateConVar("jse_core_teleporters", "0", "Toggles allowing engineers to build teleporters", FCVAR_NONE, true, 0.0, true, 1.0);

	g_hCVResetScore = CreateConVar("jse_core_reset_score", "1", "Toggles clearing player scoreboard points upon /restart", FCVAR_NONE, true, 0.0, true, 1.0);

	RegConsoleCmd("sm_ammo", cmdAmmo, "Toggles ammo and weapon clip regeneration");
	RegConsoleCmd("sm_regen", cmdAmmo, "Toggles ammo and weapon clip regeneration");

	g_hBlockSounds = new ArrayList(128);

	g_hControlPoints = new StringMap();

	AddNormalSoundHook(Hook_NormalSound);

	if (g_hCVBlockFXBlood.BoolValue) {
		AddTempEntHook("TFBlood", Hook_TempEnt);
	}

	if (g_hCVBlockFXExplosions.BoolValue) {
		AddTempEntHook("TFExplosion", Hook_TempEnt);
		AddTempEntHook("TFParticleEffect", Hook_TempEntParticle);
	}

	if (g_hCVBlockFXShake.BoolValue) {
		HookUserMessage(GetUserMessageId("Shake"), Hook_UserMessageShake, true);
	}

	char sFilePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), DATA_FOLDER);
	if (!FileExists(sFilePath)) {
		CreateDirectory(sFilePath, 0x775);
	}

	HookEvent("player_builtobject", Event_BuiltObject);
	HookEvent("player_carryobject", Event_CarryObject);
	HookEvent("player_upgradedobject", Event_UpgradedObject);

	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Pre);
	HookEvent("player_spawn", Event_EquipWeapon);

	HookEvent("player_changeclass", Event_EquipWeapon);
	HookEvent("player_changeclass", Event_PlayerChangeClass);
	HookEvent("post_inventory_application", Event_EquipWeapon, EventHookMode_Pre);
	HookEvent("teamplay_round_start", Event_RoundStart);

	if (g_hCVResetScore.IntValue) {
		BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "gamedata/jse.scores.txt");
		if(FileExists(sFilePath)) {
			Handle hGameConf = LoadGameConfigFile("jse.scores");
			if(hGameConf != INVALID_HANDLE ) {
				StartPrepSDKCall(SDKCall_Player);
				PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CTFPlayer::ResetScores");
				g_hSDKResetScores = EndPrepSDKCall();
				CloseHandle(hGameConf);
			}
		}

		if (g_hSDKResetScores == null) {
			LogError("Failed to load jse.scores gamedata.  Setting jse_core_reset_score to 0");
			g_hCVResetScore.IntValue = 0;
		}
	}

	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "gamedata/jse.regen.txt");
	if(FileExists(sFilePath)) {
		Handle hGameConf = LoadGameConfigFile("jse.regen");
		if(hGameConf != INVALID_HANDLE ) {
			StartPrepSDKCall(SDKCall_Entity);
			PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CTFWeaponBase::GetMaxClip1");
			PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_ByValue);
			g_hSDKGetMaxClip1 = EndPrepSDKCall();

			CloseHandle(hGameConf);
		}

		if (g_hSDKGetMaxClip1 == null) {
			LogError("Failed to load jse.regen gamedata.  Weapon clip regen will not be available.");
			g_hCVRegenAmmo.IntValue = 0;
		}
	}

	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "gamedata/jse.buildings.txt");
	if(FileExists(sFilePath)) {
		Handle hGameConf = LoadGameConfigFile("jse.buildings");
		if(hGameConf != INVALID_HANDLE ) {
			StartPrepSDKCall(SDKCall_Entity);
			PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseObject::FinishUpgrading");
			g_hSDKFinishUpgrading = EndPrepSDKCall();

			StartPrepSDKCall(SDKCall_Entity);
			PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CBaseObject::FinishedBuilding");
			g_hSDKFinishBuilding = EndPrepSDKCall();

			CloseHandle(hGameConf);
		}

		if (g_hSDKFinishUpgrading == null || g_hSDKFinishBuilding == null) {
			LogError("Failed to load jse.buildings gamedata.  Instant building and upgrades will not be available.");
		}
	}

	g_hCaptureForward = CreateGlobalForward("OnCapPointCapture", ET_Single, Param_Cell, Param_Cell, Param_Cell, Param_String, Param_String);

	LoadTranslations("common.phrases");
}

public void OnPluginEnd() {
	for (int i = 1; i <= MaxClients; i++) {
		ClearScore(i);
	}
}

public void OnConfigsExecuted() {
	g_hBlockSounds.Clear();

	char sSounds[128];
	g_hCVBlockSounds.GetString(sSounds, sizeof(sSounds));
	char sBuffer[32][32];
	int iSounds = ExplodeString(sSounds, ",", sBuffer, sizeof(sBuffer), sizeof(sBuffer[]));

	for (int i = 0; i < iSounds; i++) {
		TrimString(sBuffer[i]);
		g_hBlockSounds.PushString(sBuffer[i]);
	}

	FindConVar("tf_weapon_criticals").IntValue = g_hCVCriticals.IntValue;
	FindConVar("tf_fastbuild").IntValue = g_hCVEasyBuild.IntValue;
	FindConVar("tf_cheapobjects").IntValue = g_hCVEasyBuild.IntValue;
}

public void OnClientPutInServer(int iClient) {
	SDKHook(iClient, SDKHook_OnTakeDamage, Hook_TakeDamage);

	g_iLastCapture[iClient] = 0;
	g_iLastRegen[iClient] = 0;
	g_iLastSpawn[iClient] = 0;

	g_bBlockEquip[iClient] = false;
	g_bBlockRegen[iClient] = false;

	g_bAmmoRegen[iClient] = false;
}

public void OnEntityCreated(int iEntity, const char[] sClassName) {
	if (!g_hCVTeleporters.BoolValue && StrEqual(sClassName, "obj_teleporter")) {
		SDKHook(iEntity, SDKHook_Spawn, Hook_KillOnSpawn);
	}
}

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			SDKHook(i, SDKHook_OnTakeDamage, Hook_TakeDamage);
			//SDKHook(i, SDKHook_TraceAttack, Hook_OnTraceAttack);

			g_iLastCapture[i] = 0;
			g_iLastRegen[i] = 0;
			g_iLastSpawn[i] = 0;

			g_bBlockEquip[i] = false;
			g_bBlockRegen[i] = false;

			g_bAmmoRegen[i] = false;

		} 
	}

	if (g_hCVSentryAmmo.BoolValue) {
		CreateTimer(5.0, Timer_BuildingRegen, 0, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}

	CreateTimer(0.1, Timer_AmmoRegen, 0, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	if (g_hCVRegenShield.FloatValue > 0.0) {
		CreateTimer(g_hCVRegenShield.FloatValue, Timer_ShieldRegen, 0, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}

	Setup();
	PrecacheSounds();

	FindConVar("mp_waitingforplayers_time").IntValue = 0;
	FindConVar("mp_respawnwavetime").IntValue = 0;
}

public void OnMapEnd() {
	g_hControlPoints.Clear();
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float fVel[3], float fAng[3], int &iWeapon) {
	if (!IsClientInGame(iClient)) {
		return Plugin_Continue;
	}

	if (g_hCVRegenHP.BoolValue) {
		int iMaxHealth = Entity_GetMaxHealth(iClient);
		if (Entity_GetHealth(iClient) < iMaxHealth) {
			Entity_SetHealth(iClient, iMaxHealth);
		}
	}

	return Plugin_Continue;
}

// Custom callbacks

public Action Event_BuiltObject(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iEntity = hEvent.GetInt("index");
	SetEntProp(iEntity, Prop_Send, "m_iUpgradeMetalRequired", 0);
	//SetEntPropFloat(iEntity, Prop_Send, "m_flPercentageConstructed", 0.0);

	if (g_hSDKFinishBuilding != null) {
		RequestFrame(FrameCallback_FinishBuilding, iEntity);
	}

	SDKHook(iEntity, SDKHook_Touch, Hook_BuildingTouch);
}

public Action Event_CarryObject(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iEntity = hEvent.GetInt("index");
	SetEntProp(iEntity, Prop_Send, "m_iUpgradeLevel", GetEntProp(iEntity, Prop_Send, "m_iHighestUpgradeLevel"));
}

public Action Event_UpgradedObject(Event hEvent, const char[] sName, bool bDontBroadcast) {
	if (g_hSDKFinishUpgrading != null) {
		int iEntity = hEvent.GetInt("index");
		RequestFrame(FrameCallback_FinishUpgrading, iEntity);
	}
	return Plugin_Continue;
}

public Action Event_EquipWeapon(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!iClient) {
		return Plugin_Handled;
	}

	if (g_bBlockEquip[iClient]) {
		return Plugin_Handled;
	}

	if (TF2_GetPlayerClass(iClient) == TFClass_Scout && g_hCVRegenHype.BoolValue) {
		int iWeapon = GetPlayerWeaponSlot(iClient, 0);
		if (iWeapon != -1) {
			char sClassName[32];
			GetEdictClassname(iWeapon, sClassName, sizeof(sClassName));

			if (StrEqual(sClassName, "tf_weapon_soda_popper")) {
				SetEntPropFloat(iClient, Prop_Send, "m_flHypeMeter", view_as<float>(0x7F800000)); // +Infinity hype
			} else {
				SetEntPropFloat(iClient, Prop_Send, "m_flHypeMeter", 0.0); // No hype
			}
		}
	}

	return Plugin_Continue;
}

public Action Event_PlayerChangeClass(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!iClient) {
		return Plugin_Handled;
	}

	ClearControlPointCapture(iClient);

	TF2_RespawnPlayer(iClient);

	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!iClient) {
		return Plugin_Handled;
	}

	if (g_hCVInstantRespawn.IntValue != -1) {
		float iRespawnTime = Math_Min(g_hCVInstantRespawn.FloatValue - (GetTime() - g_iLastSpawn[iClient]), 0.1);
		CreateTimer(iRespawnTime, Timer_Respawn, GetClientSerial(iClient), TIMER_FLAG_NO_MAPCHANGE);
	}

	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!iClient) {
		return Plugin_Handled;
	}

	g_iLastSpawn[iClient] = GetTime();

	return Plugin_Continue;
}

public Action Event_RoundStart(Event hEvent, const char[] sName, bool bDontBroadcast) {
	Setup();
}

public void FrameCallback_FinishBuilding(any iEntity) {
	SDKCall(g_hSDKFinishBuilding, iEntity);

	SetVariantInt(Entity_GetMaxHealth(iEntity));
	AcceptEntityInput(iEntity, "SetHealth");

}

public void FrameCallback_FinishUpgrading(any iEntity) {
	SDKCall(g_hSDKFinishUpgrading, iEntity);
}

public Action Hook_BuildingTouch(int iEntity, int iOther) {
	return Plugin_Handled;
}

public Action Hook_KillOnSpawn(int iEntity) {
	AcceptEntityInput(iEntity, "Kill");
	return Plugin_Handled;
}

public Action Hook_NormalSound(int iClients[64], int &iNumClients, char sSound[PLATFORM_MAX_PATH], int &iEnt, int &iChannel, float &fVolume, int &iLevel, int &iPitch, int &iFlags) {
	for (int i = 0; i < g_hBlockSounds.Length; i++) {
		static char sBuffer[64];
		g_hBlockSounds.GetString(i, sBuffer, sizeof(sBuffer));
		if (StrContains(sSound, sBuffer) != -1) {
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action Hook_TakeDamage(int iClient, int &iAttacker, int &iInflictor, float &fDamage, int &iDamageType) {
	if (iDamageType & DMG_FALL && g_hCVBlockFallDamage.BoolValue) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Hook_TempEnt(const char[] sTEName, const int[] iPlayers, int iNumClients, float fDelay) {
	return Plugin_Handled;
}

public Action Hook_TempEntParticle(const char[] sTEName, const int[] iPlayers, int iNumClients, float fDelay) {
	// 1137: drg_cow_explosioncore_normal
	// 1146: drg_cow_explosioncore_charged
	// 1152: drg_cow_explosioncore_charged_blue
	// 1153: drg_cow_explosioncore_normal_blue
	switch (TE_ReadNum("m_iParticleSystemIndex")) {
		case 1137, 1146, 1152, 1153: {
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action Hook_TouchCaptureArea(int iEntity, int iClient) {
	if (Client_IsValid(iClient)) {

		char sCapName[128];
		char sCapPrintName[128];
		GetEntPropString(iEntity, Prop_Data, "m_iszCapPointName", sCapName, sizeof(sCapName));

		int iTime = GetTime();

		int iControlPointData[MAXPLAYERS + 1];

		if ((iTime - g_iLastCapture[iClient] > g_hCVCapInterval.IntValue) && g_hControlPoints.GetArray(sCapName, iControlPointData, sizeof(iControlPointData)) && !iControlPointData[iClient]) {
			int iTeam = GetClientTeam(iClient);

			int iControlPointEntity = EntRefToEntIndex(iControlPointData[0]);
			int iPointIndex = -1;
			if (IsValidEntity(iControlPointEntity)) {
				GetEntPropString(iControlPointEntity, Prop_Data, "m_iszPrintName", sCapPrintName, sizeof(sCapPrintName));
				iPointIndex = GetEntProp(iControlPointEntity, Prop_Data, "m_iPointIndex");
			} else {
				strcopy(sCapPrintName, sizeof(sCapPrintName), sCapName);
			}

			int iResult = CAP_NORMAL;
			Call_StartForward(g_hCaptureForward);
			Call_PushCell(iClient);
			Call_PushCell(iControlPointEntity);
			Call_PushCell(iEntity);
			Call_PushString(sCapName);
			Call_PushString(sCapPrintName);
			Call_Finish(iResult);

			if (iResult) {
				iControlPointData[iClient] = 1;
				g_hControlPoints.SetArray(sCapName, iControlPointData, sizeof(iControlPointData));

				if (iResult & CAP_EVENT) {
					// Manually construct event to avoid announcer sqwawk

					Event hEvent = CreateEvent("teamplay_point_captured");
					hEvent.SetInt("cp", iPointIndex);
					hEvent.SetString("cpname", sCapPrintName);
					hEvent.SetInt("team", iTeam & 0xFF);

					char sCappers[2];
					sCappers[0] = iClient;

					hEvent.SetString("cappers", sCappers);
					hEvent.Fire();
				}

				if (iResult & CAP_SND_CHEER) {
					char sSound[PLATFORM_MAX_PATH];
					char sClass[10];
					TFClassType iClass = TF2_GetPlayerClass(iClient);
					TF2_GetClassName(iClass, sClass, sizeof(sClass));
					int iRand = GetRandomInt(1, 3);
					FormatEx(sSound, sizeof(sSound), "/vo/%s_autocappedcontrolpoint0%d.mp3", sClass, iRand);

					float fPos[3];
					GetClientEyePosition(iClient, fPos);
					EmitSoundToClient(iClient, sSound);
					EmitSoundToAll(sSound, SOUND_FROM_WORLD, SNDCHAN_VOICE, SNDLEVEL_NORMAL,  SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, fPos);
				}

				if (iResult & CAP_SND_BROADCAST) {
					EmitSoundToAll(SND_REACH_CONTROL_POINT, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.4);
				}
			}

			g_iLastCapture[iClient] = iTime;
		}

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Hook_TouchFuncRegenerate(int iEntity, int iClient) {
	if (Client_IsValid(iClient)) {
		if (g_bBlockEquip[iClient]) {
			int iGameTime = GetTime();
			if ((iGameTime - g_iLastRegen[iClient]) >= 3) {
				RegenWeapons(iClient, true);
				g_iLastRegen[iClient] = iGameTime;
			}

			return Plugin_Handled;
		}

		if (TF2_GetPlayerClass(iClient) == TFClass_Soldier) {
			int iWeapon1 = GetPlayerWeaponSlot(iClient, TFWeaponSlot_Primary);
			if (iWeapon1 != -1 && GetItemDefIndex(iWeapon1) == 730 && GetEntProp(iWeapon1, Prop_Send, "m_iClip1")) {
				if (g_bAmmoRegen[iClient] && GetEntProp(iWeapon1, Prop_Send, "m_iConsecutiveShots") == 1 && GetEntProp(iWeapon1, Prop_Send, "m_iReloadMode")) {
					int iMaxClip1 = SDKCall(g_hSDKGetMaxClip1, iWeapon1);
					SetEntProp(iWeapon1, Prop_Send, "m_iClip1", iMaxClip1);
				}

				return Plugin_Handled;
			}
		}
	}

	return Plugin_Continue;
}

public Action Hook_UserMessageShake(UserMsg iMsgID, BfRead hMsg, const int[] iPlayers, int iPlayersNum, bool bReliable, bool bInit) {
	return Plugin_Handled;
}

public Action Timer_AmmoRegen(Handle hTimer) {
	bool bRegenAmmo = g_hCVRegenAmmo.BoolValue;
	bool bRegenCaber = g_hCVRegenCaber.BoolValue;

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && (bRegenAmmo || g_bAmmoRegen[i]) && !g_bBlockRegen[i]) {
			RegenWeapons(i);
		}
	}

	if (bRegenCaber) {
		int iEntity = -1;
		while ((iEntity = FindEntityByClassname(iEntity, "tf_weapon_stickbomb")) != INVALID_ENT_REFERENCE) {
			SetEntProp(iEntity, Prop_Send, "m_bBroken", 0);
			SetEntProp(iEntity, Prop_Send, "m_iDetonated", 0);
		}
	}

	return Plugin_Continue;
}

public Action Timer_ShieldRegen(Handle hTimer) {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && TF2_GetPlayerClass(i) == TFClass_DemoMan) {
			SetEntPropFloat(i, Prop_Send, "m_flChargeMeter", 100.0);
		}
	}

	return Plugin_Continue;
}

public Action Timer_BuildingRegen(Handle hTimer) {
	int iEntity = -1;
	while ((iEntity = FindEntityByClassname(iEntity, "obj_sentrygun")) != INVALID_ENT_REFERENCE) {
		SetEntProp(iEntity, Prop_Send, "m_iAmmoShells", 200);
		SetEntProp(iEntity, Prop_Send, "m_iAmmoRockets", 20);
	}

	return Plugin_Continue;
}

public Action Timer_Respawn(Handle hTimer, any aData) {
	int iClient = GetClientFromSerial(aData);
	if (iClient && TF2_GetClientTeam(iClient) > TFTeam_Spectator && !IsPlayerAlive(iClient)) {
		TF2_RespawnPlayer(iClient);
	}

	return Plugin_Handled;
}

// Natives

public int Native_GetBlockEquip(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);
	return g_bBlockEquip[iClient];
}

public int Native_GetBlockRegen(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);
	return g_bBlockRegen[iClient];
}

public int Native_GetRegen(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);
	return g_bAmmoRegen[iClient];
}

public int Native_SetBlockEquip(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);
	bool bEnabled = GetNativeCell(2);
	g_bBlockEquip[iClient] = bEnabled;
}

public int Native_SetBlockRegen(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);
	bool bEnabled = GetNativeCell(2);
	g_bBlockRegen[iClient] = bEnabled;
}

public int Native_SetRegen(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);
	bool bEnabled = GetNativeCell(2);
	g_bAmmoRegen[iClient] = bEnabled;
}

public int Native_ClearControlPointCapture(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);

	char sCapName[128];
	int iControlPointData[MAXPLAYERS + 1];

	StringMapSnapshot hSnap = g_hControlPoints.Snapshot();
	for (int i = 0; i < hSnap.Length; i++) {
		hSnap.GetKey(i, sCapName, sizeof(sCapName));

		g_hControlPoints.GetArray(sCapName, iControlPointData, sizeof(iControlPointData));
		iControlPointData[iClient] = 0;
		g_hControlPoints.SetArray(sCapName, iControlPointData, sizeof(iControlPointData));
	}
	delete hSnap;
}

public int Native_ClearScore(Handle hPlugin, int iArgC) {
	int iClient = GetNativeCell(1);

	if (IsClientInGame(iClient)) {
		SDKCall(g_hSDKResetScores, iClient);
	}
}

// Commands

public Action cmdAmmo(int iClient, int iArgC) {
	if (g_bBlockEquip[iClient] || g_bBlockRegen[iClient]) {
		CReplyToCommand(iClient, "{dodgerblue}[jse] {white}%t", "No Access");
		return Plugin_Handled;
	}

	g_bAmmoRegen[iClient] = !g_bAmmoRegen[iClient];

	CReplyToCommand(iClient, "{dodgerblue}[jse] {white}%s ammo and clip regeneration.", g_bAmmoRegen[iClient] ? "Enabled" : "Disabled");

	return Plugin_Handled;
}

// Helpers
/*
bool checkSpawned(int iClient) {
	TFClassType iClass = TF2_GetPlayerClass(iClient);
	TFTeam iTFTeam = TF2_GetClientTeam(iClient);

	if (iTFTeam <= TFTeam_Spectator || iClass == TFClass_Unknown) {
		CReplyToCommand(iClient, "{dodgerblue}[jse] {white}You must be spawned to use this command.");
		return false;
	}

	return true;
}
*/

void PrecacheSounds() {
	char sSound[PLATFORM_MAX_PATH];
	char sClass[10];
	for (int i = 1; i < 10; i++) {
		TF2_GetClassName(view_as<TFClassType>(i), sClass, sizeof(sClass));
		FormatEx(sSound, sizeof(sSound), "/vo/%s_autocappedcontrolpoint01.mp3", sClass);
		PrecacheSound(sSound);
		FormatEx(sSound, sizeof(sSound), "/vo/%s_autocappedcontrolpoint02.mp3", sClass);
		PrecacheSound(sSound);
		FormatEx(sSound, sizeof(sSound), "/vo/%s_autocappedcontrolpoint03.mp3", sClass);
		PrecacheSound(sSound);
	}

	PrecacheSound(SND_REACH_CONTROL_POINT);
}

void RegenWeapons(int iClient, bool bForce=false) {
	int iWeapon1 = GetPlayerWeaponSlot(iClient, TFWeaponSlot_Primary);
	if (iWeapon1 != -1) {
		int iAmmoType1 = GetEntProp(iWeapon1, Prop_Data, "m_iPrimaryAmmoType");
		GivePlayerAmmo(iClient, 500, iAmmoType1, true);

		// Ignore Beggar's Bazooka
		if ((g_bAmmoRegen[iClient] || bForce) && GetItemDefIndex(iWeapon1) != 730) {
			int iMaxClip = SDKCall(g_hSDKGetMaxClip1, iWeapon1);
			SetEntProp(iWeapon1, Prop_Send, "m_iClip1", iMaxClip);

			SetEntPropFloat(iWeapon1, Prop_Send, "m_flEnergy", 100.0);
		}
	}

	int iWeapon2 = GetPlayerWeaponSlot(iClient, TFWeaponSlot_Secondary);
	if (iWeapon2 != -1) {
		int iAmmoType2 = GetEntProp(iWeapon2, Prop_Data, "m_iPrimaryAmmoType");
		GivePlayerAmmo(iClient, 500, iAmmoType2, true);

		if (g_bAmmoRegen[iClient] || bForce) {
			int iMaxClip = SDKCall(g_hSDKGetMaxClip1, iWeapon2);
			SetEntProp(iWeapon2, Prop_Send, "m_iClip1", iMaxClip);

			SetEntPropFloat(iWeapon2, Prop_Send, "m_flEnergy", 100.0);
		}
	}
}

void Setup() {
	g_hControlPoints.Clear();

	int iControlPointData[MAXPLAYERS + 1];

	char sCapName[128];
	int iEntity = INVALID_ENT_REFERENCE;
	while ((iEntity = FindEntityByClassname(iEntity, "team_control_point")) != INVALID_ENT_REFERENCE) {
		iControlPointData[0] = EntIndexToEntRef(iEntity); // Save ent index

		Entity_GetName(iEntity, sCapName, sizeof(sCapName));
		g_hControlPoints.SetArray(sCapName, iControlPointData, sizeof(iControlPointData));
	}

	iEntity = INVALID_ENT_REFERENCE;
	while ((iEntity = FindEntityByClassname(iEntity, "trigger_capture_area")) != INVALID_ENT_REFERENCE) {
		SDKHook(iEntity, SDKHook_StartTouch, Hook_TouchCaptureArea);
		SDKHook(iEntity, SDKHook_Touch, Hook_TouchCaptureArea);

		SetVariantString("2 0");
		AcceptEntityInput(iEntity, "SetTeamCanCap");

		SetVariantString("3 0");
		AcceptEntityInput(iEntity, "SetTeamCanCap");

		GetEntPropString(iEntity, Prop_Data, "m_iszCapPointName", sCapName, sizeof(sCapName));
		if (!g_hControlPoints.GetArray(sCapName, iControlPointData, sizeof(iControlPointData))) {
			iControlPointData[0] = -1;
			g_hControlPoints.SetArray(sCapName, iControlPointData, sizeof(iControlPointData));
		}
	}

	iEntity = INVALID_ENT_REFERENCE;
	while ((iEntity = FindEntityByClassname(iEntity, "func_regenerate")) != INVALID_ENT_REFERENCE) {
		SDKHook(iEntity, SDKHook_Touch, Hook_TouchFuncRegenerate);
	}

	if ((g_iObjectiveResource = FindEntityByClassname(iEntity, "tf_objective_resource")) != INVALID_ENT_REFERENCE) {
		for (int i = 0; i < 8; i++) {
			SetEntProp(g_iObjectiveResource, Prop_Data, "m_bCPIsVisible", 0, 4, i);
		}
	}
}

// Stock

stock int GetItemDefIndex(int iItem) {
	return GetEntProp(iItem, Prop_Send, "m_iItemDefinitionIndex");
}

stock void TF2_GetClassName(TFClassType iClass, char[] sName, int iLength) {
  static char sClass[10][10] = {"unknown", "scout", "sniper", "soldier", "demoman", "medic", "heavy", "pyro", "spy", "engineer"};
  strcopy(sName, iLength, sClass[view_as<int>(iClass)]);
}
