#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.1"

#include <sourcemod>
#include <sdktools>
#include <jse_tracker>

int g_iScore[MAXPLAYERS + 1];

Handle g_hSDKResetScores = null;

public Plugin myinfo = 
{
	name = "Jump Server Essentials - Scoreboard",
	author = PLUGIN_AUTHOR,
	description = "JSE map progression scoreboard component",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart()
{
	AddCommandListener(CommandListener_Restart, "sm_restart");
	
	HookEvent("teamplay_round_start", Hook_RoundStart);
	HookEvent("player_team", Hook_ChangeTeamClass);
	HookEvent("player_changeclass", Hook_ChangeTeamClass);
	
	char sFilePath[PLATFORM_MAX_PATH];
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
		SetFailState("Failed to load jse.scores gamedata");
	}

	// Late load
	if (GetClientCount(true) && IsTrackerLoaded()) {
		for (int i = 1; i <= MaxClients; i++) {
			g_iScore[i] = ComputeScore(i);
			AddScore(i, g_iScore[i]);
		}
	}
}

public void OnPluginEnd() {
	ResetAllClients();
}

public void OnMapEnd() {
	ResetAllClients();
}

public void OnClientDisconnect(int iClient) {
	g_iScore[iClient] = 0;
}

// Custom callbacks

public Action CommandListener_Restart(int iClient, const char[] sCommand, int iArgC) {
	ResetClient(iClient);
	ResetPlayerProgress(iClient);
}

public Action Hook_ChangeTeamClass(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	ResetClient(iClient);
	
	return Plugin_Continue;
}

public Action Hook_RoundStart(Event hEvent, const char[] sName, bool bDontBroadcast) {
	ResetAllClients();
}

public void OnCheckpointReached(int iClient, Course iCourse, Jump iJump, ControlPoint iControlPoint) {
	if (iControlPoint || (iJump && iJump.iNumber > 1)) {
		g_iScore[iClient]++;
		AddScore(iClient, 1);
	}
}

// Helpers

void ResetAllClients() {
	for (int i = 1; i <= MaxClients; i++) {
		ResetClient(i);
	}
}

void ResetClient(int iClient) {
	if (IsClientInGame(iClient)) {
		ResetScore(iClient);
	}
	
	g_iScore[iClient] = 0;
}

void AddScore(int iClient, int iScore) {
	if (iScore) {
		Event hEvent = CreateEvent("player_escort_score", true);
		hEvent.SetInt("player", iClient);
		hEvent.SetInt("points", iScore);
		FireEvent(hEvent);
		
		int iEntity = CreateEntityByName("game_score");
		if (IsValidEntity(iEntity)) {
			SetEntProp(iEntity, Prop_Data, "m_Score", 2 * iScore);
			DispatchSpawn(iEntity);
			AcceptEntityInput(iEntity, "ApplyScore", iClient, iEntity);
			AcceptEntityInput(iEntity, "Kill");
		}
	}
}

int ComputeScore(int iClient) {
	ArrayList hProgress = new ArrayList(sizeof(Checkpoint));
	GetPlayerProgress(iClient, hProgress);

	int iScore = 0;
	for (int i=0; i<hProgress.Length; i++) {
		Jump iJump = hProgress.Get(i, Checkpoint::iJump);
		if (!iJump || iJump.iNumber > 1) {
			iScore++;
		}
	}

	delete hProgress;

	return iScore;
}

void ResetScore(int iClient) {
	int iEntity = CreateEntityByName("game_score");
	if (IsValidEntity(iEntity)) {
		SetEntProp(iEntity, Prop_Data, "m_Score", -2 * g_iScore[iClient]);
		DispatchSpawn(iEntity);
		AcceptEntityInput(iEntity, "ApplyScore", iClient, iEntity);
		AcceptEntityInput(iEntity, "Kill");
	}
	
	SDKCall(g_hSDKResetScores, iClient);
}
