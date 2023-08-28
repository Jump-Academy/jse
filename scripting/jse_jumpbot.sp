#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR	"AI"
#define PLUGIN_VERSION	"1.0.0-rc5"

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <clientprefs>

#include <autoexecconfig>
#include <botcontroller>
#include <multicolors>
#include <sha1>
#include <smlib/arrays>
#include <smlib/clients>
#include <tf2attributes>
#include <tf2items>
#include <socket>

#include <jse_jumpbot>

#undef REQUIRE_PLUGIN
#include <updater>
#include <jse_core>
#include <jse_showkeys>
#include <jse_autosave>
#include <octree>

#pragma newdecls required

enum struct ClientState {
	float fPos[3];
	float fAng[3];
	int iButtons;
	int iLastUpdate;
}

enum struct RecEnt {
	int iID;
	int iRef;
	int iType;
	int iMoveType;
	int iOwner;
	int iAssign;
	int iDesyncs;
	float fPosPrev[3];
	float fAngPrev[3];
	float fPosNext[3];
	float fAngNext[3];
}

enum struct RecBot {
	int iEnt;
	DataPack hEquip;
	float fPosPrev[3];
	float fAngPrev[3];
	float fPosNext[3];
	float fAngNext[3];
}

enum struct Bubble {
	int iEnt;
	int iTime;
}

enum struct Queue {
	int iClient;
	Recording iRecording;
	float fTime;
	TFTeam iTeam;
	Obs_Mode iObsMode;
}

enum struct SpawnFreeze {
	int iFrames;
	TFTeam iTeam;
	TFClassType iClass;
	float fPos[3];
	float fAng[3];
}

#define UPDATE_URL		"http://jumpacademy.tf/plugins/jse/jumpbot/updatefile.txt"
#define API_HOST		"api.jumpacademy.tf"

#define REC_FORMAT_VERSION_MAJOR	1
#define REC_FORMAT_VERSION_MINOR	0

#define INST_NOP				 0
#define INST_PAUSE				 1
#define INST_RECD				(1 << 1)
#define INST_PLAY				(1 << 2)
#define INST_PLAYALL			(1 << 3)
#define INST_REWIND				(1 << 4)
#define INST_WARMUP				(1 << 5)
#define INST_RETURN				(1 << 6)
#define INST_WAIT				(1 << 7)
#define INST_SPEC				(1 << 8)

#define MAX_NEARBY_SEARCH_DISTANCE	1000.0
#define MAX_TARGET_FOLLOW_DISTANCE	4000.0

#define MAX_REC_DESYNCS		3

#define WARMUP_FRAMES_DEFAULT	66
#define RESPAWN_FREEZE_FRAMES	66 // 1 second

#define JSE_FOLDER				"data/jse"
#define RECORD_FOLDER			"data/jse/jumpbot"
#define TRASH_FOLDER 			"data/jse/jumpbot/.trash"
#define CACHE_FOLDER 			"data/jse/jumpbot/.cache"

#define HINT_MODEL_MARKER		"models/extras/info_speech.mdl"
#define HINT_MODEL_ROCKET		"models/weapons/w_models/w_rocket.mdl"
#define HINT_MODEL_STICKY		"models/weapons/w_models/w_stickybomb.mdl"
#define TRAIL_MATERIAL_LASER	"sprites/laser.vmt"
#define TRAIL_MATERIAL_HALO		"sprites/halo01.vmt"

#define POSITIVE_INFINITY	view_as<float>(0x7F800000)
#define NEGATIVE_INFINITY	view_as<float>(0xFF800000)

enum FindResult {
	NO_RECORDING,
	NO_NEARBY_RECORDING,
	NO_CLASS_RECORDING,
	FOUND_RECORDING
}

enum RecBlockType {
	FRAME 						= 1,
	CLIENT 						= 2,
	ENTITY 						= 3
}

ConVar g_hBotName;
ConVar g_hBotNameAuthors;
ConVar g_hBotImmunity;
ConVar g_hDebug;
ConVar g_hOutline;

ConVar g_hTrail;
ConVar g_hTrailColor;
ConVar g_hProjTrail;
ConVar g_hProjTrailColor;
ConVar g_hTrailLife;

ConVar g_hVacate;

ConVar g_hBubble;
ConVar g_hBotCallSign;
ConVar g_hBotCallSignShort;
ConVar g_hBotOptionsShort;
ConVar g_hBotCallKey;
ConVar g_hBotCallCooldown;

ConVar g_hBotMaxError;
ConVar g_hShowMeDefault;
ConVar g_hBotJoinExecute;
ConVar g_hAllowMedic;
ConVar g_hRobot;
ConVar g_hFOV;

ConVar g_hRewindWaitFrames;

ConVar g_hLocalRecColor;

ConVar g_hUseRepo;
ConVar g_hCacheExpire;

ConVar g_hInteractive;

Handle g_hCookieBubble;
Handle g_hCookieTrail;
Handle g_hCookieInteract;
Handle g_hCookieSpeed;
Handle g_hCookiePerspective;

bool g_bSocketExtension;

int g_iClientInstruction;
int g_iClientInstructionPost;
int g_iClientOfInterest;
int g_iClientFollow;
int g_iTargetFollow;

ArrayList g_hRecordings;
Recording g_iRecording;
ArrayList g_hPlaybackQueue;
Octree g_iSpatialIdx;

#include "jse_jumpbot_rec.sp"

bool g_bShuttingDown;
bool g_bLocked;
bool g_bPlayerGrantAccess[MAXPLAYERS+1];

char g_sRecSubDir[32];

ArrayList g_hRecordingBots;
ArrayList g_hRecordingClients;
ArrayList g_hRecordingEntities;
ArrayList g_hRecordingEntTypes;
int g_iRecordingEntTotal;

#include "jse_jumpbot_repo.sp"

ArrayList g_hRecBuffer;
int g_iRecBufferIdx;
int g_iRecBufferUsed;
int g_iRecBufferFrame;

float g_fPlaybackSpeed;
int g_iInterFrameIdx;
int g_iInterFrameLength;

int g_iWarmupFrames;

ArrayList g_hRecBufferFrames;
int g_iRewindWaitFrames;
int g_iStateLoadLast;

ClientState g_eClientState[MAXPLAYERS+1];

SpawnFreeze g_eSpawnFreeze[MAXPLAYERS+1];
StringMap g_hProjMap;
ArrayList g_hSpecList;
int g_iTrailLaser;
int g_iTrailHalo;

ArrayList g_hQueue;
Panel g_hQueuePanel[MAXPLAYERS+1] = {null, ...};
Handle g_hQueueTimer;

ArrayList g_hVisibleRecordings;
ArrayList g_hLastVisibleRecordings;

StringMap g_hBubbleLookup;
Bubble g_eLastBubbleTime[MAXPLAYERS+1];
int g_iCallKeyMask;
char g_sCallKeyLabel[16];

int g_iLastCaller;
int g_iLastCallTime;

bool g_bCoreAvailable;
bool g_bShowKeysAvailable;
bool g_bOctreeAvailable;

int g_iProjTrailColor[4];
int g_iTrailColor[4];
int g_iLocalRecColor[3];
float g_fTrailLife;

bool g_bBubble[MAXPLAYERS + 1] = {true, ...};
bool g_bTrail[MAXPLAYERS + 1] = {true, ...};
bool g_bInteract[MAXPLAYERS + 1] =  { true, ... };
float g_fSpeed[MAXPLAYERS + 1] = {1.0, ...};
int g_iPerspective[MAXPLAYERS + 1] = {1, ...};

Handle g_hSDKGetMaxClip1;

GlobalForward g_hClientRestoreForward;

public Plugin myinfo = {
	name = "Jump Server Essentials - JumpBot",
	author = PLUGIN_AUTHOR,
	description = "JSE jump skills tutorial and replay bot",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

//////// Built-in forwards ////////

public void OnPluginStart() {
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetFile("jse_jumpbot");
	
	g_hBotName 				= AutoExecConfig_CreateConVar("jse_jb_name", 			"JumpBOT", 			"JumpBOT default name", 																FCVAR_NONE												);
	g_hBotNameAuthors		= AutoExecConfig_CreateConVar("jse_jb_name_authors",	"0",	 			"Rename bot as the recorder during playback", 																FCVAR_NONE,							true, 0.0, true, 1.0);
	g_hBotImmunity			= AutoExecConfig_CreateConVar("jse_jb_immunity", 		"90",	 			"Bot immunity level", 																FCVAR_NONE												);
	g_hDebug				= AutoExecConfig_CreateConVar("jse_jb_debug", 			"0", 				"Toggle debug mode", 																	FCVAR_DONTRECORD, 					true, 0.0, true, 1.0);
	
	g_hOutline	 			= AutoExecConfig_CreateConVar("jse_jb_outline", 		"1", 				"Toggle JumpBOT glow outline", 															FCVAR_NONE, 						true, 0.0, true, 1.0);
	g_hTrail 				= AutoExecConfig_CreateConVar("jse_jb_trail", 			"1", 				"Toggle JumpBOT path trail", 															FCVAR_NONE, 						true, 0.0, true, 1.0);
	g_hTrailLife 			= AutoExecConfig_CreateConVar("jse_jb_trailtime", 		"5.0",				"Bot trail visible duration", 															FCVAR_NONE,							true, 0.0, true, 25.6);
	g_hTrailColor	 		= AutoExecConfig_CreateConVar("jse_jb_trailcolor", 		"1E90FFFF",			"Bot travel path trail color (hex RGBA)", 												FCVAR_NONE												);

	g_hProjTrail 			= AutoExecConfig_CreateConVar("jse_jb_projtrail", 		"1", 				"Toggle projectile trail", 																FCVAR_NONE, 						true, 0.0, true, 1.0);
	g_hProjTrailColor		= AutoExecConfig_CreateConVar("jse_jb_projcolor", 		"800080FF", 		"Bot launched projectiles trail color (hex RGBA)", 										FCVAR_NONE												);

	g_hVacate 				= AutoExecConfig_CreateConVar("jse_jb_vacate", 			"1", 				"Vacate when the server becomes empty", 												FCVAR_NONE, 						true, 0.0, true, 1.0);
	
	g_hBubble 				= AutoExecConfig_CreateConVar("jse_jb_bubble", 			"1", 				"Toggle showing JumpBOT recording bubbles", 											FCVAR_NONE, 						true, 0.0, true, 1.0);
	g_hBotCallSign			= AutoExecConfig_CreateConVar("jse_jb_callsign", 		"jumpbot", 			"JumpBOT call sign, showme alternative", 												FCVAR_NONE												);
	g_hBotCallSignShort		= AutoExecConfig_CreateConVar("jse_jb_callsign_short", 	"jb", 				"JumpBOT short call sign, showme alternative", 											FCVAR_NONE												);
	g_hBotOptionsShort		= AutoExecConfig_CreateConVar("jse_jb_options_short", 	"jbo", 				"JumpBOT short options, jb_options alternative", 										FCVAR_NONE												);
	g_hBotCallKey 			= AutoExecConfig_CreateConVar("jse_jb_callkey", 		"3", 				"JumpBOT call key (0:disable, 1:+reload, 2:+attack2, 3:+attack3 (default), 4:+use)", 	FCVAR_NONE, 						true, 0.0, true, 4.0);
	g_hBotCallCooldown		= AutoExecConfig_CreateConVar("jse_jb_call_cooldown", 	"5", 				"JumpBOT call cooldown from the same player (seconds)", 								FCVAR_NONE, 						true, 0.0			);
	
	g_hBotMaxError 			= AutoExecConfig_CreateConVar("jse_jb_maxerr", 			"50.0", 			"Bot max interpolation error before teleport correction", 								FCVAR_NONE, 						true, 0.0, false	);
	g_hShowMeDefault 		= AutoExecConfig_CreateConVar("jse_jb_showme_default", 	"1", 				"Showme perspective default (0:none, 1:fp, 3:tp)", 										FCVAR_NONE, 						true, 0.0, true, 3.0);
	g_hBotJoinExecute	 	= AutoExecConfig_CreateConVar("jse_jb_joinexecute", 	"", 				"Commands bots should execute after joining the server", 								FCVAR_NONE												);
	g_hAllowMedic 			= AutoExecConfig_CreateConVar("jse_jb_allow_medic", 	"1", 				"Allow medics to call for other bot classes", 											FCVAR_NONE, 						true, 0.0, true, 1.0);
	g_hRobot 				= AutoExecConfig_CreateConVar("jse_jb_robot", 			"1", 				"Use robot model for bot", 																FCVAR_NONE, 						true, 0.0, true, 1.0);
	g_hFOV 					= AutoExecConfig_CreateConVar("jse_jb_fov", 			"90",		 		"Set the bot to use this field of view", 												FCVAR_NONE												);
	
	g_hRewindWaitFrames		= AutoExecConfig_CreateConVar("jse_jb_rewind_wait", 	"11",		 		"Number of frames to block recorder movement after rewind or state load",				FCVAR_NONE, 						true, 0.0			);

	g_hLocalRecColor		= AutoExecConfig_CreateConVar("jse_jb_localreccolor", 	"00FF00", 			"Local recording bubble color (hex RGB)", 												FCVAR_NONE												);
	
	g_hUseRepo 				= AutoExecConfig_CreateConVar("jse_jb_repository", 		"1", 				"Fetch recordings from repository", 													FCVAR_NONE, 						true, 0.0, true, 1.0);
	g_hCacheExpire	 		= AutoExecConfig_CreateConVar("jse_jb_cache_expire",	"5", 				"Days to keep unused cached recordings", 												FCVAR_NONE, 						true, 0.0			);
	
	g_hInteractive 			= AutoExecConfig_CreateConVar("jse_jb_interactive", 	"1", 				"Toggles interactive follower mode (0:disable, 1:follow caller, 2:follow any nearby)",	FCVAR_NONE, 						true, 0.0, true, 2.0);
	
	ConVar hPluginVersion	= AutoExecConfig_CreateConVar("jse_jb_version", 		PLUGIN_VERSION, 	"JumpBOT plugin version", 																FCVAR_NOTIFY | FCVAR_DONTRECORD							);
	hPluginVersion.SetString(PLUGIN_VERSION);
	
	AutoExecConfig_ExecuteFile();
	
	// Commands
	RegConsoleCmd(	"jb_record", 		cmdRecord, 							"Start recording movement into the buffer"							);
	RegConsoleCmd(	"jb_play", 			cmdPlay, 							"Start playback of movement from the buffer on the control client"	);
	RegConsoleCmd(	"jb_save", 			cmdSave, 							"Save the last recording to disk"									);
	RegAdminCmd(	"jb_delete", 		cmdDelete, 			ADMFLAG_BAN,	"Remove the specified recording ID"									);
	RegAdminCmd(	"jb_clearcache", 	cmdClearCache, 		ADMFLAG_ROOT, 	"Clear the recording cache"											);
	RegAdminCmd(	"jb_upgrade", 		cmdUpgrade, 		ADMFLAG_ROOT, 	"Perform plugin upgrade operations"									);
	
	RegAdminCmd(	"jb_grant", 		cmdGrantAccess, 	ADMFLAG_BAN, 	"Grant recorder access to a player"									);
	RegAdminCmd(	"jb_revoke", 		cmdRevokeAccess, 	ADMFLAG_BAN, 	"Revoke recorder access from a player"								);
	
	RegConsoleCmd(	"jb_lock", 			cmdToggleLock, 						"Toggle showme lock"												);
	RegConsoleCmd(	"jb_load", 			cmdLoad, 							"Force recording recache from disk"									);
	RegConsoleCmd(	"jb_playall", 		cmdPlayAll, 						"Load and play all recordings from disk"							);
	RegConsoleCmd(	"jb_stop", 			cmdStop, 							"Terminate the currently running operation"							);

	RegConsoleCmd(	"jb_pause", 		cmdPause, 							"Pause recording or playback"										);
	RegConsoleCmd(	"jb_skip", 			cmdSkip,							"Skips to a recording frame"										);
	RegConsoleCmd(	"jb_skiptime", 		cmdSkipTime,						"Skips to a recording timestamp"										);

	RegConsoleCmd(	"jb_rewind", 		cmdRewind, 							"Rewind to an earlier frame of the recording"						);
	RegConsoleCmd(	"jb_state_load", 	cmdStateLoad, 						"Load recording state"												);
	RegConsoleCmd(	"jb_state_loadlast",cmdStateLoadLast,					"Load last recording state"											);
	RegConsoleCmd(	"jb_state_save", 	cmdStateSave, 						"Save recording state"												);
	RegConsoleCmd(	"jb_state_delete", 	cmdStateDelete,						"Delete recording state"											);
	//RegConsoleCmd(	"jb_trim", 			cmdTrim, 							"Trim a recording"													);
	
	RegConsoleCmd(	"jb_list", 			cmdList, 							"List all recordings"												);
	RegConsoleCmd(	"jb_nearby", 		cmdNearby, 							"List nearby recordings"											);
	RegConsoleCmd(	"jb_chdir", 		cmdChdir, 							"Set local recording subdirectory"									);
	
	RegAdminCmd(	"show", 			cmdShow, 			ADMFLAG_GENERIC,"Play a recording nearby for the indicated client"					);
	
	char sBuffer[MAX_NAME_LENGTH];
	g_hBotCallSign.GetString(sBuffer, sizeof(sBuffer));
	RegConsoleCmd(sBuffer,				cmdShowMe, 							"Play a recording nearby the client"								);
	g_hBotCallSignShort.GetString(sBuffer, sizeof(sBuffer));
	RegConsoleCmd(sBuffer, 				cmdShowMe, 							"Play a recording nearby the client"								);
	RegConsoleCmd("showme", 			cmdShowMe, 							"Play a recording nearby the client"								);
	
	g_hBotOptionsShort.GetString(sBuffer, sizeof(sBuffer));
	RegConsoleCmd(sBuffer, 				cmdOptions,							"Change user options"												);
	RegConsoleCmd("jb_options", 		cmdOptions,							"Change user options"												);
	
	// Cookies
	g_hCookieBubble			= RegClientCookie("jse_jb_bubble", 		"Set bot bubble visibility",	 		CookieAccess_Private);
	g_hCookieTrail			= RegClientCookie("jse_jb_trail",		"Set bot trail visibility", 			CookieAccess_Private);
	g_hCookieInteract		= RegClientCookie("jse_jb_interact",	"Set bot interactivity with client",	CookieAccess_Private);
	g_hCookieSpeed			= RegClientCookie("jse_jb_speed",		"Set bot playback speed", 				CookieAccess_Private);
	g_hCookiePerspective	= RegClientCookie("jse_jb_perspective",	"Set bot playback perspective", 		CookieAccess_Private);
	
	g_hBotName.GetString(sBuffer, sizeof(sBuffer));
	SetCookieMenuItem(CookieMenuHandler_Options, 0, sBuffer);
	
	g_hRecBuffer = new ArrayList();
	g_iRecording = NULL_RECORDING;
	g_hRecordings = new ArrayList();
	g_hPlaybackQueue = new ArrayList();

	g_hVisibleRecordings = new ArrayList();
	g_hLastVisibleRecordings = new ArrayList();

	g_hBubbleLookup = new StringMap();
	g_hProjMap = new StringMap();
	g_hSpecList = new ArrayList();
	g_bLocked = false;
	g_hQueue = new ArrayList(sizeof(Queue));
	
	g_hRecordingClients = new ArrayList();
	g_hRecordingEntities = new ArrayList(sizeof(RecEnt));
	g_hRecordingEntTypes = new ArrayList(ByteCountToCells(128));
	g_hRecordingBots = new ArrayList(sizeof(RecBot));
	g_hRecBufferFrames = null;

	strcopy(g_sRecSubDir, sizeof(g_sRecSubDir), RECORD_FOLDER);
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_changeclass", Event_PlayerSpawn);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
	HookEvent("teamplay_round_start", Event_RoundStart);
	HookUserMessage(GetUserMessageId("VoiceSubtitle"), UserMessage_VoiceSubtitle, true);
	AddNormalSoundHook(Hook_NormalSound);
	
	LoadTranslations("core.phrases");
	LoadTranslations("common.phrases");
	LoadTranslations("jse_jumpbot.phrases");
	
	g_hClientRestoreForward = new GlobalForward("OnPostPlaybackClientRestore", ET_Ignore, Param_Cell);

	if (LibraryExists("updater")) {
		Updater_AddPlugin(UPDATE_URL);
	}
	
	// For manual late plugin load
	if (GetGameTime() > 5.0 && GetClientCount() > 0) {
		SetupBot();
		SetupQueue();
		
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i) && AreClientCookiesCached(i)) {
				OnClientCookiesCached(i);
			}
		}
	}
	
	ConVar hHUDHint = FindConVar("sv_hudhint_sound");
	if (hHUDHint != null) {
		hHUDHint.BoolValue = false;
	}
	
	g_bShuttingDown = false;
	
	char sFilePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "gamedata/jse.regen.txt");
	if (FileExists(sFilePath)) {
		Handle hGameConf = LoadGameConfigFile("jse.regen");
		if (hGameConf != INVALID_HANDLE ) {
			StartPrepSDKCall(SDKCall_Entity);
			PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "CTFWeaponBase::GetMaxClip1");
			PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_ByValue);
			g_hSDKGetMaxClip1 = EndPrepSDKCall();
			
			delete hGameConf;
		}
		
		if (g_hSDKGetMaxClip1 == null) {
			LogError("Failed to load jse.regen gamedata.  Weapon clip regen may not be accurate.");
		}
	}
}

public void OnPluginEnd() {
	RemoveAllModels();
	
	g_iRecording = NULL_RECORDING;
	g_hBubbleLookup.Clear();
	g_bShuttingDown = true;
	
	if (g_iClientOfInterest != -1 && g_iClientInstruction & INST_PLAY) {
		doReturn();
	}
	
	for (int i=0; i<g_hRecordingBots.Length; i++) {
		int iClient = g_hRecordingBots.Get(i, RecBot::iEnt);
		KickClient(iClient, "%t", "Punt Bot");
	}

	if (g_bOctreeAvailable) {
		Octree.Destroy(g_iSpatialIdx);
	}
}

public void OnLibraryAdded(const char[] sName) {
	if (StrEqual(sName, "jse_core")) {
		g_bCoreAvailable = true;
	} else if (StrEqual(sName, "jse_showkeys")) {
		g_bShowKeysAvailable = true;
	} else if (StrEqual(sName, "octree")) {
		g_bOctreeAvailable = true;
		CreateSpatialIndex();
	} else if (StrEqual(sName, "updater")) {
		Updater_AddPlugin(UPDATE_URL);
	} else if (StrEqual(sName, "socket.ext")) {
		g_bSocketExtension = true;
	}
}

public void OnLibraryRemoved(const char[] sName) {
	if (StrEqual(sName, "jse_core")) {
		g_bCoreAvailable = false;
	} else if (StrEqual(sName, "jse_showkeys")) {
		g_bShowKeysAvailable = false;
	} else if (StrEqual(sName, "octree")) {
		g_bOctreeAvailable = false;
		g_iSpatialIdx = NULL_OCTREE;
	}
}

public void OnAllPluginsLoaded() {
	g_bSocketExtension = GetExtensionFileStatus("socket.ext") == 1;

	g_bCoreAvailable = LibraryExists("jse_core");
	g_bShowKeysAvailable = LibraryExists("jse_showkeys");
	g_bOctreeAvailable = LibraryExists("octree");
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int sErrMax) {
	RegPluginLibrary("jse_jumpbot");
	CreateNative("JSE_JB_Shutdown", Native_Shutdown);
	CreateNative("JSE_JB_LoadRecordings", Native_LoadRecordings);
	CreateNative("JSE_JB_GetRecordings", Native_GetRecordings);
	CreateNative("JSE_JB_PlayRecording", Native_PlayRecording);
	CreateNative("JSE_JB_PlayRecordingQueueClient", Native_PlayRecordingQueueClient);

	ClientInfo_SetupNatives();
	Recording_SetupNatives();

	return APLRes_Success;
}

public void OnConfigsExecuted() {
	switch (g_hBotCallKey.IntValue) {
		case 0: {
			g_iCallKeyMask = 0;
			g_sCallKeyLabel[0] = '\0';
		}
		case 1: {
			g_iCallKeyMask = IN_RELOAD;
			strcopy(g_sCallKeyLabel, sizeof(g_sCallKeyLabel), "%+reload%");
		}
		case 2: {
			g_iCallKeyMask = IN_ATTACK2;
			strcopy(g_sCallKeyLabel, sizeof(g_sCallKeyLabel), "%+attack2%");
		}
		case 3: {
			g_iCallKeyMask = IN_ATTACK3;
			strcopy(g_sCallKeyLabel, sizeof(g_sCallKeyLabel), "%+attack3%");
		}
		case 4: {
			g_iCallKeyMask = IN_USE;
			strcopy(g_sCallKeyLabel, sizeof(g_sCallKeyLabel), "%+use%");
		}
	}
	
	char sColor[32];
	
	g_hTrailColor.GetString(sColor, sizeof(sColor));
	int iTrailColor = StringToInt(sColor, 16);
	g_iTrailColor[0] = (iTrailColor >> 24) & 0xFF;
	g_iTrailColor[1] = (iTrailColor >> 16) & 0xFF;
	g_iTrailColor[2] = (iTrailColor >>  8) & 0xFF;
	g_iTrailColor[3] = (iTrailColor      ) & 0xFF;
	
	g_hProjTrailColor.GetString(sColor, sizeof(sColor));
	int iProjColor = StringToInt(sColor, 16);
	g_iProjTrailColor[0] = (iProjColor >> 24) & 0xFF;
	g_iProjTrailColor[1] = (iProjColor >> 16) & 0xFF;
	g_iProjTrailColor[2] = (iProjColor >>  8) & 0xFF;
	g_iProjTrailColor[3] = (iProjColor      ) & 0xFF;
	
	g_hLocalRecColor.GetString(sColor, sizeof(sColor));
	int iLocalRecColor = StringToInt(sColor, 16);
	g_iLocalRecColor[0] = (iLocalRecColor >> 16) & 0xFF;
	g_iLocalRecColor[1] = (iLocalRecColor >>  8) & 0xFF;
	g_iLocalRecColor[2] = (iLocalRecColor      ) & 0xFF;

	g_fTrailLife = g_hTrailLife.FloatValue;
}

public void OnEntityCreated(int iEntity, const char[] sClassName) {
	if (StrContains(sClassName, "tf_projectile_") == 0) {
		if (StrEqual(sClassName[14], "rocket")) {
			SDKHook(iEntity, SDKHook_SpawnPost, Hook_RocketSpawn);
		} else {
			SDKHook(iEntity, SDKHook_SpawnPost, Hook_ProjectileSpawn);
		}
	}
	/*
	else if (StrEqual(sClassName, "instanced_scripted_scene") && g_hInteractive.IntValue) {
		SDKHook(iEntity, SDKHook_Spawn, Hook_SpawnTaunt);
	}
	*/
}

public void OnEntityDestroyed(int iEntity) {
	/*
	char sClassName[128];
	GetEntityClassname(iEntity, sClassName, sizeof(sClassName));
	PrintToServer("Entity %d (%s) destroyed", iEntity, sClassName);
	*/
	if (iEntity > 0 && IsValidEntity(iEntity)) {
		int iIdx = g_hRecordingEntities.FindValue(EntIndexToEntRef(iEntity), RecEnt::iRef);
		if (iIdx != -1) {
			if (g_iClientInstruction & INST_PAUSE) {
				// Do lookup since destroyed entities have owner entity field set as -1
				CloneProjectile(iEntity, g_hRecordingEntities.Get(iIdx, RecEnt::iOwner));
			}

			g_hRecordingEntities.Erase(iIdx);
		}
	}
}

public void OnMapStart() {
	g_bShuttingDown = false;
	
	g_iClientInstruction = view_as<int>(INST_NOP);
	g_iClientOfInterest = -1;
	g_iClientFollow = -1;
	g_iTargetFollow = -1;
	g_iLastCaller = -1;
	g_iLastCallTime = 0;

	g_hRecBuffer.Clear();
	g_iRecBufferIdx = 0;
	g_iRecBufferUsed = 0;
	g_iRecBufferFrame = 0;

	g_iStateLoadLast = -1;

	g_iRecording = NULL_RECORDING;
	g_iWarmupFrames = 2 * WARMUP_FRAMES_DEFAULT;
	
	g_iTrailLaser = PrecacheModel(TRAIL_MATERIAL_LASER);
	g_iTrailHalo = PrecacheModel(TRAIL_MATERIAL_HALO);
	PrecacheModel(HINT_MODEL_MARKER);
	PrecacheModel(HINT_MODEL_ROCKET);
	PrecacheModel(HINT_MODEL_STICKY);
	
	char sModel[64];
	char sClassName[10];
	for (int i=1; i<10; i++) {
		TFClassType iClass = view_as<TFClassType>(i);
		if (iClass == TFClass_DemoMan) {
			strcopy(sClassName, sizeof(sClassName), "demo"); // MvM model uses demo for short
		} else {
			TF2_GetClassName(iClass, sClassName, sizeof(sClassName));
		}
		
		Format(sModel, sizeof(sModel), "models/bots/%s/bot_%s.mdl", sClassName, sClassName);
		PrecacheModel(sModel);
	}
	
	char sCacheFolder[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sCacheFolder, sizeof(sCacheFolder), JSE_FOLDER);
	if (!DirExists(sCacheFolder)) {
		CreateDirectory(sCacheFolder, 509); // Octal 775
	}
	
	// Clear expired or empty cache files
	BuildPath(Path_SM, sCacheFolder, sizeof(sCacheFolder), CACHE_FOLDER);
	if (DirExists(sCacheFolder)) {
		int iTimeNow = GetTime();
		DirectoryListing hDir = OpenDirectory(sCacheFolder);
		char sFileName[PLATFORM_MAX_PATH];
		char sFilePath[PLATFORM_MAX_PATH];
		FileType iFileType;
		while (hDir.GetNext(sFileName, sizeof(sFileName), iFileType)) {
			BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "%s/%s", CACHE_FOLDER, sFileName);
			int iTime = GetFileTime(sFilePath, FileTime_LastAccess);
			if (iTimeNow-iTime > 24*3600 * g_hCacheExpire.IntValue || !FileSize(sFilePath)) {
				DeleteFile(sFilePath);
			}
		}
		delete hDir;
	} else {
		CreateDirectory(sCacheFolder, 509); // Octal 775
	}
	
	CreateTimer(0.1, Timer_AmmoRegen, 0, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	
	LoadRecordings();
	blockFlags();
	blockRegen();
}

public void OnMapEnd() {
	doFullStop();
	g_iClientOfInterest = -1;
	
	g_hBubbleLookup.Clear();
	g_hProjMap.Clear();
	g_hSpecList.Clear();
	doPlayerQueueClear();
	g_hPlaybackQueue.Clear();
	ClearRecordings(g_hRecordings);
	g_hRecordingClients.Clear();
	ClearRecEntities();
	g_hRecordingEntTypes.Clear();
	g_iRecordingEntTotal = 0;
	ClearRecBotData();
	if (g_hRecBufferFrames != null) {
		g_hRecBufferFrames.Clear();
	}
	
	Array_Fill(g_bPlayerGrantAccess, sizeof(g_bPlayerGrantAccess), false);
	
	if (g_hQueueTimer != null) {
		delete g_hQueueTimer;
	}
	
	for (int i = 1; i <= MaxClients; i++) {
		if (g_hQueuePanel[i] != null) {
			delete g_hQueuePanel[i];
		}
	}
	
	g_bLocked = false;
}

public void OnGameFrame() {
	if (g_iClientInstruction == INST_RECD) {
		if (!g_hRecordingClients.Length) {
			doFullStop();
			return;
		}

		if (g_iRecBufferFrame % 10 == 0) {
			char sFrameInfo[64];
			char sTimeRec[32];
			
			ToTimeDisplay(sTimeRec, sizeof(sTimeRec), g_iRecBufferFrame/66);

			for (int i=0; i<g_hRecordingClients.Length; i++) {
				int iClient = g_hRecordingClients.Get(i);
			
				FormatEx(sFrameInfo, sizeof(sFrameInfo), "%T\n%T: %d\n%T: %s", "Recorder Active", iClient, "Frame", iClient, g_iRecBufferFrame, "Time", iClient, sTimeRec);
				Handle hBuffer = StartMessageOne("KeyHintText", g_iClientOfInterest);
				BfWriteByte(hBuffer, 1); // Channel
				BfWriteString(hBuffer, sFrameInfo);
				EndMessage();
			}
		}

		int iRecBufferIdxBackup  = g_iRecBufferIdx;

		g_hRecBufferFrames.Push(g_iRecBufferIdx);
		g_hRecBuffer.Push(view_as<int>(FRAME) | (g_iRecBufferFrame++ << 8));
		g_iRecBufferIdx++;

		static float fPos[3];
		static float fVel[3];
		static float fAng[3];

		for (int iRec=0; iRec<g_hRecordingClients.Length; iRec++) {
			int iClient = g_hRecordingClients.Get(iRec);

			Entity_GetAbsOrigin(iClient, fPos);
			Entity_GetAbsVelocity(iClient, fVel);
			GetClientEyeAngles(iClient, fAng);

			int iButtons = GetClientButtons(iClient);
			int iWeaponIndex = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
			for (int i=0; i<=5; i++) {
				if (GetPlayerWeaponSlot(iClient, i) == iWeaponIndex) {
					iButtons |= i << 26;
					break;
				}
			}

			g_hRecBuffer.Push(view_as<int>(CLIENT) | (iRec << 8));
			g_hRecBuffer.Push(fPos[0]);
			g_hRecBuffer.Push(fPos[1]);
			g_hRecBuffer.Push(fPos[2]);
			g_hRecBuffer.Push(fVel[0]);
			g_hRecBuffer.Push(fVel[1]);
			g_hRecBuffer.Push(fVel[2]);
			g_hRecBuffer.Push(fAng[0]);
			g_hRecBuffer.Push(fAng[1]);
			g_hRecBuffer.Push(fAng[2]);
			g_hRecBuffer.Push(iButtons);

			g_iRecBufferIdx += 11;
		}

		for (int i=0; i<g_hRecordingEntities.Length; i++) {
			RecEnt eRecEnt;
			g_hRecordingEntities.GetArray(i, eRecEnt);

			//PrintToServer("RecEnt[%d] with iRef=%d, iEnt=%d", i, iArr[RecEnt_iRef], EntRefToEntIndex(iArr[RecEnt_iRef]));

			int iEntity = EntRefToEntIndex(eRecEnt.iRef);

			int iOwner = g_hRecordingClients.FindValue(eRecEnt.iOwner);
			if (iOwner != -1 && iEntity != INVALID_ENT_REFERENCE) {
				g_hRecBuffer.Push(view_as<int>(ENTITY) | eRecEnt.iID << 8 | eRecEnt.iType << 16 | iOwner << 24);

				Entity_GetAbsOrigin(iEntity, fPos);
				Entity_GetAbsVelocity(iEntity, fVel);
				Entity_GetAbsAngles(iEntity, fAng);
				g_hRecBuffer.Push(fPos[0]);
				g_hRecBuffer.Push(fPos[1]);
				g_hRecBuffer.Push(fPos[2]);
				g_hRecBuffer.Push(fVel[0]);
				g_hRecBuffer.Push(fVel[1]);
				g_hRecBuffer.Push(fVel[2]);
				g_hRecBuffer.Push(fAng[0]);
				g_hRecBuffer.Push(fAng[1]);
				g_hRecBuffer.Push(fAng[2]);

				g_iRecBufferIdx += 10;
			}
			#if defined DEBUG
			else {
				PrintToServer("Entity %d has owner=%d, but owneridx=%d", iEntity, Entity_GetOwner(iEntity), iOwner);
			}
			#endif
		}

		if (g_iClientInstruction & INST_PAUSE) {
			g_iRecBufferIdx = iRecBufferIdxBackup;
		}

		g_iRecBufferUsed = g_iRecBufferIdx;
	} else if (g_iClientInstruction & (INST_WARMUP | INST_WAIT)) {
		ArrayList hClientInfo = g_iRecording.ClientInfo;

		for (int i=0; i<hClientInfo.Length; i++) {
			int iClient = g_hRecordingBots.Get(i, RecBot::iEnt);
			
			ClientInfo iClientInfo = hClientInfo.Get(i);

			float fPos[3];
			iClientInfo.GetStartPos(fPos);
			Entity_SetAbsOrigin(iClient, fPos);
			
			g_eClientState[iClient].iLastUpdate = GetGameTickCount();
		}

		if (g_iClientInstruction & INST_WARMUP && g_iRecBufferFrame++ > g_iWarmupFrames) {
			//g_iWarmupFrames = WARMUP_FRAMES_DEFAULT;
			g_iClientInstruction ^= INST_WARMUP;
			g_iClientInstruction |= INST_PLAY;
			g_iRecBufferIdx = 0;

			for (int i=0; i<hClientInfo.Length; i++) {
				int iClient = g_hRecordingBots.Get(i, RecBot::iEnt);

				for (int iSlot = TFWeaponSlot_Primary; iSlot <= TFWeaponSlot_Item2; iSlot++) {
					int iCurrentWeapon = GetPlayerWeaponSlot(iClient, iSlot);
					if (IsValidEntity(iCurrentWeapon)) {
						float fTime = GetGameTime();
						SetEntPropFloat(iCurrentWeapon, Prop_Send, "m_flNextPrimaryAttack", fTime);
						SetEntPropFloat(iCurrentWeapon, Prop_Send, "m_flNextSecondaryAttack", fTime);
					}
				}
			}

			SetPlaybackSpeedCOI();
		}
	} else if (g_iClientInstruction & (INST_PLAY | INST_REWIND)) {
		static float fPos[3];
		static float fPosNow[3];
		static float fVel[3];
		static float fAng[3];
		static int iButtons;

		if (g_iRecBufferIdx >= g_hRecBuffer.Length || (g_iRecBufferIdx >= g_iRecBufferUsed)) {
			ResetBubbleRotation(g_iRecording);
			ClearRecEntities();

			ArrayList hClientInfo = g_iRecording.ClientInfo;
			
			if (g_hPlaybackQueue.Length && g_iClientInstruction & INST_PLAYALL) {
				g_iRecording = g_hPlaybackQueue.Get(0);
				g_hPlaybackQueue.Erase(0);
				
				if (Client_IsValid(g_iClientOfInterest) && IsClientInGame(g_iClientOfInterest)) {
					g_fPlaybackSpeed = g_fSpeed[g_iClientOfInterest];
				} else {
					g_fPlaybackSpeed = 1.0;
				}

				char sFilePath[PLATFORM_MAX_PATH];
				g_iRecording.GetFilePath(sFilePath, sizeof(sFilePath));

				if (g_hDebug.BoolValue) {
					int iFilePart = FindCharInString(sFilePath, '/', true);
					CPrintToChatAll("{dodgerblue}[jb] {white}%t %d/%d: %s", "Load", g_hRecordings.Length - g_hPlaybackQueue.Length, g_hRecordings.Length, sFilePath[iFilePart+1]);
				}
				
				if (g_iRecording.Repo && !FileExists(sFilePath)) {
					g_iClientInstruction = INST_NOP | INST_PLAYALL;
					FetchRecording(g_iRecording);
				} else if (!LoadFrames(g_iRecording)) {
					if (g_hDebug.BoolValue)
						CPrintToChatAll("{dodgerblue}[jb] {white}%t", "Cannot File Read");
					g_iRecBufferIdx = 0;
					g_iRecording = NULL_RECORDING;
					return;
				}
				
				g_iRecBufferIdx = 0;

				for (int i=0; i<hClientInfo.Length; i++) {
					int iRecBot = g_hRecordingBots.Get(i, RecBot::iEnt);
					ClientInfo iClientInfo = hClientInfo.Get(i);

					TF2_SetPlayerClass(iRecBot, view_as<TFClassType>(iClientInfo.Class));
					if (g_hRobot.BoolValue) {
						setRobotModel(iRecBot);
					}

					// FIXME: Regen causes custom equip weapon drop
					//TF2_RegeneratePlayer(iClient);

					iClientInfo.GetStartPos(fPos);
					iClientInfo.GetStartAng(fAng);
					fAng[2] = 0.0;
					TeleportEntity(iRecBot, fPos, fAng, view_as<float>({0.0, 0.0, 0.0}));
				}

				return;
			}

			for (int i=0; i<hClientInfo.Length; i++) {
				int iRecBot = g_hRecordingBots.Get(i, RecBot::iEnt);

				g_eClientState[iRecBot].iButtons = 0; // Release all buttons
			}

			if (Client_IsValid(g_iClientOfInterest) && IsClientInGame(g_iClientOfInterest)) {
				PrintHintText(g_iClientOfInterest, " ");
				StopSound(g_iClientOfInterest, SNDCHAN_STATIC, "ui/hint.wav");
				CreateTimer(0.1, Timer_CloseHintPanel, g_iClientOfInterest, TIMER_FLAG_NO_MAPCHANGE);
				
				doReturn();
			}

			if (!(g_iClientInstruction & INST_RECD)) {
				doFullStop();
				findTargetFollow();

				if (g_hDebug.BoolValue) {
					CPrintToChatAll("{dodgerblue}[jb] {white}%t", "Playback Stop");
				}
			}

			if (g_iClientInstruction & INST_REWIND) {
				if (g_iRewindWaitFrames-- <= 0) {
					g_iClientInstruction &= ~INST_REWIND;
				}
			}

			return;
		}

		// Rotate bubble
		if (g_iRecording) {
			int iBubble = EntRefToEntIndex(g_iRecording.NodeModel);
			if (IsValidEntity(iBubble)) {
				// Avoid using TeleportEntity due to animation jitter due to entity parenting
				float fBubbleAng[3];
				GetEntPropVector(iBubble, Prop_Send, "m_angRotation", fBubbleAng);
				fBubbleAng[1] -= 10.0;
				SetEntPropVector(iBubble, Prop_Send, "m_angRotation", fBubbleAng);
			}
		}

		if (g_iInterFrameIdx == 0) {
			int iRecBufferIdxBackup = g_iRecBufferIdx;

			if (view_as<RecBlockType>(g_hRecBuffer.Get(g_iRecBufferIdx) & 0xFF) == FRAME) {
				g_iRecBufferFrame = g_hRecBuffer.Get(g_iRecBufferIdx) >> 8;
				g_iRecBufferIdx++;
				g_iInterFrameIdx = 0;
			} else {
				LogError("Cannot find start of frame at buffer index: %d", g_iRecBufferIdx);
				doFullStop();
				return;
			}

			for (int i=0; i<g_hRecordingEntities.Length; i++) {
				int iDesyncs = g_hRecordingEntities.Get(i, RecEnt::iDesyncs);
				g_hRecordingEntities.Set(i, iDesyncs+1, RecEnt::iDesyncs);
			}

			while (g_iRecBufferIdx < g_iRecBufferUsed && g_iRecBufferIdx < g_hRecBuffer.Length) {
				int iEntity = INVALID_ENT_REFERENCE;
				int iEntType;
				int iOwner = -1;
				int iBotID = -1;
				int iRecordingEnt = -1;

				RecBlockType iRecBlockType = view_as<RecBlockType>(g_hRecBuffer.Get(g_iRecBufferIdx) & 0xFF);
				switch (iRecBlockType) {
					case FRAME: {
						break;
					}
					case CLIENT: {
						if (g_iClientInstruction & INST_REWIND && g_iClientInstruction & INST_RECD) {
							iEntity = g_hRecordingClients.Get((g_hRecBuffer.Get(g_iRecBufferIdx++) >> 8) & 0xFF, RecBot::iEnt);
						} else {
							iBotID = (g_hRecBuffer.Get(g_iRecBufferIdx++) >> 8) & 0xFF;
							iEntity = g_hRecordingBots.Get(iBotID, RecBot::iEnt);
						}

						fPos[0] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fPos[1] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fPos[2] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fVel[0] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fVel[1] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fVel[2] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fAng[0] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fAng[1] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fAng[2] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						iButtons = g_hRecBuffer.Get(g_iRecBufferIdx++);

						if (g_iClientInstruction & INST_PAUSE) {
							iButtons &= ~(IN_ATTACK | IN_ATTACK2 | IN_ATTACK3);
						}

						g_eClientState[iEntity].iLastUpdate = GetGameTickCount();
						g_eClientState[iEntity].fAng = fAng;
						g_eClientState[iEntity].iButtons = iButtons; // & ~(7 << 26);

						if (g_iInterFrameLength > 1 && iBotID != -1) {
							RecBot eRecBot;
							g_hRecordingBots.GetArray(iBotID, eRecBot);
							
							eRecBot.fPosPrev = eRecBot.fPosNext;
							eRecBot.fAngPrev = eRecBot.fAngNext;

							eRecBot.fPosNext = fPos;
							eRecBot.fAngNext = fAng;

							g_hRecordingBots.SetArray(iBotID, eRecBot);
						}

						if (g_hTrail.BoolValue) {
							GetClientAbsOrigin(iEntity, fPosNow);
							if (GetVectorDistance(fPosNow, fPos) < 100.0) {
								float fEyePos[3];
								GetClientEyePosition(iEntity, fEyePos);
								float fZOffset = (fEyePos[2] - fPosNow[2])/2;

								fPosNow[2] += fZOffset;
								float fPosNext[3];
								fPosNext[0] = fPos[0];
								fPosNext[1] = fPos[1];
								fPosNext[2] = fPos[2] + fZOffset;

								TE_SetupBeamPoints(fPosNow, fPosNext, g_iTrailLaser, g_iTrailHalo, 0, 66, g_fTrailLife, 25.0, 25.0, 1, 1.0, g_iTrailColor, 0);
								TE_SendToAllInRangeVisible(fPos);
							}
						}
					}
					case ENTITY: {
						iRecordingEnt	= (g_hRecBuffer.Get(g_iRecBufferIdx  ) >>  8) & 0xFF;
						iEntType 		= (g_hRecBuffer.Get(g_iRecBufferIdx  ) >> 16) & 0xFF;
						iOwner			= (g_hRecBuffer.Get(g_iRecBufferIdx++) >> 24) & 0xFF;
						
						fPos[0] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fPos[1] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fPos[2] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fVel[0] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fVel[1] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fVel[2] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fAng[0] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fAng[1] = g_hRecBuffer.Get(g_iRecBufferIdx++);
						fAng[2] = g_hRecBuffer.Get(g_iRecBufferIdx++);

						int iRecEntIdx = g_hRecordingEntities.FindValue(iRecordingEnt, RecEnt::iAssign);
						if (iRecEntIdx == -1) {
							iEntity = INVALID_ENT_REFERENCE;
							int iOwnerEnt = g_hRecordingBots.Get(iOwner, RecBot::iEnt);

							// Find unassigned entity to associate
							for (int i=0; i<g_hRecordingEntities.Length; i++) {
								RecEnt eRecEnt;
								g_hRecordingEntities.GetArray(i, eRecEnt);

								if (eRecEnt.iAssign == -1 && eRecEnt.iOwner == iOwnerEnt && eRecEnt.iType == iEntType) {
									iRecEntIdx = i;

									iEntity = EntRefToEntIndex(eRecEnt.iRef);
									g_hRecordingEntities.Set(iRecEntIdx, iRecordingEnt, RecEnt::iAssign);
									g_hRecordingEntities.Set(iRecEntIdx, 0, RecEnt::iDesyncs);
									break;
								}
							}

							if (iRecEntIdx == -1) {
								RecEnt eRecEnt;
								eRecEnt.iID = g_iRecordingEntTotal++ % 256;
								eRecEnt.iRef = 0;
								eRecEnt.iType = iEntType;
								eRecEnt.iOwner = iOwnerEnt;
								eRecEnt.iAssign = iRecordingEnt;
								g_hRecordingEntities.PushArray(eRecEnt);
								iRecEntIdx = g_hRecordingEntities.Length -1;
							}
						} else {
							if (g_hRecordingEntities.Get(iRecEntIdx, RecEnt::iRef)) {
								g_hRecordingEntities.Set(iRecEntIdx, 0, RecEnt::iDesyncs);

								iEntity = EntRefToEntIndex(g_hRecordingEntities.Get(iRecEntIdx, RecEnt::iRef));
							} else {
								int iDesyncs = g_hRecordingEntities.Get(iRecEntIdx, RecEnt::iDesyncs);
								if (iDesyncs) {
									#if defined DEBUG
									char sClassName[64];
									g_hRecordingEntTypes.GetString(iEntType, sClassName, sizeof(sClassName));
									PrintToServer("Entity block for RecEnt[%d] has no assigned entity (%s) (%d)", iRecordingEnt, sClassName, iDesyncs);
									#endif

									if (iDesyncs >= MAX_REC_DESYNCS) {
										int iOwnerEnt = g_hRecordingBots.Get(iOwner, RecBot::iEnt);

										#if !defined DEBUG
										char sClassName[64];
										g_hRecordingEntTypes.GetString(iEntType, sClassName, sizeof(sClassName));
										#endif

										iEntity = CreateProjectile(sClassName, fPos, fAng, fVel, iOwnerEnt);
										if (IsValidEntity(iEntity)) {
											g_hRecordingEntities.Set(iRecEntIdx, EntIndexToEntRef(iEntity), RecEnt::iRef);
											g_hRecordingEntities.Set(iRecEntIdx, 0, RecEnt::iDesyncs);
											DispatchSpawn(iEntity);

											#if defined DEBUG
											PrintToServer("Respawned RecEnt[%d] (%s)", iRecordingEnt, sClassName);
											#endif
										}
									}
								}
							}
						}

						if (g_iInterFrameLength > 1) {
							RecEnt eRecEnt;
							g_hRecordingEntities.GetArray(iRecEntIdx, eRecEnt);

							eRecEnt.fPosPrev = eRecEnt.fPosNext;
							eRecEnt.fAngPrev = eRecEnt.fAngNext;

							eRecEnt.fPosNext = fPos;
							eRecEnt.fAngNext = fAng;

							g_hRecordingEntities.SetArray(iRecEntIdx, eRecEnt);
						}
					}
					#if defined DEBUG
					default: {
						PrintToServer("Buffer read: UNKNOWN");
					}
					#endif
				}

				if (iEntity == INVALID_ENT_REFERENCE || g_iInterFrameLength > 1) {
					continue;
				}

				Entity_GetAbsOrigin(iEntity, fPosNow);

				float fPosErr = GetVectorDistance(fPosNow, fPos);
				if (fPosErr > g_hBotMaxError.FloatValue) {
					if (iRecBlockType == CLIENT) {
						float fPosBump[3];
						fPosBump[0] = fPos[0];
						fPosBump[1] = fPos[1];
						fPosBump[2] = fPos[2] + 0.05;
						Handle hTr = TR_TraceRayFilterEx(fPosBump, view_as<float>({90.0, 0.0, 0.0}), MASK_SHOT_HULL, RayType_Infinite, traceHitNonPlayer, iEntity);
						if (TR_DidHit(hTr)) {
							float fPosAhead[3];
							TR_GetEndPosition(fPosAhead, hTr);

							if (GetVectorDistance(fPosBump, fPosAhead) < 0.05) {
								#if defined DEBUG
								PrintToServer("Prevented playback client teleport into ground (%1.f, %.1f, %.3f)", fPos[0], fPos[1], fPos[2]);
								#endif

								fPos[2] = fPosAhead[2];
							}
						}
						delete hTr;
					}

					Entity_SetAbsOrigin(iEntity, fPos);

					#if defined DEBUG
					PrintToServer("Position for %s[%d] exceeded max error (%.1f/%.1f)", iRecBlockType == CLIENT ? "iBotID" : "iRecEnt", iRecBlockType == CLIENT ? iBotID : iRecordingEnt, fPosErr, g_hBotMaxError.FloatValue);
					#endif
				} else {
					fVel[0] = (fPos[0]-fPosNow[0])*66;
					fVel[1] = (fPos[1]-fPosNow[1])*66;
					fVel[2] = (fPos[2]-fPosNow[2])*66;
				}

				TeleportEntity(iEntity, NULL_VECTOR, fAng, fVel);
			}
		
			for (int i=0; i<g_hRecordingEntities.Length; i++) {
				int iDesyncs = g_hRecordingEntities.Get(i, RecEnt::iDesyncs);
				if (iDesyncs) {
					int iEntity = g_hRecordingEntities.Get(i, RecEnt::iRef);
					if (!iEntity) {
						continue;
					}

					iEntity = EntRefToEntIndex(iEntity);
					if (IsValidEntity(iEntity)) {
						int iRecordingEnt = g_hRecordingEntities.Get(i, RecEnt::iAssign);
						if (iRecordingEnt == -1) {
							continue;
						}

						#if defined DEBUG
						char sClassName[64];
						GetEntityClassname(iEntity, sClassName, sizeof(sClassName));
						
						PrintToServer("Missing entity block for RecEnt[%d] (%s) (%d)", iRecordingEnt, sClassName, iDesyncs);	
						#endif

						if (iDesyncs >= MAX_REC_DESYNCS) {
							AcceptEntityInput(iEntity, "Kill");
							// Kill triggers OnEntityDestroyed immediately and removes from list
							i--;

							#if defined DEBUG
							PrintToServer("Pruned orphaned RecEnt[%d] (%s)", iRecordingEnt, sClassName);
							#endif
						}

					} else {
						g_hRecordingEntities.Erase(i--);
					}
				}
			
				if (g_iClientInstruction & INST_PAUSE) {
					g_iRecBufferIdx = iRecBufferIdxBackup;
				}

				if (g_iClientInstruction & INST_REWIND) {
					if (g_iRewindWaitFrames-- <= 0) {
						g_iClientInstruction &= ~INST_REWIND;
						/*
						for (int i=0; i<g_hRecordingClients.Length; i++) {
							int iRecClient = g_hRecordingClients.Get(i, RecBot::iEnt);
							SetEntityMoveType(iRecClient, MOVETYPE_WALK);
						}
						*/
					}
				}
			}
		}
		
		if (g_iInterFrameLength > 1) {
			float fAlpha = float(g_iInterFrameIdx) / g_iInterFrameLength;

			ArrayList hClientInfo = g_iRecording.ClientInfo;

			for (int i=0; i<hClientInfo.Length; i++) {
				RecBot eRecBot;
				g_hRecordingBots.GetArray(i, eRecBot);

				int iClient = eRecBot.iEnt;
				if (!IsClientInGame(iClient) || !IsPlayerAlive(iClient)) {
					continue;
				}

				InterpCoords(fAlpha, eRecBot.fPosPrev, eRecBot.fPosNext, fPos);
				InterpAngles(fAlpha, eRecBot.fAngPrev, eRecBot.fAngNext, fAng);

				g_eClientState[iClient].fAng = fAng;

				Entity_GetAbsOrigin(iClient, fPosNow);

				float fPosErr = GetVectorDistance(fPosNow, fPos);
				if (fPosErr > g_hBotMaxError.FloatValue) {
					TeleportEntity(iClient, fPos, fAng, NULL_VECTOR);
				} else {
					CalcCorrectionalVelocity(fPosNow, fPos, fVel);
					Entity_SetAbsVelocity(iClient, fVel);
				}
			}

			for (int i=0; i<g_hRecordingEntities.Length; i++) {
				RecEnt eRecEnt;
				g_hRecordingEntities.GetArray(i, eRecEnt);
				
				if (!eRecEnt.iRef || eRecEnt.iDesyncs) {
					continue;
				}

				int iEntity = EntRefToEntIndex(eRecEnt.iRef);
				if (!IsValidEntity(iEntity)) {
					continue;
				}

				InterpCoords(fAlpha, eRecEnt.fPosPrev, eRecEnt.fPosNext, fPos);
				InterpAngles(fAlpha, eRecEnt.fAngPrev, eRecEnt.fAngNext, fAng);

				Entity_GetAbsOrigin(iEntity, fPosNow);

				float fPosErr = GetVectorDistance(fPosNow, fPos);
				if (fPosErr > g_hBotMaxError.FloatValue) {
					TeleportEntity(iEntity, fPos, fAng, NULL_VECTOR);
				} else {
					CalcCorrectionalVelocity(fPosNow, fPos, fVel);

					TeleportEntity(iEntity, NULL_VECTOR, fAng, fVel);
				}
			}

			g_iInterFrameIdx = (g_iInterFrameIdx+1) % g_iInterFrameLength;
		}
	}
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float fVel[3], float fAng[3], int &iWeapon) {
	if (!IsClientInGame(iClient)) {
		return Plugin_Continue;
	}

	if (g_eSpawnFreeze[iClient].iFrames > 0 &&
		TF2_GetClientTeam(iClient) == g_eSpawnFreeze[iClient].iTeam &&
		TF2_GetPlayerClass(iClient) == g_eSpawnFreeze[iClient].iClass) {

		fAng = g_eSpawnFreeze[iClient].fAng;
		TeleportEntity(iClient, g_eSpawnFreeze[iClient].fPos, fAng, NULL_VECTOR);
		g_eSpawnFreeze[iClient].iFrames--;

		return Plugin_Changed;
	}
	
	if (iClient == g_iClientOfInterest) {
		if (g_iClientInstruction & INST_PLAY || g_iClientInstruction & INST_WARMUP) {
			Obs_Mode iObserverMode = Client_GetObserverMode(g_iClientOfInterest);
			if ((iObserverMode == OBS_MODE_IN_EYE || iObserverMode == OBS_MODE_CHASE) && !(g_iClientInstruction & INST_WARMUP)) {
				int iObsTarget = Client_GetObserverTarget(g_iClientOfInterest);
				if (g_hRecordingBots.FindValue(iObsTarget) == -1) {
					FakeClientCommand(g_iClientOfInterest, "spec_player \"%N\"", g_hRecordingBots.Get(0));
				}
			}
			
			if ((g_iRecBufferFrame % 22) == 0 && !(g_iClientInstruction & INST_WARMUP) && g_hRecBufferFrames != null) {
				char sTimePlay[32];
				char sTimeTotal[32];
				
				ToTimeDisplay(sTimePlay, sizeof(sTimePlay), g_iRecBufferFrame/66);
				ToTimeDisplay(sTimeTotal, sizeof(sTimePlay), g_hRecBufferFrames.Length/66);

				char sRecordingType[32];
				if (g_iRecording && g_iRecording.Repo) {
					FormatEx(sRecordingType, sizeof(sRecordingType), "%T: %T", "Source", iClient, "Repository", iClient);
				} else {
					FormatEx(sRecordingType, sizeof(sRecordingType), "%T: %T", "Source", iClient, "Local", iClient);
				}
				
				if (g_iCallKeyMask) {
					if (g_iClientInstruction & INST_PLAYALL) {
						PrintHintText(iClient, "[%d/%d] %t %s/%s\n%s\n%t", g_hRecordings.Length-g_hPlaybackQueue.Length, g_hRecordings.Length, "Replaying", sTimePlay, sTimeTotal, sRecordingType, "Press Stop", g_sCallKeyLabel);
					} else {
						PrintHintText(iClient, "%t %s/%s\n%s\n%t", "Replaying", sTimePlay, sTimeTotal, sRecordingType, "Press Stop", g_sCallKeyLabel);
					}
				} else {
					if (g_iClientInstruction & INST_PLAYALL) {
						PrintHintText(iClient, "[%d/%d] %t %s/%s\n%s\n%t", g_hRecordings.Length-g_hPlaybackQueue.Length, g_hRecordings.Length, "Replaying", sTimePlay, sTimeTotal, sRecordingType, "Type Stop");
					} else {
						PrintHintText(iClient, "%t %s/%s\n%s", "Replaying", sTimePlay, sTimeTotal, sRecordingType);
					}
				}
				StopSound(iClient, SNDCHAN_STATIC, "ui/hint.wav");
			}
			
			if (iButtons & g_iCallKeyMask && g_iRecBufferFrame >= 66) {
				if (Client_IsValid(g_iClientOfInterest) && IsClientInGame(g_iClientOfInterest)) {
					PrintHintText(g_iClientOfInterest, " ");
					StopSound(g_iClientOfInterest, SNDCHAN_STATIC, "ui/hint.wav");
					CreateTimer(0.1, Timer_CloseHintPanel, g_iClientOfInterest, TIMER_FLAG_NO_MAPCHANGE);
					
					g_eLastBubbleTime[g_iClientOfInterest].iTime = GetTime()-10; // Prevent showme spam
					doReturn();
				}
				
				doFullStop();
				findTargetFollow();

				ArrayList hClientInfo = g_iRecording.ClientInfo;

				for (int i=0; i<hClientInfo.Length; i++) {
					TF2_RespawnPlayer(g_hRecordingBots.Get(i, RecBot::iEnt));
				}
			}
		}
		return Plugin_Continue;
	} else if (g_hRecordingBots.FindValue(iClient) != -1) {
		fAng = g_eClientState[iClient].fAng;

		if (GetGameTickCount() - g_eClientState[iClient].iLastUpdate >= MAX_REC_DESYNCS) {
			return Plugin_Changed;
		}


		iButtons = g_eClientState[iClient].iButtons | IN_RELOAD; // Autoreload;

		int iWeaponSlot = (iButtons >>> 26) & 7;
		iWeapon = GetPlayerWeaponSlot(iClient, iWeaponSlot);

		iButtons &= ~(7 << 26);
			
		if (iButtons & (IN_FORWARD|IN_BACK) == IN_FORWARD|IN_BACK) {
			fVel[0] = 0.0;
		} else if (iButtons & IN_FORWARD) {
			fVel[0] = 400.0;
		} else if (iButtons & IN_BACK) {
			fVel[0] = -400.0;
		}
		
		if (iButtons & (IN_MOVELEFT|IN_MOVERIGHT) == IN_MOVELEFT|IN_MOVERIGHT) {
			fVel[1] = 0.0;
		} else if (iButtons & IN_MOVELEFT) {
			fVel[1] = -400.0;
		} else if (iButtons & IN_MOVERIGHT) {
			fVel[1] = 400.0;
		}

		return Plugin_Changed;
	} else if (iButtons & g_iCallKeyMask && (GetTime()-g_eLastBubbleTime[iClient].iTime) < 10) {
		g_eLastBubbleTime[iClient].iTime = GetTime();
		FakeClientCommand(iClient, "showme");
	}
	
	return Plugin_Continue;
}

public void OnClientCookiesCached(int iClient) {
	if (IsFakeClient(iClient)) {
		return;
	}
	
	bool bBubble = true;
	getCookieBool(iClient, g_hCookieBubble, bBubble);
	g_bBubble[iClient] = bBubble;
	
	g_bTrail[iClient] = true;
	getCookieBool(iClient, g_hCookieTrail, g_bTrail[iClient]);
	
	g_bInteract[iClient] = true;
	getCookieBool(iClient, g_hCookieInteract, g_bInteract[iClient]);
	
	g_fSpeed[iClient] = 1.0;
	getCookieFloat(iClient, g_hCookieSpeed, g_fSpeed[iClient]);
	
	g_iPerspective[iClient] = g_hShowMeDefault.IntValue;
	getCookieInt(iClient, g_hCookiePerspective, g_iPerspective[iClient]);
}

public void OnClientPostAdminCheck(int iClient) {
	g_eSpawnFreeze[iClient].iFrames = 0;
	
	if (!IsFakeClient(iClient) && !g_hRecordingBots.Length) {
		SetupBot();
		SetupQueue();
	}
}

public void OnClientDisconnect(int iClient) {
	doPlayerQueueRemove(iClient);

	int iID = g_hRecordingClients.FindValue(iClient);
	if (iID != -1) {
		g_hRecordingClients.Erase(iID);
	}

	if (iClient == g_iLastCaller) {
		g_iLastCaller = -1;
		g_iLastCallTime = 0;
	}

	if (iClient == g_iClientOfInterest) {
		doFullStop();
		g_iClientOfInterest = -1;
		return;
	}
	
	if (iClient == g_iClientFollow) {
		g_iClientFollow = -1;
	}
	
	if (iClient == g_iTargetFollow) {
		g_iTargetFollow = -1;
	}
	
	int iPlayerCount = Client_GetCount(true, false);

	if (IsFakeClient(iClient)) {
		if ((iID = g_hRecordingBots.FindValue(iClient, RecBot::iEnt)) != -1) {
			ClearRecBotData(iID);
			doFullStop();
			
			if (!g_bShuttingDown && iPlayerCount) {
				SetupBot();
			}
		}
	} else if (!iPlayerCount && g_hVacate.BoolValue) {
		doFullStop();

		for (int i=0; i<g_hRecordingBots.Length; i++) {
			KickClient(g_hRecordingBots.Get(i), "%t", "Server Empty");
		}

		if (g_hQueueTimer != null) {
			delete g_hQueueTimer;
		}
	}
}

public void OnRebuildAdminCache(AdminCachePart iPart) {
	for (int i=0; i<g_hRecordingBots.Length; i++) {
		int iClient = g_hRecordingBots.Get(i, RecBot::iEnt);
		SetupBotImmunity(iClient);
	}
}

// Natives 
public int Native_Shutdown(Handle hPlugin, int iArgC) {
	g_bShuttingDown = true;

	for (int i=0; i<g_hRecordingBots.Length; i++) {
		int iClient = g_hRecordingBots.Get(i, RecBot::iEnt);
		KickClient(iClient, "%t", "Punt Bot");
		doFullStop();
	}

	return 0;
}

public int Native_LoadRecordings(Handle hPlugin, int iArgC) {
	doFullStop();

	RemoveAllModels();
	LoadRecordings();

	return 0;
}

public int Native_GetRecordings(Handle hPlugin, int iArgC) {
	ArrayList hRecordings = g_hRecordings.Clone();
	return view_as<int>(hRecordings);
}

public int Native_PlayRecording(Handle hPlugin, int iArgC) {
	Recording iRecording = view_as<Recording>(GetNativeCell(1));
	int iClient = GetNativeCell(2);

	if (g_hRecordings.FindValue(iRecording) == -1 || iClient < 0 || (Client_IsValid(iClient) && !IsClientInGame(iClient))) {
		return 0;
	}

	doFullStop();

	LoadFrames(iRecording);

	g_iRecBufferIdx = 0;
	g_iRecBufferFrame = 0;
	ClearRecEntities();
	g_iRecordingEntTotal = 0;

	if (!PrepareBots(iRecording)) {
		return 0;
	}

	if (iClient) {
		if (GetNativeCell(3)) {
			g_iClientInstructionPost = INST_RETURN;

			float fPos[3], fAng[3];
			GetClientEyeAngles(iClient, fAng);
			GetClientAbsOrigin(iClient, fPos);
			setRespawn(iClient, fPos, fAng);
		}

		int iPerspective = GetNativeCell(4);
		if (iPerspective == -1) {
			iPerspective = g_iPerspective[iClient];
		}
		
		Obs_Mode iMode;
		switch (iPerspective) {
			case 1: {
				iMode = OBS_MODE_IN_EYE;
			}
			case 3: {
				iMode = OBS_MODE_CHASE;
			}
			default: {
				iMode = OBS_MODE_NONE;
			}
		}

		// Primary rec
		int iRecBot = g_hRecordingBots.Get(0, RecBot::iEnt);

		if (iMode == OBS_MODE_IN_EYE || iMode == OBS_MODE_CHASE) {
			ChangeClientTeam(iClient, view_as<int>(TFTeam_Spectator));
			TF2_RespawnPlayer(iClient);

			FakeClientCommand(iClient, "spec_player \"%N\"", iRecBot);
			FakeClientCommand(iClient, "spec_mode %d", iMode);
		}
	}

	g_iRecording = iRecording;

	g_iClientInstruction = INST_WARMUP;
	g_iClientOfInterest = iClient;
	g_iClientInstructionPost = INST_NOP;
	
	SetAllBubbleAlpha(50);

	return 1;
}

public int Native_PlayRecordingQueueClient(Handle hPlugin, int iArgC) {
	Recording iRecording = view_as<Recording>(GetNativeCell(1));
	int iClient = GetNativeCell(2);

	if (g_hRecordings.FindValue(iRecording) == -1 || !Client_IsValid(iClient) || !IsClientInGame(iClient)) {
		return 0;
	}

	int iPerspective = GetNativeCell(3);
	if (iPerspective == -1) {
		iPerspective = g_iPerspective[iClient];
	}
	
	Obs_Mode iMode;
	switch (iPerspective) {
		case 1: {
			iMode = OBS_MODE_IN_EYE;
		}
		case 3: {
			iMode = OBS_MODE_CHASE;
		}
		default: {
			iMode = OBS_MODE_NONE;
		}
	}

	doPlayerQueueRemove(iClient);
	doPlayerQueueAdd(iClient, iRecording, iMode);

	return 1;
}

//////// Commands ////////

public Action cmdGrantAccess(int iClient, int iArgC) {
	if (iArgC < 1) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t: jb_grant <%t>", "Usage", "Name");
		return Plugin_Handled;
	}

	char sArg1[32];					 
	GetCmdArg(1, sArg1, sizeof(sArg1));
	
	int iTarget = FindTarget(iClient, sArg1);
	if (iTarget == -1) {
		return Plugin_Handled;
	}
	
	g_bPlayerGrantAccess[iTarget] = true;
	
	char sUserName[32];
	GetClientName(iTarget, sUserName, sizeof(sUserName));
	CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Recorder Access Granted", sUserName);
	
	return Plugin_Handled;
}

public Action cmdRevokeAccess(int iClient, int iArgC) {
	if (iArgC < 1) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t: jb_revoke <%t>", "Usage", "Name");
		return Plugin_Handled;
	}
	
	char sArg1[32];					 
	GetCmdArg(1, sArg1, sizeof(sArg1));
	
	int iTarget = FindTarget(iClient, sArg1);
	if (iTarget == -1) {
		return Plugin_Handled;
	}
	
	g_bPlayerGrantAccess[iTarget] = false;
	
	char sUserName[32];
	GetClientName(iTarget, sUserName, sizeof(sUserName));
	CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Recorder Access Revoked", sUserName);
	
	return Plugin_Handled;
}

public Action cmdRecord(int iClient, int iArgC) {
	if (!checkAccess(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}

	if (g_iClientInstruction == INST_RECD) {
		if (g_iClientOfInterest == iClient) {
			doFullStop();
			CPrintToChat(iClient, "{dodgerblue}[jb] {white}%t {white}(%d %t)", "Rec Stop", g_iRecBufferFrame, "Frames");
			g_iClientOfInterest = 0;
			
			if (!g_bLocked) {
				SetAllBubbleAlpha(255);
			}
		} else {
			char sUserName[32];
			GetClientName(g_iClientOfInterest, sUserName, sizeof(sUserName));
			CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t: %s", "Recorder Using", sUserName);
		}
		return Plugin_Handled;	
	}
	
	g_iClientOfInterest = iClient;
	g_hRecordingEntities.Clear();
	g_iRecordingEntTotal = 0;

	if (g_hRecordingClients.FindValue(iClient) == -1) {
		g_hRecordingClients.Push(iClient);
	}

	g_hRecBuffer.Clear();
	g_iRecBufferIdx = 0;
	g_iRecBufferUsed = 0;
	g_iRecBufferFrame = 0;
	g_iClientInstruction = INST_RECD;
	
	SetAllBubbleAlpha(50);

	Recording iRec = Recording.Instance();
	g_hRecBufferFrames = iRec.Frames;
	iRec.Timestamp = GetTime();

	// TODO: Bot count vs. RecClient count mismatch
	char sClassName[128];
	char sName[32];
	char sAuthID[24];

	for (int i=0; i<g_hRecordingClients.Length; i++) {
		int iRecClient = g_hRecordingClients.Get(i);

		GetClientName(iRecClient, sName, sizeof(sName));
		GetClientAuthId(iRecClient, AuthId_Steam3, sAuthID, sizeof(sAuthID));

		ClientInfo iClientInfo = ClientInfo.Instance();
		iClientInfo.SetName(sName);
		iClientInfo.SetAuthID(sAuthID);
		iClientInfo.Class = TF2_GetPlayerClass(iRecClient);
		iClientInfo.Team = TF2_GetClientTeam(iRecClient);
		
		for (int iSlot = TFWeaponSlot_Primary; iSlot <= TFWeaponSlot_Item2; iSlot++) {
			int iWeapon = GetPlayerWeaponSlot(iRecClient, iSlot);
			if (iWeapon == -1) {
				iClientInfo.SetEquipItemDefIdx(iSlot, 0);
				//int iSto = iClientInfo.GetEquipItemDefIdx(iSlot);
				//PrintToServer("Rec with slot %d has iWeapon=%d, stored a %d", iSlot, iWeapon, iSto);
				continue;
			}

			iClientInfo.SetEquipItemDefIdx(iSlot, GetItemDefIndex(iWeapon));

			GetEntityClassname(iWeapon, sClassName, sizeof(sClassName));
			iClientInfo.SetEquipClassName(iSlot, sClassName);

			//PrintToServer("Rec with slot %d equipped with %s", iSlot, sClassName);
		}

		iRec.ClientInfo.Push(iClientInfo);
	}

	g_iRecording = iRec;
	
	CPrintToChat(iClient, "{dodgerblue}[jb] {white}%t", "Rec Start");
	
	return Plugin_Handled;
}

public Action cmdPlay(int iClient, int iArgC) {
	if (!checkAccess(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}

	if ((g_iClientInstruction == INST_RECD || g_iClientInstruction & INST_PLAY) && (g_iClientOfInterest > 0 && g_iClientOfInterest != iClient)) {
		char  sUserName[32];
		GetClientName(g_iClientOfInterest, sUserName, sizeof(sUserName));
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Recorder Using", sUserName);
		return Plugin_Handled;
	}

	Recording iRecording = g_iRecording;

	switch (iArgC) {
		case 0: {
			if (!iRecording) {
				// TODO: Translate
				CReplyToCommand(iClient, "{dodgerblue}[jb] {white}Nothing to replay");
				return Plugin_Handled;
			}
		}
		case 1: {
			char sArg1[32];
			GetCmdArg(1, sArg1, sizeof(sArg1));
			int iRecID = StringToInt(sArg1);

			if (iRecID < 0) {
				iRecID = g_hRecordings.Length+iRecID;
			}

			if (iRecID >= g_hRecordings.Length) {
				// TODO: Translate
				CReplyToCommand(iClient, "{dodgerblue}[jb] {white}Invalid recording ID");
				return Plugin_Handled;
			}

			iRecording = g_hRecordings.Get(iRecID);
			if (!LoadFrames(iRecording)) {
				// TODO: Translate
				CReplyToCommand(iClient, "{dodgerblue}[jb] {white}Failed to load recording file");
				return Plugin_Handled;
			}
		}
	}
	
	doFullStop();

	if (!PrepareBots(iRecording)) {
		return Plugin_Handled;
	}

	g_iRecBufferIdx = 0;
	g_iRecBufferFrame = 0;
	ClearRecEntities();
	g_iRecordingEntTotal = 0;
	
	g_iRecording = iRecording;
	g_hRecBufferFrames = iRecording.Frames;

	g_iClientInstruction = INST_WARMUP;
	g_iClientOfInterest = iClient;
	g_iClientInstructionPost = INST_NOP;
	
	SetAllBubbleAlpha(50);
		
	if (g_hDebug.BoolValue) {
		CPrintToChatAll("{dodgerblue}[jb] {white}%t", "Playback Start");
	} else {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Playback Start");
	}

	return Plugin_Handled;
}

public Action cmdSave(int iClient, int iArgC) {
	if (!checkAccess(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}
	
	if (!g_hRecordingBots.Length) {
		 return Plugin_Handled;
	}
	
	if (g_iClientInstruction != INST_NOP) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Terminated");
		
		if (g_iClientInstruction == INST_RECD) {
			g_iClientOfInterest = 0;
		}
		
		doFullStop();
	}
	
	g_iRecBufferIdx = 0;
	
	if (g_iRecBufferUsed == 0) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t (%t: 0)", "Cannot File Write", "Frames");
		return Plugin_Handled;
	}
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), g_sRecSubDir);
	if (!DirExists(sPath)) {
		CreateDirectory(sPath, 509);
	}
	
	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));
	
	char sDate[32];
	FormatTime(sDate, sizeof(sDate), "%Y%m%d_%H%M%S");
	Format(sPath, sizeof(sPath), "%s/%s-%s.jmp", sPath, sMapName, sDate);

	if (!SaveFile(sPath)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t: %s", "Cannot File Write", sPath);
	}

	char sSteamID[32];
	GetClientAuthId(iClient, AuthId_Steam3, sSteamID, sizeof(sSteamID));
	
	if (g_hDebug.BoolValue) {
		CPrintToChatAll("{dodgerblue}[jb] {white}%t", "Playback Saved", g_iRecording.Frames.Length, sSteamID);
	} else {
		CPrintToChat(iClient, "{dodgerblue}[jb] {white}%t", "Playback Saved", g_iRecording.Frames.Length, sSteamID);
	}

	Recording.Destroy(g_iRecording);
	g_iRecording = NULL_RECORDING;
		
	// Refresh recordings
	RemoveAllModels();
	LoadRecordings(true);
	
	return Plugin_Handled;
}

public Action cmdStateSave(int iClient, int iArgC) {
	if (!checkAccess(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}
	
	if (!g_hRecordingBots.Length) {
		 return Plugin_Handled;
	}

	if (!(g_iClientInstruction & INST_RECD)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}Cannot save state while not recording");
		return Plugin_Handled;
	}

	if (iClient != g_iClientOfInterest) {
		char sUserName[32];
		GetClientName(g_iClientOfInterest, sUserName, sizeof(sUserName));
		CPrintToChat(iClient, "{dodgerblue}[jb] {white}%t", "Recorder Using", sUserName);
		return Plugin_Handled;
	}
	
	if (g_iRecBufferUsed == 0) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t (%t: 0)", "Cannot File Write", "Frames");
		return Plugin_Handled;
	}
	
	char sPath[PLATFORM_MAX_PATH];
	char sPathTemp[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), g_sRecSubDir);
	if (!DirExists(sPath))
		CreateDirectory(sPath, 509);
	
	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));
	
	g_iRecording.Timestamp = GetTime();

	int iSlot;
	if (iArgC == 0) {
		iSlot = 0;
		do {
			Format(sPathTemp, sizeof(sPathTemp), "%s/%s-%d.save", sPath, sMapName, ++iSlot);
		} while (FileExists(sPathTemp));
	} else {
		char sArg1[32];
		GetCmdArg(1, sArg1, sizeof(sArg1));

		iSlot = StringToInt(sArg1);
		if (iSlot <= 0) {
			CPrintToChat(iClient, "{dodgerblue}[jb] {white}Invalid state slot number");
			return Plugin_Handled;
		}

		Format(sPathTemp, sizeof(sPathTemp), "%s/%s-%d.save", sPath, sMapName, iSlot);
	}
	
	if (SaveFile(sPathTemp)) {
		CPrintToChat(iClient, "{dodgerblue}[jb] {white}Saved state to slot %d (%d frames)", iSlot, g_hRecBufferFrames.Length);
		g_iStateLoadLast = iSlot;
	} else {
		CPrintToChat(iClient, "{dodgerblue}[jb] {white}%t: %s", "Cannot File Write", sPathTemp);
	}
	
	return Plugin_Handled;
}

public Action cmdStateLoad(int iClient, int iArgC) {
	if (!checkAccess(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}
	
	if (!g_hRecordingBots.Length) {
		 return Plugin_Handled;
	}

	if (g_iClientInstruction != INST_RECD) {
		CPrintToChat(iClient, "{dodgerblue}[jb] {white}Cannot load state while not recording");
		return Plugin_Handled;
	}

	if (iClient != g_iClientOfInterest) {
		char sUserName[32];
		GetClientName(g_iClientOfInterest, sUserName, sizeof(sUserName));
		CPrintToChat(iClient, "{dodgerblue}[jb] {white}%t", "Recorder Using", sUserName);
		return Plugin_Handled;
	}

	char sFilePath[PLATFORM_MAX_PATH];
	char sPath[PLATFORM_MAX_PATH];
	char sFile[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, sPath, sizeof(sPath), g_sRecSubDir);
	if (!DirExists(sPath)) {
		CreateDirectory(sPath, 509);
	}

	if (iArgC == 0) {
		Menu hMenu = new Menu(MenuHandler_LoadState);
		hMenu.SetTitle("Load Rec State");
		BuildStateMenu(hMenu);
		hMenu.Display(iClient, 0);
	} else {
		char sArg1[32];
		GetCmdArg(1, sArg1, sizeof(sArg1));

		int iSaveID = StringToInt(sArg1);
		if (iSaveID <= 0) {
			CPrintToChat(iClient, "{dodgerblue}[jb] {white}Invalid state slot number");
			return Plugin_Handled;
		}

		char sMapName[PLATFORM_MAX_PATH];
		GetCurrentMap(sMapName, sizeof(sMapName));

		FormatEx(sFile, sizeof(sFile), "%s-%d.save", sMapName, iSaveID);
		FormatEx(sFilePath, sizeof(sFilePath), "%s/%s", sPath, sFile);
		ReplaceString(sFilePath, sizeof(sFilePath), "\\\0", "/", true); // Windows

		if (FileExists(sFilePath)) {
			doFullStop();

			Recording iRecording = Recording.Instance();
			iRecording.SetFilePath(sFilePath);

			if (LoadState(iRecording)) {
				CPrintToChat(iClient, "{dodgerblue}[jb] {white}Load state slot %d (%d frames)", iSaveID, g_hRecBufferFrames.Length);
				g_iClientOfInterest = iClient;
				g_iStateLoadLast = iSaveID;
				g_hRecordingClients.Push(iClient);
			} else {
				CPrintToChat(iClient, "{dodgerblue}[jb] {white}Failed to load state slot %d", iSaveID);
				g_iClientOfInterest = -1;
			}
		} else {
			CPrintToChat(iClient, "{dodgerblue}[jb] {white}No such state slot %d", iSaveID);
		}
	}

	return Plugin_Handled;
}

public Action cmdStateLoadLast(int iClient, int iArgC) {
	FakeClientCommand(iClient, "jb_state_load %d", g_iStateLoadLast);
	return Plugin_Handled;
}

public Action cmdStateDelete(int iClient, int iArgC) {
	if (!checkAccess(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}

	char sFilePath[PLATFORM_MAX_PATH];
	char sPath[PLATFORM_MAX_PATH];
	char sFile[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, sPath, sizeof(sPath), g_sRecSubDir);
	if (!DirExists(sPath)) {
		CreateDirectory(sPath, 509);
	}

	if (iArgC == 0) {
		Menu hMenu = new Menu(MenuHandler_DeleteState);
		hMenu.SetTitle("Delete Rec State");
		BuildStateMenu(hMenu);
		hMenu.Display(iClient, 0);
		
	} else {
		char sArg1[32];
		GetCmdArg(1, sArg1, sizeof(sArg1));

		int iSaveID = StringToInt(sArg1);
		if (iSaveID <= 0) {
			CPrintToChat(iClient, "{dodgerblue}[jb] {white}Invalid state slot number");
			return Plugin_Handled;
		}

		char sMapName[PLATFORM_MAX_PATH];
		GetCurrentMap(sMapName, sizeof(sMapName));

		FormatEx(sFile, sizeof(sFile), "%s-%d.save", sMapName, iSaveID);
		FormatEx(sFilePath, sizeof(sFilePath), "%s/%s", sPath, sFile);
		ReplaceString(sFilePath, sizeof(sFilePath), "\\\0", "/", true); // Windows

		if (FileExists(sFilePath)) {
			if (DeleteFile(sFilePath)) {
				CPrintToChat(iClient, "{dodgerblue}[jb] {white}Deleted state slot %d", iSaveID);
			}
		} else {
			CPrintToChat(iClient, "{dodgerblue}[jb] {white}No such state slot %d", iSaveID);
		}
	}

	return Plugin_Handled;
}

public Action cmdList(int iClient, int iArgC) {
	// TODO: Translate
	CReplyToCommand(iClient, "{dodgerblue}[jb] {white}Found %d recordings.%s", g_hRecordings.Length, GetCmdReplySource() == SM_REPLY_TO_CHAT ? "  See console for output." : NULL_STRING);

	if (g_hRecordings.Length) {
		DataPack hPack = new DataPack();
		hPack.WriteCell(iClient);
		hPack.WriteCell(0);
		Timer_RecList(null, hPack);
	}

	return Plugin_Handled;
}

public Action Timer_RecList(Handle hTimer, any aData) {
	DataPack hPack = view_as<DataPack>(aData);
	hPack.Reset(false);
	int iClient = hPack.ReadCell();
	DataPackPos iPos = hPack.Position;
	int iIdx = hPack.ReadCell();

	Recording iRecording = g_hRecordings.Get(iIdx);

	ArrayList hClientInfo = iRecording.ClientInfo;
	
	char sTimeTotal[32];
	ToTimeDisplay(sTimeTotal, sizeof(sTimeTotal), iRecording.FramesExpected/66);

	static char sBuffer[4096];
	FormatEx(sBuffer, sizeof(sBuffer), "\t[%d] duration: %s, frames: %d, buffer: %d, clients: %d", iIdx, sTimeTotal, iRecording.Frames.Length, iRecording.Length, hClientInfo.Length);

	for (int i=0; i<hClientInfo.Length; i++) {
		ClientInfo iClientInfo = hClientInfo.Get(i);
		char sName[32];
		char sAuthID[24];

		iClientInfo.GetName(sName, sizeof(sName));
		iClientInfo.GetAuthID(sAuthID, sizeof(sAuthID));

		Format(sBuffer, sizeof(sBuffer), "%s\n\t\tClient %d, team: %d, class: %d, authid: %24s name: %s", sBuffer, i, iClientInfo.Team, iClientInfo.Class, sAuthID, sName);

		float fPos[3], fAng[3];
		iClientInfo.GetStartPos(fPos);
		iClientInfo.GetStartAng(fAng);
		Format(sBuffer, sizeof(sBuffer), "%s\n\t\t\tStart pos: (%.1f, %.1f, %.1f) ang: (%.1f, %.1f)\n\t\t\tEquipment:", sBuffer, fPos[0], fPos[1], fPos[2], fAng[0], fAng[1]);

		for (int j=TFWeaponSlot_Primary; j<=TFWeaponSlot_Item2; j++) {
			int iItemDefIdx = iClientInfo.GetEquipItemDefIdx(j);
			if (iItemDefIdx) {
				char sClassName[128];
				iClientInfo.GetEquipClassName(j, sClassName, sizeof(sClassName));
				Format(sBuffer, sizeof(sBuffer), "%s\n\t\t\t\tSlot %d, item: %5d, class: %s", sBuffer, j, iItemDefIdx, sClassName);
			}
		}
	}

	PrintToConsole(iClient, sBuffer);

	if (iIdx+1 < g_hRecordings.Length) {
		hPack.Position = iPos;
		hPack.WriteCell(iIdx+1);

		CreateTimer(0.01, Timer_RecList, aData, TIMER_FLAG_NO_MAPCHANGE);
	} else {
		delete hPack;
	}

	return Plugin_Handled;
}

public Action cmdNearby(int iClient, int iArgC) {
	if (!g_hRecordings.Length) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Rec");
		return Plugin_Handled;
	}

	CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t...", "List Nearby");
	
	float fPos[3];
	GetClientEyePosition(iClient, fPos);

	ArrayList hRecordings;
	int iRecordingsTotal;

	if (g_bOctreeAvailable && g_iSpatialIdx) {
		hRecordings = new ArrayList();
		iRecordingsTotal = g_iSpatialIdx.Find(fPos, MAX_NEARBY_SEARCH_DISTANCE, hRecordings, true);
	} else {
		hRecordings = g_hRecordings;
		iRecordingsTotal = g_hRecordings.Length;
	}

	float fPosRecord[3];
	for (int i=0; i<iRecordingsTotal; i++) {
		Recording iRecording = hRecordings.Get(i);
		ArrayList hClientInfo = iRecording.ClientInfo;
		for (int j=0; j<hClientInfo.Length; j++) {
			ClientInfo iClientInfo = hClientInfo.Get(j);

			iClientInfo.GetStartPos(fPosRecord);
			fPosRecord[2] += 20.0; // In case origin is buried inside ground due to floating-point imprecision
			
			float fVecDist = GetVectorDistance(fPosRecord, fPos);
			if (fVecDist < 1000) {
				Handle hTr = TR_TraceRayFilterEx(fPos, fPosRecord, MASK_SHOT_HULL, RayType_EndPoint, traceHitEnvironment);
				if (!TR_DidHit(hTr)) {
					char sClass[32];
					TF2_GetClassName(iClientInfo.Class, sClass, sizeof(sClass));
					sClass[0] = CharToUpper(sClass[0]);

					char sFilePath[PLATFORM_MAX_PATH];
					iRecording.GetFilePath(sFilePath, sizeof(sFilePath));
					int iFilePart = FindCharInString(sFilePath, '/', true);
					
					char sAuthID[24];
					iClientInfo.GetAuthID(sAuthID, sizeof(sAuthID));

					int iID = g_hRecordings.FindValue(iRecording);
					
					CReplyToCommand(iClient, "{white}ID: %3d    %t: %5.1f    %t: %10t    %t: %3d    %t: %20s    %t: %s", iID, "Distance", fVecDist, "Class", sClass, "Frames", iRecording.Length, "Author", sAuthID, "File", sFilePath[iFilePart+1]);
				}
				delete hTr;
			}
		}
	}

	if (hRecordings != g_hRecordings) {
		delete hRecordings;
	}
	
	return Plugin_Handled;
}

public Action cmdLoad(int iClient, int iArgC) {
	if (!checkAccess(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}

	if (g_iClientInstruction != INST_NOP) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Terminated");
		doFullStop();
	}
	
	RemoveAllModels();
	LoadRecordings();
	return Plugin_Handled;
}

public Action cmdDelete(int iClient, int iArgC) {
	if (iArgC != 1) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Usage Delete");
		return Plugin_Handled;
	}
	
	char sArg1[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));
	
	int iID = StringToInt(sArg1);
	if (iID == 0 && sArg1[0] != '0' || iID < 0 || iID >= g_hRecordings.Length) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Invalid ID");
	} else {
		Recording iRecording = g_hRecordings.Get(iID);

		if (iRecording.Repo) {
			CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Cannot Delete Repo");
			return Plugin_Handled;
		}

		doFullStop();
		
		char sFilePath[PLATFORM_MAX_PATH];
		iRecording.GetFilePath(sFilePath, sizeof(sFilePath));
		int iFilePart = FindCharInString(sFilePath, '/', true);
		
		char sFilePathTrash[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, sFilePathTrash, sizeof(sFilePathTrash), TRASH_FOLDER);
		if (!DirExists(sFilePathTrash)) {
			CreateDirectory(sFilePathTrash, 509); // Octal 775
		}
		
		BuildPath(Path_SM, sFilePathTrash, sizeof(sFilePathTrash), "%s/%s", TRASH_FOLDER, sFilePath[iFilePart]);
		
		RenameFile(sFilePathTrash, sFilePath);
		
		LogMessage("%T '%s' > '%s'", "Deleted Rec", LANG_SERVER, sFilePath, sFilePathTrash);
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t: %s", "Deleted Rec", sFilePath[iFilePart+1]);

		RemoveAllModels();
		LoadRecordings(true);
	}
	
	return Plugin_Handled;
}

public Action cmdPlayAll(int iClient, int iArgC) {
	if (!checkAccess(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}

	if (!g_hRecordings.Length) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Rec");
		return Plugin_Handled;
	}
	
	if (g_iClientInstruction != INST_NOP) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Terminated");
	}
	
	doFullStop();

	g_iRecBufferIdx = 0;
	g_iRecBufferFrame = 0;
	ClearRecEntities();
	g_iRecordingEntTotal = 0;

	LoadRecordings(true);
	
	int iRecID = 0;
	if (iArgC == 1) {
		char sArg1[8];
		GetCmdArg(1, sArg1, sizeof(sArg1));
		iRecID = StringToInt(sArg1);

		if (iRecID < 0) {
			iRecID = g_hRecordings.Length+iRecID;
		}

		if (iRecID >= g_hRecordings.Length) {
			// TODO: Translate
			CReplyToCommand(iClient, "{dodgerblue}[jb] {white}Invalid recording ID");
			return Plugin_Handled;
		}
	}

	Recording iRecording = g_hRecordings.Get(iRecID);

	if (!PrepareBots(iRecording)) {
		return Plugin_Handled;
	}
	
	g_hPlaybackQueue.Clear();
	for (int i=iRecID+1; i<g_hRecordings.Length; i++) {
		g_hPlaybackQueue.Push(g_hRecordings.Get(i));
	}

	char sFilePath[PLATFORM_MAX_PATH];
	iRecording.GetFilePath(sFilePath, sizeof(sFilePath));

	if (iRecording.Repo && !FileExists(sFilePath)) {
		g_iClientInstruction = INST_NOP | INST_PLAYALL; // Wait for download completion
		FetchRecording(iRecording);
	} else {
		g_iClientInstruction = INST_WARMUP | INST_PLAYALL;
		LoadFrames(iRecording);
	}

	g_iRecording = iRecording;

	g_iClientOfInterest = iClient;
	g_iClientInstructionPost = INST_NOP;

	SetAllBubbleAlpha(50);
	
	return Plugin_Handled;
}

public Action cmdRewind(int iClient, int iArgC) {
	if (!checkAccess(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}
	
	if (!(g_iClientInstruction & (INST_RECD | INST_PLAY))) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}Cannot use outside of playback or recording");
		return Plugin_Handled;
	}

	if (g_fSpeed[iClient] < 1.0) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}Cannot use while in slow motion.");
		return Plugin_Handled;	
	}

	if (iArgC == 0) {
		g_iRecBufferIdx = 0;
		g_iRecBufferFrame = 0;

		CPrintToChat(iClient, "{dodgerblue}[jb] {white}Rewinded to beginning");
	} else {
		char sArg1[32];
		GetCmdArg(1, sArg1, sizeof(sArg1));

		int iFrames = StringToInt(sArg1);
		if (iFrames <= 0) {
			return Plugin_Handled;
		}

		int iGotoFrame = g_hRecBufferFrames.Length - iFrames;
		if (iGotoFrame < 0) {
			iFrames += iGotoFrame;
			iGotoFrame = 0;
		}

		g_iRecBufferIdx = g_hRecBufferFrames.Get(iGotoFrame - g_hRewindWaitFrames.IntValue);
		RespawnFrameRecEnt(iGotoFrame - g_hRewindWaitFrames.IntValue);

		CPrintToChat(iClient, "{dodgerblue}[jb] {white}Rewinded %d frames", iFrames);

		for (int i=g_hRecBufferFrames.Length-1; i>iGotoFrame; i--) {
			g_hRecBufferFrames.Erase(i);
		}
	}

	g_iClientInstruction |= INST_REWIND;
	g_iRewindWaitFrames = g_hRewindWaitFrames.IntValue;

	/*
	for (int i=0; i<g_hRecordingClients.Length; i++) {
		int iRecClient = g_hRecordingClients.Get(i, RecBot::iEnt);
		SetEntityMoveType(iRecClient, MOVETYPE_NONE);
	}
	*/
	
	return Plugin_Handled;
}

public Action cmdStop(int iClient, int iArgC) {
	if (!checkAccess(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}
	
	if (g_iClientInstruction != INST_NOP) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Terminated");
		if (g_iClientInstruction == INST_PLAY && g_iRecording) {
			ResetBubbleRotation(g_iRecording);
		}
		
		doFullStop();
		doPlayerQueueClear();
		SetAllBubbleAlpha(255);
	}
	
	return Plugin_Handled;
}

public Action cmdPause(int iClient, int iArgC) {
	if (!checkAccess(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}

	// TODO: Translate
	if (!(g_iClientInstruction & (INST_RECD | INST_PLAY))) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}Cannot use outside of playback or recording");
		return Plugin_Handled;
	}

	if (g_fSpeed[iClient] < 1.0) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}Cannot use while in slow motion.");
		return Plugin_Handled;	
	}

	g_iClientInstruction ^= INST_PAUSE;

	if (g_iClientInstruction & INST_RECD) {
		int iFlags = GetEntityFlags(iClient);
		if (g_iClientInstruction & INST_PAUSE) {
			for (int i=0; i<g_hRecordingClients.Length; i++) {
				int iRecClient = g_hRecordingClients.Get(i, RecBot::iEnt);
				SetEntityFlags(iRecClient, iFlags | FL_FROZEN);
				SetEntityMoveType(iRecClient, MOVETYPE_NONE);
				
				for (int j=0; j<g_hRecordingEntities.Length; j++) {
					if (g_hRecordingEntities.Get(j, RecEnt::iOwner) == iRecClient) {
						int iEntity = EntRefToEntIndex(g_hRecordingEntities.Get(j, RecEnt::iRef));
						PrintToServer("entity %d movetype was %d", iEntity, GetEntityMoveType(iEntity));
						SetEntityMoveType(iEntity, MOVETYPE_NONE);
					}
				}
				
			}
		} else {
			for (int i=0; i<g_hRecordingClients.Length; i++) {
				int iRecClient = g_hRecordingClients.Get(i, RecBot::iEnt);
				SetEntityFlags(iRecClient, iFlags & ~FL_FROZEN);
				SetEntityMoveType(iRecClient, MOVETYPE_WALK);

				// FIXME: Stickybombs cannot unfreeze properly
				for (int j=0; j<g_hRecordingEntities.Length; j++) {
					if (g_hRecordingEntities.Get(j, RecEnt::iOwner) == iRecClient) {
						int iEntity = EntRefToEntIndex(g_hRecordingEntities.Get(j, RecEnt::iRef));
						SetEntityMoveType(iEntity, g_hRecordingEntities.Get(j, RecEnt::iMoveType));
						PrintToServer("entity %d movetype reverted to %d", iEntity, g_hRecordingEntities.Get(j, RecEnt::iMoveType));
					}
				}
				
			}
		}
	}
	
	// TODO: Translate
	CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%s", (g_iClientInstruction & INST_PAUSE) ? "Paused" : "Unpaused");

	return Plugin_Handled;
}

public Action cmdSkip(int iClient, int iArgC) {
	if (!checkAccess(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}

	if (!(g_iClientInstruction & INST_PLAY)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}Cannot use outside of playback");
		return Plugin_Handled;
	}

	if (iArgC != 1) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t: jb_skip <%t>", "Usage", "Frame");
		return Plugin_Handled;
	}


	char sArg1[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));

	// TODO: Translate
	int iFrame = StringToInt(sArg1);
	if (iFrame < 0) {
		CPrintToChat(iClient, "{dodgerblue}[jb] {white}Invalid frame number");
		return Plugin_Handled;
	}

	if (iFrame >= g_hRecBufferFrames.Length) {
		CPrintToChat(iClient, "{dodgerblue}[jb] {white}Frame number exceeds buffer length (%d)", g_hRecBufferFrames.Length);
		return Plugin_Handled;
	}

	g_iRecBufferIdx = g_hRecBufferFrames.Get(iFrame);
	RespawnFrameRecEnt(iFrame);

	CPrintToChat(iClient, "{dodgerblue}[jb] {white}Skipped to frame %d", iFrame);

	return Plugin_Handled;
}

public Action cmdSkipTime(int iClient, int iArgC) {
	if (!checkAccess(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}

	if (!(g_iClientInstruction & INST_PLAY)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}Cannot use outside of playback");
		return Plugin_Handled;
	}

	if (iArgC < 1 || iArgC > 3) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t: jb_skiptime [hours] [minutes] <seconds>", "Usage");
		return Plugin_Handled;
	}

	char sArg1[32];
	char sArg2[32];
	char sArg3[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));

	int iFrame = 0;
	switch (iArgC) {
		case 1: {
			int iSeconds = StringToInt(sArg1);
			iFrame = RoundToFloor(float(iSeconds) * 66);
		}
		case 2: {
			GetCmdArg(2, sArg2, sizeof(sArg2));

			int iMinutes = StringToInt(sArg1);
			int iSeconds = StringToInt(sArg2);

			iFrame = RoundToFloor(float(iMinutes*60 + iSeconds) * 66);
		}
		case 3: {
			GetCmdArg(2, sArg2, sizeof(sArg2));
			GetCmdArg(3, sArg3, sizeof(sArg3));

			int iHours = StringToInt(sArg1);
			int iMinutes = StringToInt(sArg2);
			int iSeconds = StringToInt(sArg3);

			iFrame = RoundToFloor(float(iHours*3600 + iMinutes*60 + iSeconds) * 66);
		}
	}

	char sTimeRec[32];

	// TODO: Translate
	if (iFrame >= g_hRecBufferFrames.Length) {
		ToTimeDisplay(sTimeRec, sizeof(sTimeRec), g_hRecBufferFrames.Length/66);

		CPrintToChat(iClient, "{dodgerblue}[jb] {white}Frame number exceeds buffer (%s)", sTimeRec);
		return Plugin_Handled;
	}

	g_iRecBufferIdx = g_hRecBufferFrames.Get(iFrame);
	RespawnFrameRecEnt(iFrame);

	ToTimeDisplay(sTimeRec, sizeof(sTimeRec), iFrame/66);

	CPrintToChat(iClient, "{dodgerblue}[jb] {white}Skipped to %s", sTimeRec);

	return Plugin_Handled;
}


/*
public Action cmdTrim(int iClient, int iArgC) {
	if (!checkAccess(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}
	
	bool bUseError = false;
	if (iArgC != 2) {
		bUseError = true;
	} else {
		char sArg1[8];
		char sArg2[8];
		GetCmdArg(1, sArg1, sizeof(sArg1));
		GetCmdArg(2, sArg2, sizeof(sArg2));

		int iA = StringToInt(sArg1);	
		int iB = StringToInt(sArg2);
		
		if (iA < 0 || iB > 0 || (iA-iB) > g_iShadowBufferUsed) {
			bUseError = true;
		} else {
			int iLength = g_iShadowBufferUsed - (iA-iB);
			for (int i=0; i<iLength; i++) {
				Array_Copy(g_aShadowBuffer[iA+i], g_aShadowBuffer[i], Snapshot_Size);
			}
			
			CReplyToCommand(iClient, "%t: %d -> %d", "Frames", g_iShadowBufferUsed, iLength);
			g_iShadowBufferUsed = iLength;
		}
	}
	
	if (bUseError) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t: jb_trim <A> <B> (0 ≥ A, B ≤ 0, A-B ≤ %t = %d)", "Usage", "Frames", g_iShadowBufferUsed);
	}
	
	return Plugin_Handled;
}
*/

public Action cmdToggleLock(int iClient, int iArgs) {
	if (!checkAccess(iClient)) {
			CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
			return Plugin_Handled;
	}
		
	g_bLocked = !g_bLocked;
	if (g_bLocked) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Bot Locked");
		SetAllBubbleAlpha(50);
	} else {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Bot Unlocked");
		SetAllBubbleAlpha(255);
	}
	
	return Plugin_Handled;
}

public Action cmdShow(int iClient, int iArgC) {
	if (g_bLocked) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Bot Locked");
		return Plugin_Handled;
	}
	
	if (iArgC != 1 && iArgC != 2) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t: sm_show <%t>", "Usage", "Name");
		return Plugin_Handled;
	}
	if (g_iClientInstruction != INST_NOP) {
		char sUserName[32];
		GetClientName(g_iClientOfInterest, sUserName, sizeof(sUserName));
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Recorder Using", sUserName);
		return Plugin_Handled;
	}
	
	char sArg1[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));
	
	int iTarget = FindTarget(iClient, sArg1);
	if (iTarget != -1) {
		FakeClientCommand(iTarget, "showme");
		
		char sUserName[32];
		GetClientName(iTarget, sUserName, sizeof(sUserName));
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Show To", sUserName);
		CPrintToChat(iTarget, "{dodgerblue}[jb] {white}%t", "Show Current");
	}
	
	return Plugin_Handled;
}

public Action cmdShowMe(int iClient, int iArgC) {
	if (g_bLocked) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Bot Locked");
		return Plugin_Handled;
	}
	
	if (g_bCoreAvailable && GetBlockEquip(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}

	if (g_iClientInstruction & INST_RECD) {
		char sUserName[32];
		GetClientName(g_iClientOfInterest, sUserName, sizeof(sUserName));
		CPrintToChat(iClient, "{dodgerblue}[jb] {white}%t", "Recorder Using", sUserName);
		return Plugin_Handled;
	}
	
	if (TF2_GetClientTeam(iClient) > TFTeam_Spectator && !(GetEntityFlags(iClient) & FL_ONGROUND)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Cannot Call Air");
		return Plugin_Handled;
	}
	
	if (!g_hAllowMedic.BoolValue && TF2_GetPlayerClass(iClient) == TFClass_Medic) {
		return Plugin_Handled;
	}
	
	if (g_iClientOfInterest == iClient) {
		return Plugin_Handled;
	}
	
	if (iClient == g_iLastCaller && !checkAccess(iClient) && (GetTime() - g_iLastCallTime) < g_hBotCallCooldown.FloatValue) {
		return Plugin_Handled;
	}

	float fPos[3];
	GetClientEyePosition(iClient, fPos);
	
	Recording iClosestRecord;
	if (GetTime()-g_eLastBubbleTime[iClient].iTime < 10) {
		char sKey[32];
		int iEntity = EntRefToEntIndex(g_eLastBubbleTime[iClient].iEnt);
		if (iEntity == INVALID_ENT_REFERENCE) {
			return Plugin_Handled;
		}

		Entity_GetName(iEntity, sKey, sizeof(sKey));
		g_hBubbleLookup.GetValue(sKey, iClosestRecord);

		if (!IsRecordingVisible(iClosestRecord, iClient)) {
			return Plugin_Handled;
		}
	} else {
		FindResult iFind;
		if (TF2_GetClientTeam(iClient) > TFTeam_Spectator) {
			TFClassType iClass = TF2_GetPlayerClass(iClient);

			int iEquipFilterItemDefIdx = 0;
			int iWeapon = 0;
			switch (iClass) {
				case TFClass_Soldier: {
					iWeapon = GetPlayerWeaponSlot(iClient, TFWeaponSlot_Primary);
				}
				case TFClass_DemoMan: {
					iWeapon = GetPlayerWeaponSlot(iClient, TFWeaponSlot_Secondary);
				}
			}

			if (iWeapon && IsValidEntity(iWeapon)) {
				iEquipFilterItemDefIdx = GetItemDefIndex(iWeapon);
			}

			iFind = FindNearestRecording(fPos, iClass, iClosestRecord, iEquipFilterItemDefIdx);
		} else {
			iFind = FindNearestRecording(fPos, TFClass_Unknown, iClosestRecord);
		}
		
		if (iFind != FOUND_RECORDING) {
			switch (iFind) {
				case NO_RECORDING: {
					CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Rec Map");
				}
				case NO_CLASS_RECORDING: {
					CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Rec Class");
				}
				case NO_NEARBY_RECORDING: {
					CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Nearby");
				}
			}
			
			if (g_hQueue.Length == 0) {
				g_iClientFollow = iClient;
			}
			
			return Plugin_Handled;
		}
	}
	
	Obs_Mode iMode; 
	switch (g_iPerspective[iClient]) {
		case 1: {
			iMode = OBS_MODE_IN_EYE;
		}
		case 3: {
			iMode = OBS_MODE_CHASE;
		}
		default: {
			iMode = OBS_MODE_NONE;
		}
	}
	
	char sFilePath[PLATFORM_MAX_PATH];
	iClosestRecord.GetFilePath(sFilePath, sizeof(sFilePath));
	bool bFileExists = FileExists(sFilePath);
	
	// Prefetch file from repository, even if player is waiting in queue
	if (g_iClientInstruction != INST_NOP && iClosestRecord.Repo && !bFileExists) {
		FetchRecording(iClosestRecord, true);
	}
	
	doPlayerQueueRemove(iClient);
	doPlayerQueueAdd(iClient, iClosestRecord, iMode);
	
	return Plugin_Handled;
}

void doShowMe(int iClient, Recording iRecording, TFTeam iTeam, Obs_Mode iMode) {
	if (g_iClientInstruction != INST_NOP || !IsClientInGame(iClient) || !g_hRecordingBots.Length) {
		return;
	}
	
	char sFilePath[PLATFORM_MAX_PATH];
	iRecording.GetFilePath(sFilePath, sizeof(sFilePath));
	bool bFileExists = FileExists(sFilePath);
	
	if (!iRecording.Repo && !CheckFile(sFilePath)) {
		LogError("%T: %s", "Cannot Local Play", LANG_SERVER, sFilePath);
		g_iClientInstruction = INST_NOP;
		g_iRecording = NULL_RECORDING;
		return;
	}

	if (iRecording.Repo && (!bFileExists || iRecording.Downloading)) {
		g_iClientInstruction = INST_WAIT; // Wait for download completion
		
		if (g_hDebug.BoolValue) {
			CPrintToChat(iClient, "{dodgerblue}[jb] {white}File %s", !bFileExists ? "does not exist" : "is downloading");
		}
		
		if (!iRecording.Downloading) {
			FetchRecording(iRecording);
		}
	} else {
		if (!(LoadRecording(iRecording) && PrepareBots(iRecording) && LoadFrames(iRecording))) {
			CPrintToChat(iClient, "{dodgerblue}[jb] {white}%t", "Cannot File Read");
			return;
		}

		g_iClientInstruction = INST_WARMUP;
	}

	ArrayList hClientInfo = iRecording.ClientInfo;
	for (int i=0; i<hClientInfo.Length; i++) {
		CreateTimer(0.0, Timer_DoVoiceGo, g_hRecordingBots.Get(i), TIMER_FLAG_NO_MAPCHANGE);
	}

	if (g_hDebug.BoolValue) {
		CPrintToChat(iClient, "{dodgerblue}[jb] {white}%t: %s", "Playing Closest", sFilePath);
	} else {
		CPrintToChat(iClient, "{dodgerblue}[jb] {white}%t", "Playing Closest");
	}
	
	g_iClientOfInterest = iClient;
	g_iClientFollow = iClient;
	
	float fPos[3], fAng[3];
	GetClientEyeAngles(iClient, fAng);
	GetClientAbsOrigin(iClient, fPos);
	setRespawn(iClient, fPos, fAng);
	
	g_iRecording = iRecording;
	g_iRecBufferFrame =  0;
	g_iRecBufferIdx = 0;
	ClearRecEntities();
	g_iRecordingEntTotal = 0;

	g_iLastCaller = iClient;
	g_iLastCallTime = GetTime();

	SetAllBubbleAlpha(50);

	if (g_hAllowMedic.BoolValue && TF2_GetPlayerClass(iClient) == TFClass_Medic && iTeam > TFTeam_Spectator) {
		g_iClientInstructionPost = INST_NOP;
		g_iClientInstruction = INST_WARMUP;
		return;
	}

	// Primary rec
	int iRecBot = g_hRecordingBots.Get(0, RecBot::iEnt);
	
	if (iMode == OBS_MODE_IN_EYE || iMode == OBS_MODE_CHASE) {
		ChangeClientTeam(iClient, view_as<int>(TFTeam_Spectator));
		TF2_RespawnPlayer(iClient);

		FakeClientCommand(iClient, "spec_player \"%N\"", iRecBot);
		FakeClientCommand(iClient, "spec_mode %d", iMode);
		
		g_iClientInstructionPost = INST_RETURN;
		
		if (iTeam == TFTeam_Spectator) {
			g_iClientInstructionPost |= INST_SPEC;
		}

		setRespawnTeam(g_iClientOfInterest, iTeam);
		setRespawnClass(g_iClientOfInterest, TF2_GetPlayerClass(iClient));
	} else {
		g_iClientInstructionPost = INST_NOP;
	}
	
	if (g_iClientInstructionPost & INST_RETURN) {
		for (int i=1; i<=MaxClients; i++) {
			if (IsClientInGame(i) && i != iClient && TF2_GetClientTeam(i) == TFTeam_Spectator) {
				Obs_Mode iObserverMode = Client_GetObserverMode(i);
				if (iObserverMode == OBS_MODE_IN_EYE || iObserverMode == OBS_MODE_CHASE) {
					int iObsTarget = Client_GetObserverTarget(i);
					if (iObsTarget == iClient) {
						g_hSpecList.Push(i);
						if (IsPlayerAlive(iRecBot)) {
							FakeClientCommand(i, "spec_player \"%N\"", iRecBot);
						} else {
							CreateTimer(g_iWarmupFrames / 66.0, Timer_SpecBot, i, TIMER_FLAG_NO_MAPCHANGE);
						}
					}
				}
			}
		}
	}
	
	if (g_bShowKeysAvailable) {
		// TODO: Obs any of bots
		ForceShowKeys(iClient, iRecBot);
	}
}

public Action cmdChdir(int iClient, int iArgC) {
	if (!checkAccess(iClient)) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "No Access");
		return Plugin_Handled;
	}

	if (iArgC == 0) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Rec Folder", g_sRecSubDir);
	}
	
	if (iArgC != 1) {
		CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Usage Chdir");
		return Plugin_Handled;
	}
	
	char sArg1[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));
	
	if (strlen(sArg1) == 1 && sArg1[0] == '.') {
		strcopy(g_sRecSubDir, sizeof(g_sRecSubDir), RECORD_FOLDER);
	} else {
		if (StrContains(sArg1[0], ".") != -1 || StrContains(sArg1[0], "/") != -1) {
			CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Illegal Char");
			return Plugin_Handled;
		}
		
		FormatEx(g_sRecSubDir, sizeof(g_sRecSubDir), "%s/%s", RECORD_FOLDER, sArg1);
	}
	
	RemoveAllModels();
	LoadRecordings(true);
	
	CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Rec Chdir", g_sRecSubDir);
	
	return Plugin_Handled;
}

public Action cmdClearCache(int iClient, int iArgC) {
	doReturn();
	doFullStop();
	ClearRecordings(g_hRecordings);
	g_hBubbleLookup.Clear();
	g_hProjMap.Clear();
	g_hSpecList.Clear();
	doPlayerQueueClear();
	
	for (int i = 1; i <= MaxClients; i++) {
		if (g_hQueuePanel[i] != null) {
			delete g_hQueuePanel[i];
		}
	}
			
	char sCacheFolder[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sCacheFolder, sizeof(sCacheFolder), CACHE_FOLDER);
	
	DirectoryListing hDir = OpenDirectory(sCacheFolder);
	char sFileName[PLATFORM_MAX_PATH];
	char sFilePath[PLATFORM_MAX_PATH];
	FileType iFileType;
	while (hDir.GetNext(sFileName, sizeof(sFileName), iFileType)) {
		BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "%s/%s", CACHE_FOLDER, sFileName);
		DeleteFile(sFilePath);
	}
	delete hDir;
	
	RemoveAllModels();
	LoadRecordings(); // Redownload repo index
	
	return Plugin_Handled;
}

public Action cmdOptions(int iClient, int iArgC) {
	sendOptionsPanel(iClient);
	return Plugin_Handled;
}

public Action cmdUpgrade(int iClient, int iArgC) {
	CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t", "Running Upgrade");
	LogMessage("%T", "Running Upgrade", LANG_SERVER);
	
	char sRecordingFolder[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sRecordingFolder, sizeof(sRecordingFolder), RECORD_FOLDER);
	
	ArrayList hDirInfo = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	hDirInfo.Push(new StringMap()); // Hashes trie
	
	DirectoryListing hDir = OpenDirectory(sRecordingFolder);
	char sFileName[PLATFORM_MAX_PATH];
	char sFilePath[PLATFORM_MAX_PATH];
	FileType iFileType;
	
	while (hDir.GetNext(sFileName, sizeof(sFileName), iFileType)) {
		BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "%s/%s", RECORD_FOLDER, sFileName);

		int iExt = FindCharInString(sFileName, '.', true);
		if (iFileType == FileType_File && iExt != -1 && StrEqual(sFileName[iExt], ".jmp", false)) {
			hDirInfo.PushString(sFilePath);
		}
	}
	delete hDir;
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), CACHE_FOLDER);
	if (!DirExists(sPath)) {
		CreateDirectory(sPath, 509);
	}
	
	BuildPath(Path_SM, sPath, sizeof(sPath), "%s/hashes.txt", CACHE_FOLDER);
	
	File hFile = OpenFile(sPath, "w+");
	if (hFile == null) {
		LogError("%T: %s", "Cannot File Write", LANG_SERVER, sPath);
		return Plugin_Handled;
	}
	
	FetchHashes(hFile, hDirInfo);
	
	return Plugin_Handled;
}

//////// Custom callbacks ////////

public Action Event_PlayerSpawn(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!iClient) {
		return Plugin_Handled;
	}

	int iBotID = -1;
	if (iClient == g_iClientOfInterest && !(g_iClientInstruction & INST_PLAYALL) && TF2_GetClientTeam(iClient) > TFTeam_Spectator) {
		doFullStop();
		g_iRecBufferIdx = 0;
		g_iRecBufferFrame = 0;
		
		if (g_bShuttingDown) {
			Timer_TeleportOnSpawn(INVALID_HANDLE, iClient);
			TeleportEntity(iClient, g_eSpawnFreeze[iClient].fPos, g_eSpawnFreeze[iClient].fAng, NULL_VECTOR);
		} else {
			SetEntityFlags(iClient, GetEntityFlags(iClient) | FL_FROZEN);
			SetEntityFlags(iClient, GetEntityFlags(iClient) | FL_ATCONTROLS);
			
			CreateTimer(RESPAWN_FREEZE_FRAMES/66.0, Timer_TeleportOnSpawn, iClient);
		}
		
		return Plugin_Handled;
	} else if ((iBotID = g_hRecordingBots.FindValue(iClient, RecBot::iEnt)) != -1) {
		Client_SetFOV(iClient, g_hFOV.IntValue);
		
		SetEntProp(iClient, Prop_Data, "m_takedamage", 1, 1); // Buddha
	
		if (g_hOutline.BoolValue) {
			SetEntProp(iClient, Prop_Send, "m_bGlowEnabled", 1);
		}
		
		if (g_hRobot.BoolValue) {
			setRobotModel(iClient);
		}
		
		Equip(iBotID);
	} else {
		// Have bots join a team after a player joins one
		if (!IsFakeClient(iClient) && g_hRecordingBots.Length) {
			TFTeam iTeam = TF2_GetClientTeam(iClient);
			for (int i=0; i<g_hRecordingBots.Length; i++) {
				int iRecBot = g_hRecordingBots.Get(i, RecBot::iEnt);

				if (TF2_GetClientTeam(iRecBot) <= TFTeam_Spectator) {
					ChangeClientTeam(iRecBot, view_as<int>(iTeam));
				}
			}
			
		}
	}
	
	return Plugin_Continue;
}

public Action Event_PlayerTeam(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (!iClient) {
		return Plugin_Handled;
	}
	
	if (iClient == g_iClientOfInterest || g_hRecordingBots.FindValue(iClient, RecBot::iEnt) != -1) {
		hEvent.BroadcastDisabled  = true;
	}
	
	doPlayerQueueRemove(iClient);
	
	return Plugin_Continue;
}

public Action Event_RoundStart(Event hEvent, const char[] sName, bool bDontBroadcast) {
	RemoveAllModels();
	blockFlags();
	blockRegen();

	return Plugin_Continue;
}

public Action UserMessage_VoiceSubtitle(UserMsg iMessageID, Handle hMessage, const int[] iPlayers, int iPlayersNum, bool bReliable, bool bInit) {
	int iClient = BfReadByte(hMessage);
	if (g_hRecordingBots.FindValue(iClient, RecBot::iEnt) != -1) {
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public void Respawn(any aData) {
	TF2_RespawnPlayer(aData);
}

public Action Timer_BotJoinExecute(Handle hTimer, any aData) {
	int iClient = GetClientFromSerial(aData);
	if (iClient) {
		char sCommands[256];
		g_hBotJoinExecute.GetString(sCommands, sizeof(sCommands));
		
		char sBuffers[16][32];
		int iCmds = ExplodeString(sCommands, ";", sBuffers, 16, 32);
		
		for (int i=0; i<iCmds; i++) {
			FakeClientCommand(iClient, sBuffers[i]);
		}
		
		ConVar hCVCheats = FindConVar("sv_cheats");
		if (hCVCheats.BoolValue) {
			hCVCheats.BoolValue = false;
		}
	}
	
	return Plugin_Handled;
}

public Action Timer_AmmoRegen(Handle hTimer) {
	for (int i=0; i<g_hRecordingBots.Length; i++) {
		int iRecBot = g_hRecordingBots.Get(i, RecBot::iEnt);

		int iWeapon1 = GetPlayerWeaponSlot(iRecBot, TFWeaponSlot_Primary);
		if (iWeapon1 != -1) {
			int iAmmoType1 = GetEntProp(iWeapon1, Prop_Data, "m_iPrimaryAmmoType");
			GivePlayerAmmo(iRecBot, 500, iAmmoType1, true);
			
			// Ignore Beggar's Bazooka	
			if (GetItemDefIndex(iWeapon1) != 730) {
				int iMaxClip = g_hSDKGetMaxClip1 == null ? 4 : SDKCall(g_hSDKGetMaxClip1, iWeapon1);
				SetEntProp(iWeapon1, Prop_Send, "m_iClip1", iMaxClip);
				SetEntPropFloat(iWeapon1, Prop_Send, "m_flEnergy", 100.0);
			}
		}
		
		int iWeapon2 = GetPlayerWeaponSlot(iRecBot, TFWeaponSlot_Secondary);
		if (iWeapon2 != -1) {
			int iAmmoType2 = GetEntProp(iWeapon2, Prop_Data, "m_iPrimaryAmmoType");
			GivePlayerAmmo(iRecBot, 500, iAmmoType2, true);
			int iMaxClip = g_hSDKGetMaxClip1 == null ? 4 : SDKCall(g_hSDKGetMaxClip1, iWeapon2);
			SetEntProp(iWeapon2, Prop_Send, "m_iClip1", iMaxClip);
			SetEntPropFloat(iWeapon2, Prop_Send, "m_flEnergy", 100.0);
		}
	}
	
	return Plugin_Continue;
}

public Action Timer_Queue(Handle hTimer, any aData) {
	if (g_iClientInstruction == INST_NOP && g_hQueue.Length) {
		Queue eQueue;
		g_hQueue.GetArray(0, eQueue);
		g_hQueue.Erase(0);
		
		if (g_hQueuePanel[eQueue.iClient] != null) {
			delete g_hQueuePanel[eQueue.iClient];
		}
		
		doShowMe(eQueue.iClient, eQueue.iRecording, eQueue.iTeam, eQueue.iObsMode);
	} else if (g_hRecordingBots.Length && g_iClientInstruction == INST_NOP && !g_hQueue.Length && g_hInteractive.IntValue) {
		findTargetFollow();
	}
	
	for (int i=0; i < g_hQueue.Length; i++) {
		sendQueuePanel(g_hQueue.Get(i, Queue::iClient));
	}
	
	RefreshModels();

	return Plugin_Continue;
}

public Action Timer_SpecBot(Handle hTimer, any aData) {
	if (g_hRecordingBots.Length) {
		FakeClientCommand(aData, "spec_player \"%N\"", g_hRecordingBots.Get(0));
	}

	return Plugin_Handled;
}

public Action Timer_TeleportOnSpawn(Handle hTimer, any aData) {
	int iClient = aData;
	if (IsClientInGame(iClient)) {
		SetEntityFlags(iClient, GetEntityFlags(iClient) & ~FL_FROZEN);
		SetEntityFlags(iClient, GetEntityFlags(iClient) & ~FL_ATCONTROLS);
	}
	
	return Plugin_Handled;
}

public Action Timer_DoVoiceGo(Handle hTimer, any aData) {
	if (IsClientInGame(aData)) {
		char sVoice[9][4] = {
			"0 2", // Go! Go! Go!
			"0 1", // Thanks!
			"0 6", // Yes
			"1 0", // Incoming
			"2 0", // Help!
			"2 1", // Battle Cry
			"2 2", // Cheers
			"2 4", // Positive
			"2 7"  // Good job
		};
		
		int iRandom = GetRandomInt(0, sizeof(sVoice)-1);
		FakeClientCommand(aData, "voicemenu %s", sVoice[iRandom]);
	}
	
	return Plugin_Handled;
}

public Action Timer_CloseHintPanel(Handle hTimer, any aData) {
	if (Client_IsValid(aData) && IsClientInGame(aData)) {
		int iClient = aData;
		PrintHintText(iClient, "");
		StopSound(iClient, SNDCHAN_STATIC, "ui/hint.wav");
	}
	return Plugin_Continue;
}

public Action Timer_Cleanup(Handle hTimer, ArrayList hDirInfo) {
	StringMap hHashes = hDirInfo.Get(0);
	
	char sFilePath[PLATFORM_MAX_PATH];
	char sHash[41];
	char sValue[41];
	
	int i=0;
	while (hDirInfo.Length > 1) {
		hDirInfo.GetString(hDirInfo.Length-1, sFilePath, sizeof(sFilePath));
		File hFile = OpenFile(sFilePath, "rb");
		bool bHashed = SHA1File(hFile, sHash);
		delete hFile;
		
		if (bHashed && hHashes.GetString(sHash, sValue, sizeof(sValue))) {
			LogMessage("[%d] %T -- %T: %s\t%T: %s", GetArraySize(hDirInfo)-1, "Delete", LANG_SERVER, "Hash", LANG_SERVER, sHash, "File", LANG_SERVER, sFilePath);
			DeleteFile(sFilePath);
		}
		hDirInfo.Resize(hDirInfo.Length-1);
		
		if (++i > 10) {
			CreateTimer(0.1, Timer_Cleanup, hDirInfo);
			break;
		}
	}
	
	// No more files
	if (i < 10) {
		delete hHashes;
		delete hDirInfo;
		BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "%s/hashes.txt", CACHE_FOLDER);
		DeleteFile(sFilePath);
		LogMessage("%T", "Rec Cleaned", LANG_SERVER);
	}
		
	return Plugin_Handled;
}

public bool traceHitEnvironment(int iEntity, int iMask) {
	return false;
}

public bool traceHitNonPlayer(int iEntity, int iMask, any aData) {
	return iEntity != aData && !Client_IsValid(iEntity);
}

public Action Hook_StartTouchInfo(int iEntity, int iOther) {
	if (Client_IsValid(iOther) && !IsFakeClient(iOther) && g_bBubble[iOther]) {
		int iEntityRef = EntIndexToEntRef(iEntity);

		char sKey[32];
		Entity_GetName(iEntity, sKey, sizeof(sKey));

		Recording iRecording;
		g_hBubbleLookup.GetValue(sKey, iRecording);
		
		char sDisplay[256];
		char sAuthorName[32];
		char sAuthID[24];
		char sClass[32];
		char sEquipName[64];

		if (!IsRecordingVisible(iRecording, iOther)) {
			return Plugin_Handled;
		}

		ArrayList hClientInfo = iRecording.ClientInfo;
		if (hClientInfo.Length) {
			// Primary author
			ClientInfo iClientInfo0 = hClientInfo.Get(0);
			iClientInfo0.GetName(sAuthorName, sizeof(sAuthorName));
			iClientInfo0.GetAuthID(sAuthID, sizeof(sAuthID));

			FormatEx(sDisplay, sizeof(sDisplay), sAuthorName[0] ? sAuthorName : sAuthID);

			for (int i=1; i<hClientInfo.Length; i++) {
				ClientInfo iClientInfo = hClientInfo.Get(i);
				iClientInfo.GetName(sAuthorName, sizeof(sAuthorName));
				iClientInfo.GetAuthID(sAuthID, sizeof(sAuthID));

				Format(sDisplay, sizeof(sDisplay), "%s, %s", sDisplay, sAuthorName[0] ? sAuthorName : sAuthID);
			}

			TF2_GetClassName(view_as<TFClassType>(iClientInfo0.Class), sClass, sizeof(sClass));
			sClass[0] = CharToUpper(sClass[0]);
			Format(sClass, sizeof(sClass), "%T", sClass, iOther);

			if (iClientInfo0.Class == TFClass_Soldier) {
				int iSlot, iItemDefIdx;
				iRecording.GetEquipFilter(iSlot, iItemDefIdx);

				switch (iItemDefIdx) {
					case 513:
						strcopy(sEquipName, sizeof(sEquipName), "\nLoadout: Original");
					case 730:
						strcopy(sEquipName, sizeof(sEquipName), "\nLoadout: Beggar's Bazooka");
				}
			}
		}
		
		if (!sAuthorName[0] && !sAuthID[0]) {
			FormatEx(sAuthID, sizeof(sAuthID), "%T", "Unknown", iOther);
		}

		char sTimeTotal[32];
		ToTimeDisplay(sTimeTotal, sizeof(sTimeTotal), iRecording.FramesExpected/66);

		int iRecID = g_hRecordings.FindValue(iRecording);
		if (g_iCallKeyMask) {
			if (iRecording.Repo) {
				PrintHintText(iOther, "%t (%s)%s\n%t: %s\n%t", "Class Recording", sClass, sTimeTotal, sEquipName, "Author", sDisplay, "Press Review", g_sCallKeyLabel);
			} else {
				PrintHintText(iOther, "[%d] %t (%s)%s\n%t: %s\n%t", iRecID, "Class Recording", sClass, sTimeTotal, sEquipName, "Author", sDisplay, "Press Review", g_sCallKeyLabel);
			}
		} else {
			char sCmd[32];
			g_hBotCallSignShort.GetString(sCmd, sizeof(sCmd));
			
			if (iRecording.Repo) {
				PrintHintText(iOther, "%t (%s)%s\n%t: %s\n%t", "Class Recording", sClass, sTimeTotal, sEquipName, "Author", sDisplay, "Type Review", sCmd);
			} else {
				PrintHintText(iOther, "[%d] %t (%s)%s\n%t: %s\n%t", iRecID, "Class Recording", sClass, sTimeTotal, sEquipName, "Author", sDisplay, "Type Review", sCmd);
			}
		}
		StopSound(iOther, SNDCHAN_STATIC, "ui/hint.wav");
		
		if (g_hDebug.BoolValue && (iEntityRef != g_eLastBubbleTime[iOther].iEnt || GetTime()-g_eLastBubbleTime[iOther].iTime > 10)) {
			char sFilePath[PLATFORM_MAX_PATH];
			iRecording.GetFilePath(sFilePath, sizeof(sFilePath));
			CPrintToChat(iOther, "{dodgerblue}[jb] {white}ID: %d | %t | %s %t (%s) | %t: %s | %t:\n	%s", iRecID, (iRecording.Repo ? "Repository" : "Local"), sClass, "Recording", sTimeTotal, "Author", sAuthID, "File", sFilePath);
		}

		g_eLastBubbleTime[iOther].iEnt = iEntityRef;
		g_eLastBubbleTime[iOther].iTime = GetTime();
	}
	
	return Plugin_Continue;
}

public Action Hook_EndTouchInfo(int iEntity, int iOther) {
	if (Client_IsValid(iOther) && !IsFakeClient(iOther) && g_bBubble[iOther]) {
		int iTimeDiff = GetTime() - g_eLastBubbleTime[iOther].iTime;
		if (EntIndexToEntRef(iEntity) == g_eLastBubbleTime[iOther].iEnt && iTimeDiff < 10) {
			PrintHintText(iOther, " ");
			StopSound(iOther, SNDCHAN_STATIC, "ui/hint.wav");
			CreateTimer(0.1, Timer_CloseHintPanel, iOther, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	return Plugin_Continue;
}

public Action Hook_TouchFlag(int iEntity, int iOther) {
	if (g_hRecordingBots.FindValue(iOther, RecBot::iEnt) != -1) {
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Hook_RocketSpawn(int iEntity) {
	int iOwnerEnt = Entity_GetOwner(iEntity);

	if (!Client_IsValid(iOwnerEnt)) {
		return Plugin_Continue;
	}

	int iRecBot = -1;
	int iRecOwner = IsFakeClient(iOwnerEnt) ? (iRecBot = g_hRecordingBots.FindValue(iOwnerEnt, RecBot::iEnt)) : g_hRecordingClients.FindValue(iOwnerEnt);
	
	if (iRecOwner != -1) {
		RegisterRecEnt(iEntity, iOwnerEnt);
	}

	if (iRecBot != -1) {
		if (g_hProjTrail.BoolValue) {
			float fPos[3];
			float fAng[3];
			Entity_GetAbsOrigin(iEntity, fPos);
			Entity_GetAbsAngles(iEntity, fAng);
			
			Handle hTr = TR_TraceRayFilterEx(fPos, fAng, MASK_SHOT_HULL, RayType_Infinite, traceHitNonPlayer, iEntity);
			if (TR_DidHit(hTr)) {
				float fPosAhead[3];
				TR_GetEndPosition(fPosAhead, hTr);
				
				TE_SetupBeamPoints(fPos, fPosAhead, g_iTrailLaser, g_iTrailHalo, 0, 66, g_fTrailLife, 5.0, 5.0, 1, 1.0, g_iProjTrailColor, 0);
				TE_SendToAllInRangeVisible(fPos);
			}
			delete hTr;
		}
		
		if (g_hOutline.BoolValue) {
			setProjectileGlow(iEntity);
		}
	}
	
	return Plugin_Continue;
}

public Action Hook_ProjectileSpawn(int iEntity) {
	int iOwnerEnt = Entity_GetOwner(iEntity);

	// TODO: Track and record sentry rockets
	if (!Client_IsValid(iOwnerEnt)) {
		return Plugin_Continue;
	}

	int iRecBot = -1;
	int iRecOwner = IsFakeClient(iOwnerEnt) ? (iRecBot = g_hRecordingBots.FindValue(iOwnerEnt, RecBot::iEnt)) : g_hRecordingClients.FindValue(iOwnerEnt);
	
	if (iRecOwner != -1) {
		RegisterRecEnt(iEntity, iOwnerEnt);
	}

	if (iRecBot != -1) {
		if (g_hProjTrail.BoolValue) {
			SDKHook(iEntity, SDKHook_VPhysicsUpdatePost, Hook_ProjVPhysics);
			
			char sKey[5];
			sKey[0] = (iEntity      ) & 0xFF;
			sKey[1] = (iEntity >>  8) & 0xFF;
			sKey[2] = (iEntity >> 16) & 0xFF;
			sKey[3] = (iEntity >> 24) & 0xFF;
			
			float fPos[3];
			Entity_GetAbsOrigin(iEntity, fPos);
			
			g_hProjMap.SetArray(sKey, fPos, 3);
		}

		if (g_hOutline.BoolValue) {
			setProjectileGlow(iEntity);
		}
	}
	
	return Plugin_Continue;
}

public void Hook_ProjVPhysics(int iEntity) {
	float fPos[3];
	Entity_GetAbsOrigin(iEntity, fPos);
	
	char sKey[5];
	sKey[0] = (iEntity      ) & 0xFF;
	sKey[1] = (iEntity >>  8) & 0xFF;
	sKey[2] = (iEntity >> 16) & 0xFF;
	sKey[3] = (iEntity >> 24) & 0xFF;
	
	float fPosPrev[3];
	g_hProjMap.GetArray(sKey, fPosPrev, sizeof(fPosPrev));
	g_hProjMap.SetArray(sKey, fPos, sizeof(fPos));
	
	TE_SetupBeamPoints(fPosPrev, fPos, g_iTrailLaser, g_iTrailHalo, 0, 66, g_fTrailLife, 5.0, 5.0, 1, 1.0, g_iProjTrailColor, 0);
	TE_SendToAllInRangeVisible(fPos);
}

// Adapted from BeTheRobot: https://forums.alliedmods.net/showthread.php?t=193067
public Action Hook_NormalSound(int iClients[64], int &iNumClients, char sSound[PLATFORM_MAX_PATH], int &iEnt, int &iChannel, float &fVolume, int &iLevel, int &iPitch, int &iFlags) {
	if (g_hRobot.BoolValue && g_hRecordingBots.FindValue(iEnt, RecBot::iEnt) != -1) {
		TFClassType iClass = TF2_GetPlayerClass(iEnt);
		
		if (StrContains(sSound, "player/footsteps/", false) != -1 && iClass != TFClass_Medic) {
			int iRand = GetRandomInt(1,18);
			FormatEx(sSound, sizeof(sSound), "mvm/player/footsteps/robostep_%02i.wav", iRand);
			iPitch = GetRandomInt(95, 100);
			PrecacheSound(sSound);
			EmitSoundToAll(sSound, iEnt, _, _, _, 0.25, iPitch);
			return Plugin_Changed;
		}

		if (StrContains(sSound, "vo/") != -1) {
			ReplaceString(sSound, sizeof(sSound), "vo/", "vo/mvm/norm/");
			
			char sClass[10];
			char sClassMvM[16];
			TF2_GetClassName(iClass, sClass, sizeof(sClass));
			FormatEx(sClassMvM, sizeof(sClassMvM), "%s_mvm", sClass);

			ReplaceString(sSound, sizeof(sSound), sClass, sClassMvM);

			PrecacheSound(sSound);
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}

public Action Hook_Entity_SetTransmit(int iEntity, int iClient) {
	if (!g_bBubble[iClient]) {
		return Plugin_Handled;
	}
	
	if (g_bCoreAvailable && GetBlockEquip(iClient)) {
		return Plugin_Handled;
	}

	char sKey[32];
	Entity_GetName(iEntity, sKey, sizeof(sKey));

	Recording iRecording;
	if (!g_hBubbleLookup.GetValue(sKey, iRecording)) {
		return Plugin_Continue;
	}

	if (IsRecordingVisible(iRecording, iClient)) {
		return Plugin_Continue;
	}

	return Plugin_Handled;
}

// TODO: Follower taunt
/*
public Action Hook_SpawnTaunt(int iEntity) {
	int iClient = GetEntPropEnt(iEntity, Prop_Data, "m_hOwner");
	if (Client_IsValid(iClient) && iClient == g_iTargetFollow && g_iClientInstruction == INST_NOP) {
		static char sSceneFile[PLATFORM_MAX_PATH];
		GetEntPropString(iEntity, Prop_Data, "m_iszSceneFile", sSceneFile, sizeof(sSceneFile));
		
		if (StrContains(sSceneFile, "taunt") != -1) {
			FakeClientCommand(g_iClientControl, "taunt");
		}
	}
	
	return Plugin_Continue;
}
*/

public Action Hook_TouchFuncRegenerate(int iEntity, int iOther) {
	if (g_hRecordingBots.FindValue(iOther, RecBot::iEnt) != -1) {
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action OnAutosavePreLoad(int iClient) {
	if (iClient == g_iLastCaller) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

//////// Helpers ////////

void blockFlags() {
	int iEntity = INVALID_ENT_REFERENCE;
	while ((iEntity = FindEntityByClassname(iEntity, "item_teamflag")) != INVALID_ENT_REFERENCE) {
		SDKHook(iEntity, SDKHook_Touch, Hook_TouchFlag);
	}
}

void blockRegen() {
	int iEntity = -1;
	while ((iEntity = FindEntityByClassname(iEntity, "func_regenerate")) != INVALID_ENT_REFERENCE) {
		SDKHook(iEntity, SDKHook_Touch, Hook_TouchFuncRegenerate);
	}
}

bool checkAccess(int iClient) {
	return iClient == 0 || CheckCommandAccess(iClient, "jb_access", ADMFLAG_ROOT) || g_bPlayerGrantAccess[iClient];
}

bool CheckFile(char[] sFilePath, char[] sMapName=NULL_STRING) {
	File hFile = OpenFile(sFilePath, "rb");
	if (!hFile) {
		LogError("Cannot open file: %s", sFilePath);
		return false;
	}

	char sError[256];
	bool bResult = CheckVersion(hFile, sError, sizeof(sError));
	if (!bResult) {
		LogError("%s: %s", sError, sFilePath);
	}

	if (bResult && sMapName[0]) {
		bResult = CheckMap(hFile, sMapName);
	}

	delete hFile;

	return bResult;
}

bool CheckVersion(File hFile, char[] sError, int iMaxLength) {
	int iPosBackup = hFile.Position;

	hFile.Seek(0x0, SEEK_SET);

	char sIdentifier[6];
	if (hFile.ReadString(sIdentifier, sizeof(sIdentifier)) == -1 || !StrEqual("JBREC", sIdentifier)) {
		FormatEx(sError, iMaxLength, "Not a JBREC file");
		hFile.Seek(iPosBackup, SEEK_SET);
		return false;
	}

	hFile.Seek(0x6, SEEK_SET);

	int iVersionMajor;
	int iVersionMinor;
	hFile.ReadUint8(iVersionMajor);
	hFile.ReadUint8(iVersionMinor);
	if (!(iVersionMajor == 1 && iVersionMinor == 0 || iVersionMajor == 0 && iVersionMinor == 9)) {
		FormatEx(sError, iMaxLength, "Incompatible JBREC version (%d.%d)", iVersionMajor, iVersionMinor);

		hFile.Seek(iPosBackup, SEEK_SET);
		return false;
	}

	hFile.Seek(iPosBackup, SEEK_SET);
	return true;
}

bool CheckMap(File hFile, char[] sMapName) {
	int iPosBackup = hFile.Position;

	hFile.Seek(0x28, SEEK_SET);

	char sFileMapName[32];
	hFile.ReadString(sFileMapName, sizeof(sFileMapName));
	
	hFile.Seek(iPosBackup, SEEK_SET);

	return StrEqual(sMapName, sFileMapName, false);
}

void ClearRecBotData(int iID = -1) {
	if (iID == -1) {
		for (int i=0; i<g_hRecordingBots.Length; i++) {
			delete view_as<DataPack>(g_hRecordingBots.Get(i, RecBot::hEquip));
		}

		g_hRecordingBots.Clear();
	} else {
		delete view_as<DataPack>(g_hRecordingBots.Get(iID, RecBot::hEquip));
		g_hRecordingBots.Erase(iID);
	}
}

void ClearRecordings(ArrayList hRecordings) {
	for (int i=0; i<hRecordings.Length; i++) {
		Recording iRecording = hRecordings.Get(i);
		Recording.Destroy(iRecording);
	}
	hRecordings.Clear();

	if (g_bOctreeAvailable) {
		Octree.Destroy(g_iSpatialIdx);
	}
}

void ClearRecEntities() {
	for (int i=0; i<g_hRecordingEntities.Length; i++) {
		RecEnt eRecEnt;
		g_hRecordingEntities.GetArray(i, eRecEnt);

		int iEntity = EntRefToEntIndex(eRecEnt.iRef);
		if (iEntity && IsValidEntity(iEntity)) {
			g_hRecordingEntities.Erase(i);
			AcceptEntityInput(iEntity, "Kill");

			// Kill triggers OnEntityDestroyed immediately and removes from list
			i--;
		}
	}

	g_hRecordingEntities.Clear();
}

void doPlayerQueueAdd(int iClient, Recording iRecording, Obs_Mode iMode) {
	if (g_hQueue == null) {
		return;
	}

	Queue eQueue;
	eQueue.iClient = iClient;
	eQueue.iRecording = iRecording;
	eQueue.fTime = (g_iWarmupFrames + iRecording.Length) / 66.0;
	eQueue.iTeam = TF2_GetClientTeam(iClient);
	eQueue.iObsMode = iMode;
	g_hQueue.PushArray(eQueue);
}

void doPlayerQueueRemove(int iClient) {
	if (g_hQueue == null) {
		return;
	}

	int iIdx;
	while ((iIdx = g_hQueue.FindValue(iClient)) != -1) {
		if (g_hQueuePanel[iClient] != null) {
			delete g_hQueuePanel[iClient];
		}
		
		g_hQueue.Erase(iIdx);
	}
}

void doPlayerQueueClear() {
	if (g_hQueue == null) {
		return;
	}

	for (int i = 0; i < g_hQueue.Length; i++) {
		Queue eQueue;
		g_hQueue.GetArray(i, eQueue);
		
		int iClient = eQueue.iClient;
		if (g_hQueuePanel[iClient] != null) {
			delete g_hQueuePanel[iClient];
		}
	}
	
	g_hQueue.Clear();
}

void doRespawn(int iClient) {
	g_eSpawnFreeze[iClient].iFrames = RESPAWN_FREEZE_FRAMES;
	if (TF2_GetClientTeam(iClient) != g_eSpawnFreeze[iClient].iTeam) {
		ChangeClientTeam(iClient, view_as<int>(g_eSpawnFreeze[iClient].iTeam));
	}

	if (TF2_GetPlayerClass(iClient) != g_eSpawnFreeze[iClient].iClass) {
		TF2_SetPlayerClass(iClient, g_eSpawnFreeze[iClient].iClass);
	}
	
	Respawn(iClient);
}

void doReturn() {
	if (g_iClientInstructionPost & INST_RETURN) {
		if (g_iClientInstructionPost & INST_SPEC) {
			setRespawnTeam(g_iClientOfInterest, TFTeam_Spectator);
			Client_SetObserverMode(g_iClientOfInterest, OBS_MODE_ROAMING);
			FakeClientCommand(g_iClientOfInterest, "spec_mode 6");
		} else {
			int iCOI = g_iClientOfInterest;
			
			g_iLastCaller = iCOI;
			g_iLastCallTime = GetTime();

			Call_StartForward(g_hClientRestoreForward);
			Call_PushCell(iCOI);
			Call_Finish();

			doRespawn(iCOI); // Wipes COI in doFullStop()
			doReturnSpectators(iCOI);
		}
	}
}

void doReturnSpectators(int iTarget) {
	if (!Client_IsValid(iTarget) || !IsClientInGame(iTarget)) {
		return;
	}

	for (int i=0; i<g_hSpecList.Length; i++) {
		int iClient = g_hSpecList.Get(i);
		if (IsClientInGame(iClient)) {
			Obs_Mode iObserverMode = Client_GetObserverMode(iClient);

			// FIXME: What if observing idle RecBot not in recording playback?
			if ((iObserverMode == OBS_MODE_IN_EYE || iObserverMode == OBS_MODE_CHASE) && g_hRecordingBots.FindValue(Client_GetObserverTarget(iClient), RecBot::iEnt) != -1) {
				FakeClientCommand(iClient, "spec_player \"%N\"", iTarget);
			}
		}
	}
	
	g_hSpecList.Clear();
}

void doFullStop() {
	g_iClientInstruction = INST_NOP;
	g_iClientInstructionPost = INST_NOP;
	g_fPlaybackSpeed = 1.0;
	g_iInterFrameIdx = 0;
	g_iInterFrameLength = 0;
	
	// Release all buttons
	for (int i=1; i<=MaxClients; i++) {
		g_eClientState[i].iButtons = 0;
		g_eClientState[i].iLastUpdate = 0;
	}

	if (g_bShowKeysAvailable && Client_IsValid(g_iClientOfInterest) && IsClientInGame(g_iClientOfInterest)) {
		ResetShowKeys(g_iClientOfInterest);
	}
	
	g_iClientOfInterest = -1;
	g_hProjMap.Clear();
	
	ResetBubbleRotation(g_iRecording);
	if (!g_bLocked) {
		SetAllBubbleAlpha(255);
	}
	
	int iEntity = INVALID_ENT_REFERENCE;
	while ((iEntity = FindEntityByClassname(iEntity, "tf_projectile_*")) != INVALID_ENT_REFERENCE) {
		SDKUnhook(iEntity, SDKHook_VPhysicsUpdatePost, Hook_ProjVPhysics);
	}

	for (int i=0; i<g_hRecordingClients.Length; i++) {
		int iRecClient = g_hRecordingClients.Get(i, RecBot::iEnt);

		int iFlags = GetEntityFlags(iRecClient);
		SetEntityFlags(iRecClient, iFlags & ~FL_FROZEN);
		SetEntityMoveType(iRecClient, MOVETYPE_WALK);
	}

	g_hRecordingClients.Clear();
	ClearRecEntities();
	g_hPlaybackQueue.Clear();
	g_hRecBufferFrames = null;
	
	SetPlaybackSpeed(1.0);

	if (g_hBotNameAuthors.BoolValue) {
		char sBotName[MAX_NAME_LENGTH];
		g_hBotName.GetString(sBotName, sizeof(sBotName));

		// Rename bots after playback
		for (int i=0; i<g_hRecordingBots.Length; i++) {
			char sBotNameUnique[MAX_NAME_LENGTH];
			if (i == 0) {
				sBotNameUnique = sBotName;
			} else {
				Format(sBotNameUnique, sizeof(sBotNameUnique), "%s-%d", sBotName, i);
			}

			int iRecBot = g_hRecordingBots.Get(i, RecBot::iEnt);
			SetEntPropString(iRecBot, Prop_Data, "m_szNetname", sBotNameUnique);
			SetClientName(iRecBot, sBotNameUnique);
		}
	}
}

void Equip(int iBotID) {
	int iClient = g_hRecordingBots.Get(iBotID, RecBot::iEnt);
	if (!Client_IsValid(iClient) || !IsClientInGame(iClient)) {
		LogError("Cannot equip for client not in game: bot %d, client %d", iBotID, iClient);
		return;
	}

	DataPack hEquip = g_hRecordingBots.Get(iBotID, RecBot::hEquip);
	hEquip.Reset(false);
	if (!hEquip.IsReadable(4)) {
		return;
	}

	int iEntity = INVALID_ENT_REFERENCE;
	while ((iEntity = FindEntityByClassname(iEntity, "tf_wearable")) != INVALID_ENT_REFERENCE) {
		if (Entity_GetOwner(iEntity) == iClient) {
			AcceptEntityInput(iEntity, "Kill");
		}
	}

	int iWeaponAvailable = 0;
	char sClassName[128];
	for (int iSlot = TFWeaponSlot_Primary; iSlot <= TFWeaponSlot_Item2; iSlot++) {
		int iCurrentWeapon = GetPlayerWeaponSlot(iClient, iSlot);

		int iItemDefIdx = hEquip.ReadCell();
		if (iItemDefIdx) {
			// Need to read from pack even if not re-equipping
			hEquip.ReadString(sClassName, sizeof(sClassName));

			if (IsValidEntity(iCurrentWeapon) && iItemDefIdx == GetItemDefIndex(iCurrentWeapon)) {
				if (!iWeaponAvailable) {
					iWeaponAvailable = iCurrentWeapon;
				}
				
				continue;
			}
			
			TF2_RemoveWeaponSlot(iClient, iSlot);

			Handle hWeapon = TF2Items_CreateItem(OVERRIDE_ALL | PRESERVE_ATTRIBUTES | FORCE_GENERATION);
			TF2Items_SetClassname(hWeapon, sClassName);
			TF2Items_SetItemIndex(hWeapon, iItemDefIdx);
			//TF2Items_SetQuality(hWeapon, GetEntProp(iWeapon, Prop_Send, "m_iEntityQuality"));
			//TF2Items_SetLevel(hWeapon, GetEntProp(iWeapon, Prop_Send, "m_iEntityLevel"));
			
			int iWeapon = TF2Items_GiveNamedItem(iClient, hWeapon);
			delete hWeapon;
			
			EquipPlayerWeapon(iClient, iWeapon);

			if (!iWeaponAvailable) {
				iWeaponAvailable = iWeapon;
			}
		} else {
			TF2_RemoveWeaponSlot(iClient, iSlot);
		}
	}
	
	if (iWeaponAvailable) {
		Client_SetActiveWeapon(iClient, iWeaponAvailable);
		float fTime = GetGameTime();
		SetEntPropFloat(iWeaponAvailable, Prop_Send, "m_flNextPrimaryAttack", fTime);
		SetEntPropFloat(iWeaponAvailable, Prop_Send, "m_flNextSecondaryAttack", fTime);
	}
}

void EquipRec(int iBotID, Recording iRecording, bool bImmediate = true) {
	if (!iRecording) {
		return;
	}

	DataPack hEquip = g_hRecordingBots.Get(iBotID, RecBot::hEquip);
	hEquip.Reset(true);
	
	ClientInfo iClientInfo = iRecording.ClientInfo.Get(iBotID);

	char sClassName[128];
	for (int iSlot = TFWeaponSlot_Primary; iSlot <= TFWeaponSlot_Item2; iSlot++) {
		int iItemDefIdx = iClientInfo.GetEquipItemDefIdx(iSlot);
		hEquip.WriteCell(iItemDefIdx);

		if (iItemDefIdx) {
			iClientInfo.GetEquipClassName(iSlot, sClassName, sizeof(sClassName));
			hEquip.WriteString(sClassName);
		}
	}

	if (bImmediate) {
		Equip(iBotID);
	}
}

FindResult FindNearestRecording(float fPos[3], TFClassType iClass, Recording &iClosestRecord, int iEquipFilterItemDefIdx=0) {
	bool bSearchedClass = false;
	
	iClosestRecord = NULL_RECORDING;
	float fClosestDistance = MAX_NEARBY_SEARCH_DISTANCE;
	
	if (!g_hRecordings.Length) {
		return NO_RECORDING;
	}

	ArrayList hRecordings;
	int iRecordingsTotal; 

	if (g_bOctreeAvailable && g_iSpatialIdx) {
		hRecordings = new ArrayList();
		iRecordingsTotal = g_iSpatialIdx.Find(fPos, MAX_NEARBY_SEARCH_DISTANCE, hRecordings);
	} else {
		hRecordings = g_hRecordings;
		iRecordingsTotal = g_hRecordings.Length;
	}

	float fPosRecord[3];
	for (int i=0; i<iRecordingsTotal; i++) {
		Recording iRecording = hRecordings.Get(i);
		ArrayList hClientInfo = iRecording.ClientInfo;

		for (int j=0; j<hClientInfo.Length; j++) {
			ClientInfo iClientInfo = hClientInfo.Get(j);

			if (iClass > TFClass_Unknown && iClientInfo.Class != iClass && !(g_hAllowMedic.BoolValue && iClass == TFClass_Medic)) {
				continue;
			}

			bSearchedClass = true;

			if (iEquipFilterItemDefIdx && iClass == TFClass_Soldier) {
				int iSlot, iItemDefIdx;
				iRecording.GetEquipFilter(iSlot, iItemDefIdx);

				if (iItemDefIdx) {
					if (iItemDefIdx != iEquipFilterItemDefIdx) {
						continue;
					}
				} else {
					// Skip stock if searching for Original or Beggar's Bazooka recordings
					switch (iEquipFilterItemDefIdx) {
						case 513, 730: {
							continue;
						}
					}
				}
			}
			
			iClientInfo.GetStartPos(fPosRecord);
			fPosRecord[2] += 20.0; // In case origin is buried inside ground due to floating-point imprecision
			
			float fVecDist = GetVectorDistance(fPosRecord, fPos);
			if (fVecDist < MAX_NEARBY_SEARCH_DISTANCE && fVecDist < fClosestDistance) {
				Handle hTr = TR_TraceRayFilterEx(fPos, fPosRecord, MASK_SHOT_HULL, RayType_EndPoint, traceHitEnvironment);
				if (!TR_DidHit(hTr)) {
					float fEndPoint[3];
					TR_GetEndPosition(fEndPoint, hTr);

					if (FloatAbs(GetVectorDistance(fPos, fEndPoint) - fVecDist) < 10.0) {
						iClosestRecord	= iRecording;
						fClosestDistance = fVecDist;
					}
				}
				delete hTr;
			}
		}
	}

	if (hRecordings != g_hRecordings) {
		delete hRecordings;
	}
	
	if (!iClosestRecord) {
		if (!bSearchedClass) {
			return NO_CLASS_RECORDING;
		}
		
		return NO_NEARBY_RECORDING;
	}
	
	return FOUND_RECORDING;
}

void findTargetFollow() {
	if (g_hInteractive.IntValue == 0 || g_hQueue.Length > 0 || !g_hRecordingBots.Length) {
		g_iTargetFollow = -1;
		return;
	}

	// g_iTargetFollow already set to client from doShowMe
	int iClientClosest = g_iClientFollow;
	if (Client_IsValid(iClientClosest) && (!IsClientInGame(iClientClosest) || !g_bInteract[iClientClosest])) {
		iClientClosest = -1;
	}
	
	// TODO: Multiple bot follow target
	int iRecBot = g_hRecordingBots.Get(0, RecBot::iEnt);

	float fPos[3], fPosOther[3];
	GetClientAbsOrigin(iRecBot, fPos);
	
	float fMinDist;
	switch (g_hInteractive.IntValue) {
		case 1: {
			if (Client_IsValid(iClientClosest)) {
				GetClientAbsOrigin(iClientClosest, fPosOther);
				fMinDist = GetVectorDistance(fPos, fPosOther);
			}
		}
		case 2: {
			static int iClients[MAXPLAYERS];		
			int iClientsCount = GetClientsInRange(fPos, RangeType_Visibility, iClients, sizeof(iClients));
			
			fMinDist = MAX_TARGET_FOLLOW_DISTANCE;
			
			TFTeam iTeam = TF2_GetClientTeam(iRecBot);
			for (int i = 0; i < iClientsCount; i++) {
				TFTeam iClientTeam = TF2_GetClientTeam(iClients[i]);
				if (IsFakeClient(iClients[i]) || !g_bInteract[iClients[i]] || iClientTeam <= TFTeam_Spectator || iClientTeam != iTeam) {
					continue;
				}
				
				GetClientAbsOrigin(iClients[i], fPosOther);
				if (FloatAbs(fPosOther[2] - fPos[2]) > 1000.0) {
					continue;
				}
				
				Handle hTr = TR_TraceRayFilterEx(fPos, fPosOther, MASK_SHOT_HULL, RayType_EndPoint, traceHitEnvironment);
				if (!TR_DidHit(hTr)) {
					float fDist = GetVectorDistance(fPos, fPosOther);
					if (fDist < fMinDist) {
						fMinDist = fDist;
						iClientClosest = iClients[i];
					}
				}
				delete hTr;
			}
		}
	}
	
	g_iClientFollow = iClientClosest;
	g_iTargetFollow = iClientClosest;
	
	// TODO: Bot following
	/*
	if (Client_IsValid(iClientClosest) && !g_bLocked) {
		GetClientAbsOrigin(iClientClosest, fPosOther);
		fMinDist = GetVectorDistance(fPos, fPosOther);
	
		Recording iClosestRecord;
		if (FindNearestRecording(fPos, TF2_GetPlayerClass(g_iClientControl), iClosestRecord) == FOUND_RECORDING) {
			if (g_iRecording == iClosestRecord || LoadFrames(iClosestRecord)) {
				g_iRecording = iClosestRecord;
				
				int idx = iClosestRecord.Length - 1;
				float fPosEnd[3];
				fPosEnd[0] = g_aShadowBuffer[idx][Snapshot_fPosX];
				fPosEnd[1] = g_aShadowBuffer[idx][Snapshot_fPosY];
				fPosEnd[2] = g_aShadowBuffer[idx][Snapshot_fPosZ];
				
				GetClientAbsOrigin(iClientClosest, fPosOther);
				if (GetVectorDistance(fPosOther, fPosEnd) < fMinDist) {
					g_iTargetFollow = EntRefToEntIndex(iClosestRecord.NodeModel);
				}
			} else {
				// Not yet downloaded, do prefetch
				fetchRecording(iClosestRecord, true);
			}
		}
	}
	*/
}

bool getCookieBool(int iClient, Handle hCookie, bool &bValue) {
	char sBuffer[8];
	GetClientCookie(iClient, hCookie, sBuffer, sizeof(sBuffer));
	
	if (sBuffer[0]) {
		bValue = StringToInt(sBuffer) != 0;
		return true;
	}
	
	return false;
}

bool getCookieFloat(int iClient, Handle hCookie, float &fValue) {
	char sBuffer[8];
	GetClientCookie(iClient, hCookie, sBuffer, sizeof(sBuffer));
	
	if (sBuffer[0]) {
		fValue = StringToFloat(sBuffer);
		return true;
	}
	
	return false;
}

bool getCookieInt(int iClient, Handle hCookie, int &fValue) {
	char sBuffer[8];
	GetClientCookie(iClient, hCookie, sBuffer, sizeof(sBuffer));
	
	if (sBuffer[0]) {
		fValue = StringToInt(sBuffer);
		return true;
	}
	
	return false;
}

bool LoadRecording(Recording iRecording) {
	char sFilePath[PLATFORM_MAX_PATH];
	iRecording.GetFilePath(sFilePath, sizeof(sFilePath));

	iRecording.FileSize = FileSize(sFilePath);

	File hFile = OpenFile(sFilePath, "rb");
	if (!hFile) {
		LogError("%T: %s", "Cannot Local Play", LANG_SERVER, sFilePath);
		return false;
	}

	char sError[256];
	if (!CheckVersion(hFile, sError, sizeof(sError))) {
		LogError("%s: %s", sError, sFilePath);
		delete hFile;
		return false;
	}

	hFile.Seek(0x8, SEEK_SET);
	int iTimestamp;
	hFile.ReadInt32(iTimestamp);
	iRecording.Timestamp = iTimestamp;

	hFile.Seek(0xC, SEEK_SET);
	int iFrames, iLength;
	hFile.ReadInt32(iFrames);
	iRecording.FramesExpected = iFrames;
	hFile.ReadInt32(iLength);
	iRecording.Length = iLength;

	if (!iFrames || !iLength) {
		LogError("Recording has no frames: %s", sFilePath);
		delete hFile;
		return false;
	}
	
	ArrayList hRecBufferFrames = iRecording.Frames;
	hRecBufferFrames.Clear();
	hFile.Seek(0x18, SEEK_SET);
	int iPosFrameIndex;
	hFile.ReadInt32(iPosFrameIndex);
	hFile.Seek(iPosFrameIndex, SEEK_SET);
	for (int i=0; i<iFrames; i++) {
		int iFrameIdx;
		hFile.ReadInt32(iFrameIdx);
		hRecBufferFrames.Push(iFrameIdx);
	}

	hFile.Seek(0x28, SEEK_SET);

	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

	char sFileMapName[32];
	hFile.ReadString(sFileMapName, sizeof(sFileMapName));
	if (!iRecording.Repo && !StrEqual(sMapName, sFileMapName, false)) {
		LogError("Map mismatch (%s): %s", sFileMapName, sFilePath);
		delete hFile;
		return false;
	}

	hFile.Seek(0x1C, SEEK_SET);
	int iPosClientData;
	hFile.ReadInt32(iPosClientData);
	hFile.Seek(iPosClientData, SEEK_SET);

	int iRecClients;
	hFile.ReadUint8(iRecClients);

	if (!iRecClients) {
		LogError("Recording has no clients: %s", sFilePath);
		delete hFile;
		return false;
	}

	ArrayList hClientInfo = iRecording.ClientInfo;

	// Clear existing info, such as from repo listing
	for (int i=0; i<hClientInfo.Length; i++) {
		ClientInfo.Destroy(hClientInfo.Get(i));
	}
	hClientInfo.Clear();

	for (int i=0; i<iRecClients; i++) {
		ClientInfo iClientInfo = ClientInfo.Instance();

		int iTeam;
		hFile.ReadUint8(iTeam);
		iClientInfo.Team = view_as<TFTeam>(iTeam);

		int iClass;
		hFile.ReadUint8(iClass);
		iClientInfo.Class = view_as<TFClassType>(iClass);

		for (int iSlot=TFWeaponSlot_Primary; iSlot<=TFWeaponSlot_Item2; iSlot++) {
			int iItemDefIdx;
			hFile.ReadInt32(iItemDefIdx);

			iClientInfo.SetEquipItemDefIdx(iSlot, iItemDefIdx);

			if (iItemDefIdx) {
				char sClassName[128];
				hFile.ReadString(sClassName, sizeof(sClassName));
				iClientInfo.SetEquipClassName(iSlot, sClassName);
			}
		}

		hClientInfo.Push(iClientInfo);
	}

	if (hClientInfo.Length) {
		ClientInfo iClientInfo = hClientInfo.Get(0);
		if (iClientInfo.Class == TFClass_Soldier) {
			int iItemDefIdx = iClientInfo.GetEquipItemDefIdx(TFWeaponSlot_Primary);
			// Add filter if recording has Original or Beggar's Bazooka
			switch (iItemDefIdx) {
				case 513, 730: {
					iRecording.SetEquipFilter(TFWeaponSlot_Primary, iItemDefIdx);
				}
			}
		}
	}

	hFile.Seek(0x20, SEEK_SET);
	int iPosClientNames;
	hFile.ReadInt32(iPosClientNames);
	hFile.Seek(iPosClientNames, SEEK_SET);

	for (int i=0; i<iRecClients; i++) {
		ClientInfo iClientInfo = hClientInfo.Get(i);

		char sName[32];
		hFile.ReadString(sName, sizeof(sName));
		iClientInfo.SetName(sName);

		char sAuthID[32];
		hFile.ReadString(sAuthID, sizeof(sAuthID));
		iClientInfo.SetAuthID(sAuthID);
	}					

	int iPosFrameData;
	hFile.Seek(0x14, SEEK_SET);
	hFile.ReadInt32(iPosFrameData);
	hFile.Seek(iPosFrameData+4, SEEK_SET); // Skip FRAME header

	float fStartPos[3];
	float fStartAng[3];

	for (int i=0; i<iRecClients; i++) {
		hFile.Seek(4, SEEK_CUR); // Skip client header
		hFile.ReadInt32(view_as<int>(fStartPos[0]));
		hFile.ReadInt32(view_as<int>(fStartPos[1]));
		hFile.ReadInt32(view_as<int>(fStartPos[2]));
		hFile.Seek(12, SEEK_CUR); // Skip velocity
		hFile.ReadInt32(view_as<int>(fStartAng[0]));
		hFile.ReadInt32(view_as<int>(fStartAng[1]));
		hFile.Seek(8, SEEK_CUR); // Skip ang[2] and buttons

		ClientInfo iClientInfo = hClientInfo.Get(i);
		iClientInfo.SetStartPos(fStartPos);
		iClientInfo.SetStartAng(fStartAng);
	}

	delete hFile;

	return true;
}

void LoadRecordings(bool bUseCachedRepoIndex = false) {
	ClearRecordings(g_hRecordings);
	
	char sFilePath[PLATFORM_MAX_PATH];
	
	if (g_hUseRepo.BoolValue) {
		if (bUseCachedRepoIndex) {
			BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "%s/%s", CACHE_FOLDER, INDEX_FILE_NAME);
			if (!FileExists(sFilePath)) {
				FetchRepository();
			} else {
				ParseIndex(sFilePath);
			}
		} else {
			FetchRepository();
		}
	}

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), g_sRecSubDir);
	if (!DirExists(sPath)) {
		CreateDirectory(sPath, 509);
	}
	
	DirectoryListing hDir = OpenDirectory(sPath);
	if (hDir == null) {
		return;
	}

	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));
	
	Regex hFileRegex = new Regex("^([\\w_]+)\\-[\\d_]+");

	FileType iFileType;
	char sFile[PLATFORM_MAX_PATH];
	char sFileBase[PLATFORM_MAX_PATH];
	
	while (hDir.GetNext(sFile, sizeof(sFile), iFileType)) {
		if (iFileType != FileType_File) {
			continue;
		}

		// Check file extension
		int iExt = FindCharInString(sFile, '.', true);
		if (iExt == -1 || !StrEqual(sFile[iExt], ".jmp", false)) {
			continue;
		}
		
		// Skip opening file if naming scheme matches but map does not
		// Proceed to file check for irregularly named files
		if (hFileRegex.Match(sFile) > 0 && hFileRegex.GetSubString(1, sFileBase, sizeof(sFileBase))) {
			if (!StrEqual(sFileBase, sMapName, false)) {
				continue;
			}
		}

		FormatEx(sFilePath, sizeof(sFilePath), "%s/%s", sPath, sFile);
		ReplaceString(sFilePath, sizeof(sFilePath), "\\\0", "/", true); // Windows

		if (!CheckFile(sFilePath, sMapName)) {
			continue;
		}

		Recording iRecording = Recording.Instance();
		iRecording.SetFilePath(sFilePath);

		if (LoadRecording(iRecording)) {
			g_hRecordings.Push(iRecording);
		} else {
			Recording.Destroy(iRecording);
		}
	}

	delete hFileRegex;
	delete hDir;

	SortADTArrayCustom(g_hRecordings, Sort_Recordings);

	if (!g_hUseRepo.BoolValue) {
		CreateSpatialIndex();
	}
}

bool LoadFrames(Recording iRecording) {
	if  (!iRecording) {
		return false;
	}
	
	char sFilePath[PLATFORM_MAX_PATH];
	iRecording.GetFilePath(sFilePath, sizeof(sFilePath));
	
	if (g_hDebug.BoolValue) {
		int iFilePart = FindCharInString(sFilePath, '/', true);
		CPrintToChatAll("{dodgerblue}[jb] {white}%t: %s (%s)", "Load", sFilePath[iFilePart+1], FileExists(sFilePath) ? "exists" : "notfound");
	}
	
	if (!FileExists(sFilePath)) {
		return false;
	}
	
	File hFile = OpenFile(sFilePath, "rb");
	if (hFile == null) {
		return false;
	}

	char sError[256];
	if (!CheckVersion(hFile, sError, sizeof(sError))) {
		LogError("%s: %s", sError, sFilePath);
		delete hFile;

		return false;
	}

	hFile.Seek(0xC, SEEK_SET);
	int iFrames, iLength;
	hFile.ReadInt32(iFrames);
	hFile.ReadInt32(iLength);
	iRecording.Length = iLength;

	int iRecBufferUsed = iRecording.Length;
	ArrayList hRecBufferFrames = iRecording.Frames;

	int iPosFrameData;
	hFile.Seek(0x14, SEEK_SET);
	hFile.ReadInt32(iPosFrameData);
	hFile.Seek(iPosFrameData, SEEK_SET);

	if (iRecording.Repo) {
		int iSize = FileSize(sFilePath);
		// Offset + buffer used + frame index block
		int iSizeExpected = iPosFrameData + iRecBufferUsed + hRecBufferFrames.Length;
		if (iSize < iSizeExpected) {
			LogError("%T: %s (%d/%d KB) -- %T", "Cannot Load Incomplete", LANG_SERVER, sFilePath, iSize/1000, iSizeExpected/1000, "Delete", LANG_SERVER);
			if (!iRecording.Downloading) {
				DeleteFile(sFilePath);
			}

			delete hFile;

			return false;
		}
	} else if (!FileSize(sFilePath)) {
		LogError("%T: %s (0 KB) -- %T", "Cannot Load Incomplete", LANG_SERVER, sFilePath, "Delete", LANG_SERVER);
		delete hFile;

		return false;
	}
	
	g_hRecBuffer.Clear();
	any aFrameData;
	for (int i=0; i<iRecBufferUsed; i++) {
		if (!hFile.ReadInt32(aFrameData)) {
			LogError("%T (%d/%d B): %s", "Unexpected EOF", LANG_SERVER, i, iRecBufferUsed, sFilePath);
			delete hFile;

			return false;
		}

		g_hRecBuffer.Push(aFrameData);
	}

	int iPosEntData;
	hFile.Seek(0x24, SEEK_SET);
	hFile.ReadInt32(iPosEntData);
	hFile.Seek(iPosEntData+4, SEEK_SET);
	
	int iEntTypes;
	hFile.ReadUint8(iEntTypes);

	g_hRecordingEntTypes.Clear();
	char sClassName[128];
	for (int i=0; i<iEntTypes; i++) {
		hFile.ReadString(sClassName, sizeof(sClassName));
		g_hRecordingEntTypes.PushString(sClassName);
	}

	hRecBufferFrames.Clear();
	hFile.Seek(0x18, SEEK_SET);
	int iPosFrameIndex;
	hFile.ReadInt32(iPosFrameIndex);
	hFile.Seek(iPosFrameIndex, SEEK_SET);
	for (int i=0; i<iFrames; i++) {
		int iFrameIdx;
		hFile.ReadInt32(iFrameIdx);
		hRecBufferFrames.Push(iFrameIdx);
	}

	g_iRecBufferUsed = iRecBufferUsed;
	g_hRecBufferFrames = hRecBufferFrames;
	
	delete hFile;
	
	return true;
}

void CreateSpatialIndex() {
	if (!g_bOctreeAvailable || !g_hRecordings.Length) {
		return;
	}

	// Compute octree boundaries

	float fMin[3] = {POSITIVE_INFINITY, ...};
	float fMax[3] = {NEGATIVE_INFINITY, ...};
	float fStartPos[3];

	for (int i=0; i<g_hRecordings.Length; i++) {
		Recording iRecording = g_hRecordings.Get(i);
		ArrayList hClientInfo = iRecording.ClientInfo;

		for (int j=0; j<hClientInfo.Length; j++) {
			ClientInfo iClientInfo = hClientInfo.Get(j);
			iClientInfo.GetStartPos(fStartPos);

			fMin[0] = fStartPos[0] < fMin[0] ? fStartPos[0] : fMin[0];
			fMin[1] = fStartPos[1] < fMin[1] ? fStartPos[1] : fMin[1];
			fMin[2] = fStartPos[2] < fMin[2] ? fStartPos[2] : fMin[2];

			fMax[0] = fStartPos[0] > fMax[0] ? fStartPos[0] : fMax[0];
			fMax[1] = fStartPos[1] > fMax[1] ? fStartPos[1] : fMax[1];
			fMax[2] = fStartPos[2] > fMax[2] ? fStartPos[2] : fMax[2];
		}
	}

	float fCenter[3];
	AddVectors(fMin, fMax, fCenter);
	ScaleVector(fCenter, 0.5);

	float fHalfWidth[3];
	SubtractVectors(fMax, fMin, fHalfWidth);
	ScaleVector(fHalfWidth, 0.5);

	float fMaxHalfWidth = fHalfWidth[0];
	fMaxHalfWidth = fHalfWidth[1] > fMaxHalfWidth ? fHalfWidth[1] : fMaxHalfWidth;
	fMaxHalfWidth = fHalfWidth[2] > fMaxHalfWidth ? fHalfWidth[2] : fMaxHalfWidth;

	fMaxHalfWidth += 50.0; // Prevents Octree out of bounds

	if (g_iSpatialIdx) {
		Octree.Destroy(g_iSpatialIdx);
	}

	g_iSpatialIdx = Octree.Instance(fCenter, fMaxHalfWidth, 20);

	// Insert all recording start positions into octree

	for (int i=0; i<g_hRecordings.Length; i++) {
		Recording iRecording = g_hRecordings.Get(i);
		ArrayList hClientInfo = iRecording.ClientInfo;

		for (int j=0; j<hClientInfo.Length; j++) {
			ClientInfo iClientInfo = hClientInfo.Get(j);
			iClientInfo.GetStartPos(fStartPos);

			g_iSpatialIdx.Insert(fStartPos, iRecording);
		}
	}
}

ArrayList GetSaveStates() {
	ArrayList hSaveStates = new ArrayList();

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), g_sRecSubDir);
	if (!DirExists(sPath)) {
		CreateDirectory(sPath, 509);
	}

	DirectoryListing hDir = OpenDirectory(sPath);
	if (hDir == null) {
		return hSaveStates;
	}

	char sFilePath[PLATFORM_MAX_PATH];
	char sFile[PLATFORM_MAX_PATH];
	char sSaveID[32];

	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

	char sRegExp[64];
	FormatEx(sRegExp, sizeof(sRegExp), "^%s-(\\d+)", sMapName);

	Regex hFileRegex = new Regex(sRegExp);

	FileType iFileType;
	while (hDir.GetNext(sFile, sizeof(sFile), iFileType)) {
		if (iFileType != FileType_File) {
			continue;
		}

		// Check file extension
		int iExt = FindCharInString(sFile, '.', true);
		if (iExt == -1 || !StrEqual(sFile[iExt], ".save", false)) {
			continue;
		}

		// Skip opening file if naming scheme matches but map does not
		// Skip irregularly named files
		if (hFileRegex.Match(sFile) < 0 || !hFileRegex.GetSubString(1, sSaveID, sizeof(sSaveID))) {
			continue;
		}

		FormatEx(sFilePath, sizeof(sFilePath), "%s/%s", sPath, sFile);
		ReplaceString(sFilePath, sizeof(sFilePath), "\\\0", "/", true); // Windows

		if (!CheckFile(sFilePath, sMapName)) {
			continue;
		}

		int iSaveID = StringToInt(sSaveID);
		if (iSaveID) {
			Recording iRecording = Recording.Instance();

			iRecording.SetFilePath(sFilePath);
			if (!LoadRecording(iRecording)) {
				LogError("Failed to load save slot %d: %s", iSaveID, sFilePath);

				Recording.Destroy(iRecording);
				hSaveStates.Set(iSaveID-1, NULL_RECORDING);
				continue;
			}

			while (iSaveID > hSaveStates.Length) {
				hSaveStates.Push(NULL_RECORDING);
			}

			hSaveStates.Set(iSaveID-1, iRecording);
		}
	}

	delete hFileRegex;
	delete hDir;

	return hSaveStates;
}

bool LoadState(Recording iRecording) {
	if (!LoadRecording(iRecording)) {
		return false;
	}

	ArrayList hClientInfo = iRecording.ClientInfo;
	for (int i=0; i<hClientInfo.Length; i++) {
		int iRecBot = g_hRecordingBots.Get(i);
		ClientInfo iClientInfo = hClientInfo.Get(i);

		TF2_SetPlayerClass(iRecBot, iClientInfo.Class);
		ChangeClientTeam(iRecBot, view_as<int>(iClientInfo.Team));

		RequestFrame(Respawn, iRecBot);
		TF2_RespawnPlayer(iRecBot);
	}

	if (LoadFrames(iRecording)) {
		g_iRecording = iRecording;
		g_hRecBufferFrames = iRecording.Frames;
		g_iRecBufferFrame = g_hRecBufferFrames.Length-1 - g_hRewindWaitFrames.IntValue;
		g_iRecBufferIdx = g_hRecBufferFrames.Get(g_iRecBufferFrame - g_hRewindWaitFrames.IntValue);

		PrintToServer("Trying to load save state at frame %d, idx=%d", g_iRecBufferFrame, g_iRecBufferIdx);
		RespawnFrameRecEnt(g_iRecBufferFrame - g_hRewindWaitFrames.IntValue);
		g_iRewindWaitFrames = g_hRewindWaitFrames.IntValue;
		g_iClientInstruction = INST_RECD | INST_REWIND;

		return true;
	}

	g_iRecording = NULL_RECORDING;
	return false;
}

void ResetBubbleRotation(Recording iRecording) {
	if (iRecording) {
		int iBubble = EntRefToEntIndex(iRecording.NodeModel);
		if (IsValidEntity(iBubble)) {
			// Primary author
			ClientInfo iClientInfo = iRecording.ClientInfo.Get(0);
			float fBubbleAng[3] = {0.0, ...};
			iClientInfo.GetStartAng(fBubbleAng);
			fBubbleAng[0] = 0.0;

			if (IsValidEntity(EntRefToEntIndex(iRecording.WeaponModel))) {
				fBubbleAng[1] = 90.0;
			} else {
				fBubbleAng[1] = float((RoundFloat(fBubbleAng[1]) + 90) % 360);
			}

			Entity_SetAbsAngles(iBubble, fBubbleAng);
		}
	}
}

bool SaveFile(char[] sFilePath) {
	File hFile = OpenFile(sFilePath, "wb");
	if (hFile == null) {
		//CReplyToCommand(iClient, "{dodgerblue}[jb] {white}%t: %s", "Cannot File Write", sPath);
		return false;
	}
	
	hFile.WriteString("JBREC", true); // Identifier
	
	// 0x6
	hFile.WriteInt8(REC_FORMAT_VERSION_MAJOR); // File format version major
	hFile.WriteInt8(REC_FORMAT_VERSION_MINOR); // File format version minor

	// 0x8
	hFile.WriteInt32(g_iRecording.Timestamp);

	// 0xC
	ArrayList hRecBufferFrames = g_iRecording.Frames;
	hFile.WriteInt32(hRecBufferFrames.Length);

	// 0x10
	hFile.WriteInt32(g_iRecBufferUsed);

	// 0x14
	int iMetaPosFrameData = hFile.Position;
	hFile.WriteInt32(0);

	// 0x18
	int iMetaPosFrameIndex = hFile.Position;
	hFile.WriteInt32(0);

	// 0x1C
	int iMetaPosClientData = hFile.Position;
	hFile.WriteInt32(0);

	// 0x20
	int iMetaPosClientNames = hFile.Position;
	hFile.WriteInt32(0);

	// 0x24
	int iMetaPosEntData = hFile.Position;
	hFile.WriteInt32(0);
	
	// 0x28
	int iPosMapName = hFile.Position;
	hFile.Write(view_as<int>({0, 0, 0, 0, 0, 0, 0, 0}), 8, 4);

	// 0x48
	// TODO: Custom call bubble location

	int iPosClientData = hFile.Position;
	hFile.Seek(iMetaPosClientData, SEEK_SET);
	hFile.WriteInt32(iPosClientData);

	hFile.Seek(iPosMapName, SEEK_SET);
	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));
	hFile.WriteString(sMapName, true);

	hFile.Seek(iPosClientData, SEEK_SET);

	ArrayList hClientInfo = g_iRecording.ClientInfo;

	char sClassName[128];

	// Lookup 0x1C for this address
	hFile.WriteInt8(hClientInfo.Length);
	for (int i=0; i<hClientInfo.Length; i++) {
		ClientInfo iClientInfo = view_as<ClientInfo>(hClientInfo.Get(i));

		hFile.WriteInt8(view_as<int>(iClientInfo.Team));
		hFile.WriteInt8(view_as<int>(iClientInfo.Class));

		for (int iSlot=TFWeaponSlot_Primary; iSlot<=TFWeaponSlot_Item2; iSlot++) {
			int iItemDefIdx = iClientInfo.GetEquipItemDefIdx(iSlot);
			hFile.WriteInt32(iItemDefIdx);

			if (iItemDefIdx) {	
				iClientInfo.GetEquipClassName(iSlot, sClassName, sizeof(sClassName));
				hFile.WriteString(sClassName, true);
			}
		}
	}

	int iPosClientNames = hFile.Position;
	hFile.Seek(iMetaPosClientNames, SEEK_SET);
	hFile.WriteInt32(iPosClientNames);
	hFile.Seek(iPosClientNames, SEEK_SET);

	// Lookup 0x20 for this address
	for (int i=0; i<hClientInfo.Length; i++) {
		ClientInfo iClientInfo = view_as<ClientInfo>(hClientInfo.Get(i));

		char sName[32];
		iClientInfo.GetName(sName, sizeof(sName));
		hFile.WriteString(sName, true);	

		char sAuthID[32];
		iClientInfo.GetAuthID(sAuthID, sizeof(sAuthID));
		hFile.WriteString(sAuthID, true);
	}

	int iPosEntData = hFile.Position;
	hFile.Seek(iMetaPosEntData, SEEK_SET);
	hFile.WriteInt32(iPosEntData);
	hFile.Seek(iPosEntData, SEEK_SET);

	// Lookup 0x24 for this address
	hFile.WriteInt32(g_iRecordingEntTotal);
	hFile.WriteInt8(g_hRecordingEntTypes.Length);

	for (int i=0; i<g_hRecordingEntTypes.Length; i++) {
		g_hRecordingEntTypes.GetString(i, sClassName, sizeof(sClassName));

		hFile.WriteString(sClassName, true);
	}

	int iPosFrameData = hFile.Position;
	hFile.Seek(iMetaPosFrameData, SEEK_SET);
	hFile.WriteInt32(iPosFrameData);
	hFile.Seek(iPosFrameData, SEEK_SET);

	// Lookup 0x14 for this address 
	for (int i=0; i<g_iRecBufferUsed; i++) {
		hFile.WriteInt32(g_hRecBuffer.Get(i));
	}
	
	int iPosFrameIndex = hFile.Position;
	hFile.Seek(iMetaPosFrameIndex, SEEK_SET);
	hFile.WriteInt32(iPosFrameIndex);
	hFile.Seek(iPosFrameIndex, SEEK_SET);

	// Lookup 0x18 for this address 
	for (int i=0; i<hRecBufferFrames.Length; i++) {
		hFile.WriteInt32(hRecBufferFrames.Get(i));
	}
	
	FlushFile(hFile);
	delete hFile;

	return true;
}

void SetAllBubbleAlpha(int iAlpha) {
	for (int i=0; i<g_hRecordings.Length; i++) {
		Recording iRecording = g_hRecordings.Get(i);
		SetBubbleAlpha(iRecording, iAlpha);
	}
}

void SetBubbleAlpha(Recording iRecording, int iAlpha) {
	int iNModel = iRecording.NodeModel;
	int iWModel = iRecording.WeaponModel;
	
	if (IsValidEntity(iNModel) && IsValidEntity(iWModel)) {
		if (iRecording.Repo) {
			SetEntityRenderColor(iNModel, 255, 255, 255, iAlpha);
			
		} else {
			SetEntityRenderColor(iNModel, g_iLocalRecColor[0], g_iLocalRecColor[1], g_iLocalRecColor[2], iAlpha);
		}

		SetEntityRenderColor(iWModel, 255, 255, 255, iAlpha);
	}
}

void setProjectileGlow(int iEntity) {
	if (!IsValidEntity(iEntity)) {
		return;
	}

	char sTargetName[32];
	Entity_GetName(iEntity, sTargetName, sizeof(sTargetName));
	if (!sTargetName[0]) {
		FormatEx(sTargetName, sizeof(sTargetName), "proj%i", iEntity);
		Entity_SetName(iEntity, sTargetName);
	}

	int iGlowEntity = CreateEntityByName("tf_glow");

	SetVariantString("!activator");
	AcceptEntityInput(iGlowEntity, "SetParent", iEntity, iGlowEntity); 

	DispatchKeyValue(iGlowEntity, "targetname", "ProjectileGlow");
	DispatchKeyValue(iGlowEntity, "target", sTargetName);
	DispatchKeyValue(iGlowEntity, "Mode", "0");
	DispatchSpawn(iGlowEntity);
	AcceptEntityInput(iGlowEntity, "Enable");
	Entity_SetAbsOrigin(iGlowEntity, view_as<float>({ 0.0, 0.0, 0.0 }) );

	SetVariantColor(g_iProjTrailColor);
	AcceptEntityInput(iGlowEntity, "SetGlowColor");
}

void setRespawnTeam(int iClient, TFTeam iTeam) {
	g_eSpawnFreeze[iClient].iTeam = iTeam;
}

void setRespawnClass(int iClient, TFClassType iClass) {
	g_eSpawnFreeze[iClient].iClass = iClass;
}

void setRespawn(int iClient, float fPos[3], float fAng[3]) {
	g_eSpawnFreeze[iClient].fPos = fPos;
	g_eSpawnFreeze[iClient].fAng = fAng;
}

void setRobotModel(int iClient) {
	char sModel[64];
	char sClassName[10];
	
	TFClassType iClass = TF2_GetPlayerClass(iClient);
	if (!iClass) {
		return;
	}
	
	if (iClass == TFClass_DemoMan) {
		strcopy(sClassName, sizeof(sClassName), "demo"); // MvM model uses demo for short
	} else {
		TF2_GetClassName(iClass, sClassName, sizeof(sClassName));
	}
	FormatEx(sModel, sizeof(sModel), "models/bots/%s/bot_%s.mdl", sClassName, sClassName);
	
	SetVariantString(sModel);
	AcceptEntityInput(iClient, "SetCustomModel");
	SetEntProp(iClient, Prop_Send, "m_bUseClassAnimations", 1);
}

bool SetupBot(int iBots=1) {
	if (g_hRecordingBots.Length >= iBots || g_bShuttingDown) {
		return true;
	}

	doFullStop();

	char sBotName[MAX_NAME_LENGTH];
	g_hBotName.GetString(sBotName, sizeof(sBotName));

	for (int i=g_hRecordingBots.Length; i<iBots; i++) {
		char sBotNameUnique[MAX_NAME_LENGTH];
		if (i == 0) {
			sBotNameUnique = sBotName;
		} else {
			Format(sBotNameUnique, sizeof(sBotNameUnique), "%s-%d", sBotName, i);
		}

		int iRecBot = BotController_CreateBot(sBotNameUnique);
		if (!Client_IsValid(iRecBot)) {
			LogError("%t", "Cannot Create Bot");
			return false;
		}

		SetupBotImmunity(iRecBot);

		RecBot eRecBot;
		eRecBot.iEnt = iRecBot;
		eRecBot.hEquip = new DataPack();
		g_hRecordingBots.PushArray(eRecBot);

		CreateTimer(5.0, Timer_BotJoinExecute, GetClientSerial(iRecBot), TIMER_FLAG_NO_MAPCHANGE);
	}
	
	return true;
}

void SetupBotImmunity(int iClient) {
	AdminId iAdmin = CreateAdmin("Bot");
	SetAdminFlag(iAdmin, Admin_Reservation, true);
	SetAdminImmunityLevel(iAdmin, g_hBotImmunity.IntValue);
	SetUserAdmin(iClient, iAdmin, true);
}

void SetupQueue() {
	if (g_hQueueTimer == null) {
		g_hQueueTimer = CreateTimer(1.0, Timer_Queue, 0, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

void RefreshModels() {
	if (!g_hBubble.BoolValue) {
		return;
	}

	ArrayList hTemp = g_hLastVisibleRecordings;
	g_hLastVisibleRecordings = g_hVisibleRecordings;
	g_hVisibleRecordings = hTemp;
	g_hVisibleRecordings.Clear();

	int iLastVisibleRecordingsLength = g_hLastVisibleRecordings.Length;
// 	for (int i=0; i<iLastVisibleRecordingsLength; i++) {
// 		Recording iRecording = g_hLastVisibleRecordings.Get(i);
// 		iRecording.ResetVisibility();
// 	}

	ArrayList hRemodelRecordings = new ArrayList();

	if (g_bOctreeAvailable && g_iSpatialIdx) {
		ArrayList hRecordings = new ArrayList();

		for (int i=1; i<=MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i)) {
				float fPos[3];
				GetClientAbsOrigin(i, fPos);

				int iRecordingsTotal = g_iSpatialIdx.Find(fPos, MAX_NEARBY_SEARCH_DISTANCE, hRecordings);

				for (int j=0; j<iRecordingsTotal; j++) {
					Recording iRecording = hRecordings.Get(j);
					bool bPreviouslyVisible = IsRecordingVisible(iRecording, i);

					if (IsRecordingVisible(iRecording, i, true)) {
						if (g_hVisibleRecordings.FindValue(iRecording) == -1) {
							g_hVisibleRecordings.Push(iRecording);
						}
					} else if (bPreviouslyVisible && hRemodelRecordings.FindValue(iRecording) == -1) {
						// Delete models as a workaround to force game client to respect parent entity transmission hierarchy once recreated so both can be hidden again.
						// FIXME: This will glitch models for a currently playing recording.
						//        Use a recording's custom start location/angle when implemented to seamlessly continue spin during playback.

						RemoveModels(iRecording);
						hRemodelRecordings.Push(iRecording);
					}
				}

				hRecordings.Clear();
			}
		}

		delete hRecordings;
	} else {
		int iRecordingsTotal = g_hRecordings.Length;

		for (int i=0; i<iRecordingsTotal; i++) {
			Recording iRecording = g_hRecordings.Get(i);

			// Primary author
			ClientInfo iClientInfo = iRecording.ClientInfo.Get(0);

			float fPos[3], fPosClient[3];
			iClientInfo.GetStartPos(fPos);
			fPos[2] += 20.0;

			static int iClients[MAXPLAYERS+1];

			bool bVisible = false;
			int iClientsNearby = GetClientsInRange(fPos, RangeType_Visibility, iClients, sizeof(iClients));
			for (int j=0; j<iClientsNearby; j++) {
				bool bPreviouslyVisible = IsRecordingVisible(iRecording, iClients[j]);
				bool bVisibility = IsRecordingVisible(iRecording, iClients[j], true);

				if (!bVisibility && bPreviouslyVisible && hRemodelRecordings.FindValue(iRecording) == -1) {
					RemoveModels(iRecording);
					hRemodelRecordings.Push(iRecording);
				}

				if (!bVisible) {
					GetClientEyePosition(iClients[j], fPosClient);
					bVisible |= bVisibility && GetVectorDistance(fPos, fPosClient) < MAX_NEARBY_SEARCH_DISTANCE;
				}
			}

			if (bVisible) {
				g_hVisibleRecordings.Push(iRecording);
			}
		}
	}

	delete hRemodelRecordings;

	int iVisibleRecordingsLength = g_hVisibleRecordings.Length;

	for (int i=0; i<iVisibleRecordingsLength; i++) {
		Recording iRecording = g_hVisibleRecordings.Get(i);

		bool bHasModel = iRecording.NodeModel != INVALID_ENT_REFERENCE;
		if (bHasModel) {
			continue;
		}

		// Primary author
		ClientInfo iClientInfo = iRecording.ClientInfo.Get(0);

		float fPos[3], fAng[3];
		iClientInfo.GetStartPos(fPos);
		iClientInfo.GetStartAng(fAng);

		int iWeaponEntity = INVALID_ENT_REFERENCE;
		TFClassType iClass = iClientInfo.Class;

		static char sWeaponModel[64];
		switch (iClass) {
			case TFClass_Soldier: {
				sWeaponModel = HINT_MODEL_ROCKET;
			}
			case TFClass_DemoMan: {
				sWeaponModel = HINT_MODEL_STICKY;
			}
			default: {
				sWeaponModel[0] = '\0';
			}
		}

		if (sWeaponModel[0] && (iWeaponEntity = CreateEntityByName("prop_dynamic")) != INVALID_ENT_REFERENCE) {
			char sKey[32];
			FormatEx(sKey, sizeof(sKey), "_jumpbot_rec_weapon:%d", iRecording);
			g_hBubbleLookup.SetValue(sKey, iRecording);

			SetEntityModel(iWeaponEntity, sWeaponModel);

			SetEntPropFloat(iWeaponEntity, Prop_Data, "m_flModelScale", 0.75);
			DispatchKeyValue(iWeaponEntity, "Solid", "0");
			DispatchKeyValue(iWeaponEntity, "targetname", sKey);
			DispatchSpawn(iWeaponEntity);
			SetEntityRenderMode(iWeaponEntity, RENDER_TRANSALPHA);

			iRecording.WeaponModel = EntIndexToEntRef(iWeaponEntity);

			float fPosOffset[3];
			fPosOffset = fPos;
			fPosOffset[2] += 9.0;

			float fAngOffset[3];
			fAngOffset[0] = 0.0;
			fAngOffset[1] = 90.0 + float((RoundFloat(fAng[1]) - 90) % 360);

			TeleportEntity(iWeaponEntity, fPosOffset, fAngOffset, NULL_VECTOR);

			SDKHook(iWeaponEntity, SDKHook_StartTouch, Hook_StartTouchInfo);
			SDKHook(iWeaponEntity, SDKHook_EndTouch, Hook_EndTouchInfo);
			SDKHook(iWeaponEntity, SDKHook_SetTransmit, Hook_Entity_SetTransmit);
		}

		int iNodeEntity = CreateEntityByName("prop_dynamic");
		if (IsValidEntity(iNodeEntity)) {
			char sKey[32];
			FormatEx(sKey, sizeof(sKey), "_jumpbot_rec_node:%d", iRecording);

			SetEntityModel(iNodeEntity, HINT_MODEL_MARKER);
			SetEntPropFloat(iNodeEntity, Prop_Data, "m_flModelScale", 0.5);
			SetEntProp(iNodeEntity, Prop_Data, "m_CollisionGroup", COLLISION_GROUP_PLAYER);
			SetEntProp(iNodeEntity, Prop_Data, "m_usSolidFlags", FSOLID_NOT_SOLID | FSOLID_TRIGGER);
			DispatchKeyValue(iNodeEntity, "targetname", sKey);
			DispatchSpawn(iNodeEntity);
			SetEntityRenderMode(iNodeEntity, RENDER_TRANSALPHA);

			if (!iRecording.Repo) {
				SetEntityRenderColor(iNodeEntity, g_iLocalRecColor[0], g_iLocalRecColor[1], g_iLocalRecColor[2], 255);
			}

			iRecording.NodeModel = EntIndexToEntRef(iNodeEntity);

			float fAngOffset[3], fPosOffset[3];
			g_hBubbleLookup.SetValue(sKey, iRecording);

			if (iWeaponEntity == INVALID_ENT_REFERENCE) {
				fPosOffset = fPos;
				fPosOffset[2] += 20.0;

				fAngOffset[1] = float(RoundFloat(fAng[1] + 90) % 360);

				SDKHook(iNodeEntity, SDKHook_StartTouch, Hook_StartTouchInfo);
				SDKHook(iNodeEntity, SDKHook_EndTouch, Hook_EndTouchInfo);
				SDKHook(iNodeEntity, SDKHook_SetTransmit, Hook_Entity_SetTransmit);
			} else {
				Entity_SetParent(iNodeEntity, iWeaponEntity);

				fPosOffset[2] = 11.0;

				fAngOffset[1] = 90.0;
			}

			TeleportEntity(iNodeEntity, fPosOffset, fAngOffset, NULL_VECTOR);
		}

		if (g_iRecording == iRecording && g_iClientInstruction & (INST_RECD | INST_PLAY)) {
			SetBubbleAlpha(iRecording, 50);
		}
	}

	for (int i=0; i<iLastVisibleRecordingsLength; i++) {
		Recording iRecording = g_hLastVisibleRecordings.Get(i);
		if (g_hVisibleRecordings.FindValue(iRecording) == -1) {
			RemoveModels(iRecording);
		}
	}
}

void RemoveAllModels() {
	for (int i=0; i<g_hRecordings.Length; i++) {
		RemoveModels(g_hRecordings.Get(i));
	}

	g_hBubbleLookup.Clear();
}

void RemoveModels(Recording iRecording) {
	int iEntityRef = iRecording.NodeModel;
	if (iEntityRef != INVALID_ENT_REFERENCE) {
		int iEntity = EntRefToEntIndex(iEntityRef);
		if (iEntity > 0 && IsValidEntity(iEntity)) {
			AcceptEntityInput(iEntity, "Kill");

			char sKey[32];
			Entity_GetName(iEntity, sKey, sizeof(sKey));
			g_hBubbleLookup.Remove(sKey);
		}

		iRecording.NodeModel = INVALID_ENT_REFERENCE;
	}
	
	iEntityRef = iRecording.WeaponModel;
	if (iEntityRef != INVALID_ENT_REFERENCE) {
		int iEntity = EntRefToEntIndex(iEntityRef);
		if (iEntity > 0 && IsValidEntity(iEntity)) {
			AcceptEntityInput(iEntity, "Kill");

			char sKey[32];
			Entity_GetName(iEntity, sKey, sizeof(sKey));
			g_hBubbleLookup.Remove(sKey);
		}

		iRecording.WeaponModel = INVALID_ENT_REFERENCE;
	}
}

void TE_SendToAllInRangeVisible(float fPos[3]) {
	static int iClients[MAXPLAYERS];
	int iClientCount = GetClientsInRange(fPos, RangeType_Visibility, iClients, sizeof(iClients));
	for (int i = 0; i < iClientCount; i++) {
		if (!g_bTrail[iClients[i]]) {
			iClients[i] = iClients[iClientCount-i-1];
			iClientCount--;
		}
	}
	
	TE_Send(iClients, iClientCount);
}

void TF2_GetClassName(TFClassType iClass, char[] sName, int iLength) {
	char sClass[10][10] = {"unknown", "scout", "sniper", "soldier", "demoman", "medic", "heavy", "pyro", "spy", "engineer"};
	strcopy(sName, iLength, sClass[view_as<int>(iClass)]);
}

void ToTimeDisplay(char[] sBuffer, int iLength, int iTime) {
	if (iTime >= 3600) {
		int iMinutes = iTime / 60;
		int iSeconds = iTime % 60;
		int iHours = iTime / 3600;
		iMinutes %= 60;

		FormatEx(sBuffer, iLength, "%d:%02d:%02d", iHours, iMinutes, iSeconds);
	} else {
		FormatEx(sBuffer, iLength, "%d:%02d", iTime / 60, iTime % 60);
	}
}

int GetItemDefIndex(int iItem) {
	return GetEntProp(iItem, Prop_Send, "m_iItemDefinitionIndex");
}

bool IsRecordingVisible(Recording iRecording, int iClient, bool bRefresh=false) {
	if (IsFakeClient(iClient) || !iRecording) {
		return false;
	}

	if (!bRefresh) {
		return iRecording.GetVisibility(iClient);
	}

	if ((g_hAllowMedic.BoolValue && TF2_GetPlayerClass(iClient) == TFClass_Medic) || g_hDebug.BoolValue) {
		return iRecording.SetVisibility(iClient, true);
	}

	if (TF2_GetClientTeam(iClient) == TFTeam_Spectator) {
		if (iClient == g_iClientOfInterest) {
			return iRecording.SetVisibility(iClient, g_iRecording == iRecording);
		}

		Obs_Mode iObserverMode = Client_GetObserverMode(iClient);
		int iObsTarget = Client_GetObserverTarget(iClient);
		if ((iObserverMode == OBS_MODE_IN_EYE || iObserverMode == OBS_MODE_CHASE) && g_hRecordingBots.FindValue(iObsTarget, RecBot::iEnt) != -1) {
			return iRecording.SetVisibility(iClient, g_iRecording == iRecording);
		}

		return iRecording.SetVisibility(iClient, checkAccess(iClient));
	}

	TFClassType iClass = TF2_GetPlayerClass(iClient);

	int iSlot, iItemDefIdx;
	iRecording.GetEquipFilter(iSlot, iItemDefIdx);

	ArrayList hClientInfo = iRecording.ClientInfo;
	for (int i=0; i<hClientInfo.Length; i++) {
		ClientInfo iClientInfo = hClientInfo.Get(i);
		if (iClass == iClientInfo.Class) {
			if (iItemDefIdx) {
				int iWeapon = GetPlayerWeaponSlot(iClient, iSlot);
				if (iWeapon == -1 || GetItemDefIndex(iWeapon) != iItemDefIdx) {
					return iRecording.SetVisibility(iClient, false);
				}
			} else if (iClass == TFClass_Soldier) {
				int iWeapon = GetPlayerWeaponSlot(iClient, TFWeaponSlot_Primary);
				if (iWeapon == -1) {
					return iRecording.SetVisibility(iClient, false);
				}
				
				// Hide stock recording if player is equipped with Original or Beggar's Bazooka
				switch (GetItemDefIndex(iWeapon)) {
					case 513, 730: {
						return iRecording.SetVisibility(iClient, false);
					}
				}
			}

			return iRecording.SetVisibility(iClient, true);
		}
	}

	return iRecording.SetVisibility(iClient, false);
}

int CloneProjectile(int iEntity, int iOwner=-1) {
	if (iOwner == -1) {
		iOwner = Entity_GetOwner(iEntity);
	}

	char sClassName[128];
	GetEntityClassname(iEntity, sClassName, sizeof(sClassName));

	float fPos[3];
	float fAng[3];
	float fVel[3];
	Entity_GetAbsOrigin(iEntity, fPos);
	Entity_GetAbsAngles(iEntity, fAng);
	Entity_GetAbsVelocity(iEntity, fVel);

	int iLauncher = GetEntProp(iEntity, Prop_Send, "m_hLauncher");
	int iOriginalLauncher = GetEntProp(iEntity, Prop_Send, "m_hOriginalLauncher");
	bool bDefensiveBomb;
	if (HasEntProp(iEntity, Prop_Send, "m_bDefensiveBomb")) {
		bDefensiveBomb = view_as<bool>(GetEntProp(iEntity, Prop_Send, "m_bDefensiveBomb"));
	}

	int iType;
	if (HasEntProp(iEntity, Prop_Send, "m_iType")) {
		iType = GetEntProp(iEntity, Prop_Send, "m_iType");
	}

	iEntity = CreateEntityByName(sClassName);
	if (IsValidEntity(iEntity)) {
		Entity_SetOwner(iEntity, iOwner);

		if (Client_IsValid(iOwner)) {
			SetEntProp(iEntity, Prop_Send, "m_iTeamNum", GetClientTeam(iOwner));
		}

		SetEntProp(iEntity, Prop_Send, "m_hLauncher", iLauncher);
		SetEntProp(iEntity, Prop_Send, "m_hOriginalLauncher", iOriginalLauncher);
		
		if (HasEntProp(iEntity, Prop_Send, "m_bDefensiveBomb")) {
			SetEntProp(iEntity, Prop_Send, "m_bDefensiveBomb", bDefensiveBomb);
		}

		if (HasEntProp(iEntity, Prop_Send, "m_iType")) {
			SetEntProp(iEntity, Prop_Send, "m_iType", iType);
		}
		
		Entity_SetAbsOrigin(iEntity, fPos);
		Entity_SetAbsAngles(iEntity, fAng);
		Entity_SetAbsVelocity(iEntity, fVel);

		DispatchSpawn(iEntity);

		return iEntity;
	}

	return -1;
}

int CreateProjectile(char[] sClassName, float fPos[3], float fAng[3], float fVel[3], int iOwner) {
	int iEntity = CreateEntityByName(sClassName);
	if (IsValidEntity(iEntity)) {
		SetEntProp(iEntity, Prop_Send, "m_iTeamNum", GetClientTeam(iOwner));
		Entity_SetOwner(iEntity, iOwner);
		Entity_SetAbsOrigin(iEntity, fPos);
		Entity_SetAbsAngles(iEntity, fAng);
		Entity_SetAbsVelocity(iEntity, fVel);

		if (StrEqual(sClassName, "tf_projectile_pipe_remote")) {
			SetEntPropEnt(iEntity, Prop_Send, "m_hThrower", iOwner);
			SetEntProp(iEntity, Prop_Send, "m_iType", 1);
		}
	}

	return iEntity;
}

void RegisterRecEnt(int iEntity, int iOwnerEnt, int iAssign=-1) {
	// Check for duplicate hook callback
	int iRef = EntIndexToEntRef(iEntity);
	if (g_hRecordingEntities.FindValue(iRef, RecEnt::iRef) != -1) {
		return;
	}

	char sClassName[128];
	GetEntityClassname(iEntity, sClassName, sizeof(sClassName));

	int iEntType = g_hRecordingEntTypes.FindString(sClassName);
	if (iEntType == -1) {
		iEntType = g_hRecordingEntTypes.Length;
		g_hRecordingEntTypes.PushString(sClassName);
	}

	float fPos[3];
	Entity_GetAbsOrigin(iEntity, fPos);

	for (int i=0; i<g_hRecordingEntities.Length; i++) {
		RecEnt eRecEnt;
		g_hRecordingEntities.GetArray(i, eRecEnt);

		if (eRecEnt.iOwner == iOwnerEnt && !eRecEnt.iRef && eRecEnt.iType == iEntType) {
			eRecEnt.iRef = iRef;
			eRecEnt.fPosPrev = fPos;
			eRecEnt.fPosNext = fPos;
			eRecEnt.iDesyncs = 0;

			g_hRecordingEntities.SetArray(i, eRecEnt);

			return;
		}
	}

	RecEnt eRecEnt;
	eRecEnt.iID = g_iRecordingEntTotal++ % 256;
	eRecEnt.iRef = iRef;
	eRecEnt.iType = iEntType;
	eRecEnt.iMoveType = view_as<int>(GetEntityMoveType(iEntity));
	eRecEnt.iOwner = iOwnerEnt;
	eRecEnt.iAssign = iAssign;
	eRecEnt.fPosPrev = fPos;
	eRecEnt.fPosNext = fPos;
	
	g_hRecordingEntities.PushArray(eRecEnt);
}

void RespawnFrameRecEnt(int iFrame) {
	for (int i=0; i<g_hRecordingEntities.Length; i++) {
		int iRecEntIdx = EntRefToEntIndex(g_hRecordingEntities.Get(i, RecEnt::iRef));
		if (IsValidEntity(iRecEntIdx)) {
			AcceptEntityInput(iRecEntIdx, "Kill");
		}
	}
	g_hRecordingEntities.Clear();

	int iRecBufferIdx = g_hRecBufferFrames.Get(iFrame) + 1; // Skip FRAME header
	
	ArrayList hClients = g_iClientInstruction & INST_RECD ? g_hRecordingClients : g_hRecordingBots;
	iRecBufferIdx += 11 * hClients.Length;

	float fPos[3], fAng[3], fVel[3];

	int iEntType;
	int iOwner = -1;
	int iRecordingEnt = -1;
	while (iRecBufferIdx < g_hRecBuffer.Length && view_as<RecBlockType>(g_hRecBuffer.Get(iRecBufferIdx) & 0xFF) == ENTITY) {
		iRecordingEnt	= (g_hRecBuffer.Get(iRecBufferIdx  ) >>  8) & 0xFF;
		iEntType 		= (g_hRecBuffer.Get(iRecBufferIdx  ) >> 16) & 0xFF;
		iOwner			= (g_hRecBuffer.Get(iRecBufferIdx++) >> 24) & 0xFF;
		
		fPos[0] = g_hRecBuffer.Get(iRecBufferIdx++);
		fPos[1] = g_hRecBuffer.Get(iRecBufferIdx++);
		fPos[2] = g_hRecBuffer.Get(iRecBufferIdx++);
		fVel[0] = g_hRecBuffer.Get(iRecBufferIdx++);
		fVel[1] = g_hRecBuffer.Get(iRecBufferIdx++);
		fVel[2] = g_hRecBuffer.Get(iRecBufferIdx++);
		fAng[0] = g_hRecBuffer.Get(iRecBufferIdx++);
		fAng[1] = g_hRecBuffer.Get(iRecBufferIdx++);
		fAng[2] = g_hRecBuffer.Get(iRecBufferIdx++);

		iOwner = hClients.Get(iOwner);
		if (iEntType >= g_hRecordingEntTypes.Length) {
			// FIXME: Recording patch
			PrintToServer("Bad iEntType reference %d >= %d in entity block", iEntType, g_hRecordingEntTypes.Length);
			continue;
		}

		char sClassName[128];
		g_hRecordingEntTypes.GetString(iEntType, sClassName, sizeof(sClassName));

		if (!sClassName[0]) {
			PrintToServer("Invalid iEntType class name for type %d", iEntType);
			continue;
		}

		//PrintToServer("Respawning for iRecEnt[%d] block, class=%s, owner=%N", iRecordingEnt, sClassName, iOwner);

		PrintToServer("Trying to respawn iEntType type %d: '%s'", iEntType, sClassName);
		int iEntity = CreateProjectile(sClassName, fPos, fAng, fVel, iOwner);
		if (IsValidEntity(iEntity)) {
			RegisterRecEnt(iEntity, iOwner, iRecordingEnt);
			DispatchSpawn(iEntity);
		}
	}
}

bool PrepareBots(Recording iRecording) {
	if (!iRecording) {
		return false;
	}

	ArrayList hClientInfo = iRecording.ClientInfo;

	if (!SetupBot(hClientInfo.Length)) {
		return false;
	}

	if (g_hBotNameAuthors.BoolValue) {
		for (int i=0; i<hClientInfo.Length; i++) {
			ClientInfo iClientInfo = hClientInfo.Get(i);
			
			char sAuthorName[32];
			iClientInfo.GetName(sAuthorName, sizeof(sAuthorName));

			int iRecBot = g_hRecordingBots.Get(i, RecBot::iEnt);

			SetEntPropString(iRecBot, Prop_Data, "m_szNetname", sAuthorName);
			SetClientName(iRecBot, sAuthorName);
		}
	}

	for (int i=0; i<hClientInfo.Length; i++) {
		RecBot eRecBot;
		g_hRecordingBots.GetArray(i, eRecBot);

		int iRecBot = eRecBot.iEnt;
		if (!IsClientInGame(iRecBot)) {
			LogError("Tried using iRecBot=%d but the client is not in-game", i);
			return false;
		}

		ClientInfo iClientInfo = hClientInfo.Get(i);

		float fPos[3];
		iClientInfo.GetStartPos(fPos);
		Entity_SetAbsOrigin(iRecBot, fPos);

		eRecBot.fPosPrev = fPos;
		eRecBot.fPosNext = fPos;

		float fAng[3];
		iClientInfo.GetStartAng(fAng);
		eRecBot.fAngPrev = fAng;
		eRecBot.fAngNext = fAng;

		g_hRecordingBots.SetArray(i, eRecBot);

		g_eClientState[iRecBot].iLastUpdate = GetGameTickCount();
		g_eClientState[iRecBot].fAng = fAng;

		TFClassType iRecClass = iClientInfo.Class;
		TFTeam iRecTeam = iClientInfo.Team;

		if (iRecClass == TFClass_DemoMan) {
			g_eClientState[iRecBot].iButtons = TFWeaponSlot_Secondary << 26;
		}

		bool bRespawnRequired = !IsPlayerAlive(iRecBot);

		if (TF2_GetPlayerClass(iRecBot) != iRecClass) {
			TF2_SetPlayerClass(iRecBot, iRecClass);
			bRespawnRequired = true;
		}

		if (TF2_GetClientTeam(iRecBot) != iRecTeam) {
			ChangeClientTeam(iRecBot, view_as<int>(iRecTeam));
			bRespawnRequired = true;
		}

		if (bRespawnRequired) {
			RequestFrame(Respawn, iRecBot);
		}

		TF2_RemoveCondition(iRecBot, TFCond_Taunting);

		EquipRec(i, iRecording);

		if (g_hRobot.BoolValue) {
			setRobotModel(iRecBot);
		}
	}

	return true;
}

void SetPlaybackSpeedCOI() {
	SetPlaybackSpeed(g_iClientOfInterest == -1 ? 1.0 : g_fSpeed[g_iClientOfInterest]);
}

void SetPlaybackSpeed(float fPlaybackSpeed, int iClient=-1) {
	if (fPlaybackSpeed == 0.0) {
		fPlaybackSpeed = g_iClientOfInterest == -1 ? 1.0 : g_fSpeed[g_iClientOfInterest];
	}

	g_fPlaybackSpeed = fPlaybackSpeed;

	float fRatio = 1.0 / fPlaybackSpeed;
	g_iInterFrameLength = RoundFloat(fRatio);

	if (iClient == -1) {
		for (int i=0; i<g_hRecordingBots.Length; i++) {
			int iRecBot = g_hRecordingBots.Get(i, RecBot::iEnt);

			TF2Attrib_SetByName(iRecBot, "gesture speed increase", g_fPlaybackSpeed);
			
			for (int j=TFWeaponSlot_Primary; j<=TFWeaponSlot_Item2; j++) {
				int iWeaponEquipped = GetPlayerWeaponSlot(iRecBot, j);
				if (iWeaponEquipped != -1) {
					TF2Attrib_SetByName(iWeaponEquipped, "fire rate penalty", fRatio);
					TF2Attrib_SetByName(iWeaponEquipped, "Projectile speed decreased", fPlaybackSpeed);
					TF2Attrib_SetByName(iWeaponEquipped, "Reload time increased", fRatio);
				}
			}
		}
	} else {
		TF2Attrib_SetByName(iClient, "gesture speed increase", g_fPlaybackSpeed);

		for (int i=TFWeaponSlot_Primary; i<=TFWeaponSlot_Item2; i++) {
			int iWeaponEquipped = GetPlayerWeaponSlot(iClient, i);
			if (iWeaponEquipped != -1) {
				TF2Attrib_SetByName(iWeaponEquipped, "fire rate penalty", fRatio);
				TF2Attrib_SetByName(iWeaponEquipped, "Projectile speed decreased", fPlaybackSpeed);
				TF2Attrib_SetByName(iWeaponEquipped, "Reload time increased", fRatio);
			}
		}
	}
}

float InterpAngle(float fAlpha, float fAngleA, float fAngleB) {
	fAngleA = DegToRad(fAngleA);
	fAngleB = DegToRad(fAngleB);
	
	return RadToDeg(ArcTangent2(fAlpha * Sine(fAngleB) + (1.0 - fAlpha) * Sine(fAngleA), fAlpha * Cosine(fAngleB) + (1.0 - fAlpha) * Cosine(fAngleA)));
}

void InterpAngles(float fAlpha, float fAngA[3], float fAngB[3], float fAngResult[3]) {
	fAngResult[0] = InterpAngle(fAlpha, fAngA[0], fAngB[0]);
	fAngResult[1] = InterpAngle(fAlpha, fAngA[1], fAngB[1]);
	fAngResult[2] = InterpAngle(fAlpha, fAngA[2], fAngB[2]);
}

float InterpCoord(float fAlpha, float fCoordA, float fCoordB) {
	return (1.0 - fAlpha) * fCoordA + fAlpha * fCoordB;
}

void InterpCoords(float fAlpha, float fCoordA[3], float fCoordB[3], float fCoordResult[3]) {
	fCoordResult[0] = InterpCoord(fAlpha, fCoordA[0], fCoordB[0]);
	fCoordResult[1] = InterpCoord(fAlpha, fCoordA[1], fCoordB[1]);
	fCoordResult[2] = InterpCoord(fAlpha, fCoordA[2], fCoordB[2]);
}

void CalcCorrectionalVelocity(float fPos[3], float fPosTarget[3], float fVelResult[3]) {
	fVelResult[0] = (fPosTarget[0] - fPos[0]) * 66;
	fVelResult[1] = (fPosTarget[1] - fPos[1]) * 66;
	fVelResult[2] = (fPosTarget[2] - fPos[2]) * 66;
}

//////// Menus ////////

void sendQueuePanel(int iClient) {
	if (g_hQueuePanel[iClient] != null) {
		delete g_hQueuePanel[iClient];
	}
	
	int iAhead = g_hQueue.FindValue(iClient, Queue::iClient);
	if (iAhead == -1) {
		iAhead = g_hQueue.Length;
	}
	
	char sBuffer[256];
	Panel hPanel = new Panel();
	
	SetGlobalTransTarget(iClient);
	FormatEx(sBuffer, sizeof(sBuffer), "== %T ==", "Playback Queue", iClient);
	hPanel.SetTitle(sBuffer);
	
	hPanel.DrawText(" ");
	
	FormatEx(sBuffer, sizeof(sBuffer), "%T", "Players Ahead", iClient, iAhead+1);
	hPanel.DrawText(sBuffer);
	
	float fWaitTime = (g_iClientInstruction & INST_WARMUP) ? g_iWarmupFrames / 66.0 : 0.0;
	fWaitTime += (g_hRecBufferFrames.Length - g_iRecBufferFrame) / 66.0 * g_fPlaybackSpeed;
	if (g_iClientInstruction & INST_PLAYALL) {
		for (int i=0; i<g_hPlaybackQueue.Length; i++) {
			Recording iRecording = g_hPlaybackQueue.Get(i);
			fWaitTime += g_iWarmupFrames / 66.0 + iRecording.FramesExpected / 66.0 * g_fPlaybackSpeed;
		}
	}
	for (int i = 0; i < iAhead; i++) {
		fWaitTime = fWaitTime + view_as<float>(g_hQueue.Get(i, Queue::fTime)) * g_fSpeed[g_hQueue.Get(i, Queue::iClient)];
	}
	int iWaitTimeRounded = RoundFloat(fWaitTime);
	
	FormatEx(sBuffer, sizeof(sBuffer), "%T: %02d:%02d", "Estimated Time About", iClient, iWaitTimeRounded/60, iWaitTimeRounded % 60);
	hPanel.DrawText(sBuffer);
	hPanel.DrawText(" ");
	
	hPanel.CurrentKey = 10;
	FormatEx(sBuffer, sizeof(sBuffer), "%T", "Cancel", iClient);
	hPanel.DrawItem(sBuffer, ITEMDRAW_CONTROL);
	
	hPanel.Send(iClient, MenuHandler_Queue, 1);
	g_hQueuePanel[iClient] = hPanel;
	
	SetGlobalTransTarget(LANG_SERVER);
}

public int MenuHandler_Queue(Menu hMenu, MenuAction iAction, int iClient, int iSelection) {
	if (iAction == MenuAction_Select) {
		delete hMenu;
		doPlayerQueueRemove(iClient);
	}

	return 0;
}

public void CookieMenuHandler_Options(int iClient, CookieMenuAction iAction, any aInfo, char[] sBuffer, int iMaxLength) {
	if (iAction == CookieMenuAction_SelectOption) {
		sendOptionsPanel(iClient);
	}	
}

void sendOptionsPanel(int iClient) {
	char sBuffer[128];
	g_hBotName.GetString(sBuffer, sizeof(sBuffer));
	Format(sBuffer, sizeof(sBuffer), "%s Settings", sBuffer);
	
	Menu hMenu = new Menu(MenuHandler_Options);
	hMenu.SetTitle(sBuffer);
	
	bool bBubble = true;
	getCookieBool(iClient, g_hCookieBubble, bBubble);
	FormatEx(sBuffer, sizeof(sBuffer), bBubble ? "Disable Bubbles" : "Enable Bubbles");
	hMenu.AddItem(NULL_STRING, sBuffer);
	
	bool bTrail = true;
	getCookieBool(iClient, g_hCookieTrail, bTrail);
	FormatEx(sBuffer, sizeof(sBuffer), bTrail ? "Disable Trails" : "Enable Trails");
	hMenu.AddItem(NULL_STRING, sBuffer);
	
	bool bInteract = true;
	getCookieBool(iClient, g_hCookieInteract, bInteract);
	FormatEx(sBuffer, sizeof(sBuffer), bInteract ? "Disable Interactions" : "Enable Interactions");
	hMenu.AddItem(NULL_STRING, sBuffer);
	
	char sPerspectives[4][5] =  { "None", "1st", "", "3rd" };
	
	int iPerspective = g_hShowMeDefault.IntValue;
	getCookieInt(iClient, g_hCookiePerspective, iPerspective);
	FormatEx(sBuffer, sizeof(sBuffer), "Playback Perspective (%s)", sPerspectives[iPerspective]);
	hMenu.AddItem(NULL_STRING, sBuffer);
	
	float fSpeed = 1.0;
	getCookieFloat(iClient, g_hCookieSpeed, fSpeed);
	FormatEx(sBuffer, sizeof(sBuffer), "Playback Speed (%.0f%%)", 100*fSpeed);
	hMenu.AddItem(NULL_STRING, sBuffer);
	
	
	DisplayMenu(hMenu, iClient, 0);
}

void sendSpeedOptionsPanel(int iClient) {
	char sBuffer[128];
	FormatEx(sBuffer, sizeof(sBuffer), "Playback Speed");
	
	Menu hMenu = new Menu(MenuHandler_SpeedOptions);
	hMenu.SetTitle(sBuffer);
	
	hMenu.AddItem("0.25", "25%");
	hMenu.AddItem("0.5", "50%");
	hMenu.AddItem("1.0", "100%");
	
	hMenu.ExitButton = false;
	hMenu.ExitBackButton = true;
	
	DisplayMenu(hMenu, iClient, 0);
}

void sendPerspectiveOptionsPanel(int iClient) {
	char sBuffer[128];
	FormatEx(sBuffer, sizeof(sBuffer), "Playback Perspective");
	
	Menu hMenu = new Menu(MenuHandler_PerspectiveOptions);
	hMenu.SetTitle(sBuffer);
	
	hMenu.AddItem("1", "First-person");
	hMenu.AddItem(NULL_STRING, NULL_STRING, ITEMDRAW_DISABLED);
	hMenu.AddItem("3", "Third-person");
	hMenu.AddItem("0", "None");
	
	hMenu.ExitButton = false;
	hMenu.ExitBackButton = true;
	
	DisplayMenu(hMenu, iClient, 0);
}

void BuildStateMenu(Menu hMenu) {
	ArrayList hSaveStates = GetSaveStates();
	for (int i=0; i<hSaveStates.Length; i++) {
		Recording iRecording = hSaveStates.Get(i);
		char sInfo[32];
		IntToString(i+1, sInfo, sizeof(sInfo));

		if (!iRecording) {
			hMenu.AddItem(sInfo, " -- Empty --", ITEMDRAW_DISABLED);
		} else {
			char sTime[64];
			FormatTime(sTime, sizeof(sTime), "%b %d %G - %r", iRecording.Timestamp);

			char sDisplay[128];
			FormatEx(sDisplay, sizeof(sDisplay), "%s - %4d frames", sTime, iRecording.Frames.Length);
			hMenu.AddItem(sInfo, sDisplay);
		}
	}
}

public int MenuHandler_Options(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			switch (iOption) {
				case 0: {
					// Bubble
					bool bBubble = true;
					getCookieBool(iClient, g_hCookieBubble, bBubble);
					SetClientCookie(iClient, g_hCookieBubble, bBubble ? "0" : "1");
					g_bBubble[iClient] = !bBubble;
					
					sendOptionsPanel(iClient);
				}
				case 1: {
					// Trail
					bool bTrail = true;
					getCookieBool(iClient, g_hCookieTrail, bTrail);
					SetClientCookie(iClient, g_hCookieTrail, bTrail ? "0" : "1");
					g_bTrail[iClient] = !bTrail;
					
					sendOptionsPanel(iClient);
				}
				case 2: {
					// Interactive
					bool bInteract = true;
					getCookieBool(iClient, g_hCookieInteract, bInteract);
					SetClientCookie(iClient, g_hCookieInteract, bInteract ? "0" : "1");
					g_bInteract[iClient] = !bInteract;
					
					sendOptionsPanel(iClient);
				}
				case 3: {
					// Perspective
					sendPerspectiveOptionsPanel(iClient);
				}
				case 4: {
					// Speed
					sendSpeedOptionsPanel(iClient);
				}
			}
		}
		case MenuAction_End: {
			delete hMenu;
		}
	}

	return 0;
}

public int MenuHandler_SpeedOptions(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			char sBuffer[8];
			hMenu.GetItem(iOption, sBuffer, sizeof(sBuffer));
			
			SetClientCookie(iClient, g_hCookieSpeed, sBuffer);
			g_fSpeed[iClient] = StringToFloat(sBuffer);
			
			sendOptionsPanel(iClient);
		}
		
		case MenuAction_Cancel: {
			sendOptionsPanel(iClient);
		}	
		
		case MenuAction_End: {
			delete hMenu;
		}
	}

	return 0;
}


public int MenuHandler_PerspectiveOptions(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			char sBuffer[8];
			hMenu.GetItem(iOption, sBuffer, sizeof(sBuffer));
			
			SetClientCookie(iClient, g_hCookiePerspective, sBuffer);
			g_iPerspective[iClient] = StringToInt(sBuffer);
			
			sendOptionsPanel(iClient);
		}
		
		case MenuAction_Cancel: {
			sendOptionsPanel(iClient);
		}	
		
		case MenuAction_End: {
			delete hMenu;
		}
	}

	return 0;
}

public int MenuHandler_LoadState(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			char sBuffer[32];
			hMenu.GetItem(iOption, sBuffer, sizeof(sBuffer));

			FakeClientCommand(iClient, "jb_state_load %s", sBuffer);

			Menu hNextMenu = new Menu(MenuHandler_LoadState);
			hNextMenu.SetTitle("Load Rec State");
			BuildStateMenu(hNextMenu);
			hNextMenu.Display(iClient, 5);
		}
		case MenuAction_End: {
			delete hMenu;
		}
	}

	return 0;
}

public int MenuHandler_DeleteState(Menu hMenu, MenuAction iAction, int iClient, int iOption) {
	switch (iAction) {
		case MenuAction_Select: {
			char sBuffer[32];
			hMenu.GetItem(iOption, sBuffer, sizeof(sBuffer));

			FakeClientCommand(iClient, "jb_state_delete %s", sBuffer);

			Menu hNextMenu = new Menu(MenuHandler_DeleteState);
			hNextMenu.SetTitle("Delete Rec State");
			BuildStateMenu(hNextMenu);
			hNextMenu.Display(iClient, 5);
		}
		case MenuAction_End: {
			delete hMenu;
		}
	}

	return 0;
}
