#pragma semicolon 1
#pragma dynamic 24576

// #define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.2.4"

#include <sourcemod>
#include <clientprefs>
#include <multicolors>
#include <regex>
#include <ripext>
#include <tf2>

#include <jse_mapinfo>
#include <smlib/strings>

#undef REQUIRE_PLUGIN
#include <mapchooser>

#define API_URL	"https://api.jumpacademy.tf/mapinfo"
#define API_VERSION	"2.0"

#define MIN_TIER			1
#define MAX_REGULAR_TIER	6
#define MAX_EXTENDED_TIER	10

enum struct InfoLookup {
	JSONArray hMapInfoList;
	bool bListView;
	int iPage;
	int iSelectedAuthorIdx;
	float fTimestamp;
}

ConVar g_hCVJoinMessageHold;
ConVar g_hCVExtendedTiers;

Cookie g_hJoinMessageCookie;
Cookie g_hExtendedTiersCookie;
Cookie g_hViewModeCookie;

JSONArray g_hCurrentMapInfoList;

ArrayList g_hLookupStack[MAXPLAYERS+1];

bool g_bJoinMessage[MAXPLAYERS+1];
bool g_bExtendedTiers[MAXPLAYERS+1];
bool g_bListView[MAXPLAYERS+1];

public Plugin myinfo = {
	name = "Jump Server Essentials - Map Info",
	author = PLUGIN_AUTHOR,
	description = "JSE map information module",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	CreateConVar("jse_mapinfo_version", PLUGIN_VERSION, "Jump Server Essentials map info version -- Do not modify",  FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_hCVJoinMessageHold = CreateConVar("jse_mapinfo_joinmessage", "8", "Seconds to show join message panel (0: keep open until dismissed, -1: disable)", FCVAR_NONE, true, -1.0);
	g_hCVExtendedTiers = CreateConVar("jse_mapinfo_extendedtiers", "0", "Default for tier classifications beyond T6 (0: clamp, 1: show)", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	RegConsoleCmd("sm_mi", cmdMapInfo, "Show the map information");
	RegConsoleCmd("sm_mapinfo", cmdMapInfo, "Show the map information");

	g_hJoinMessageCookie = new Cookie("jse_mapinfo_joinmessage", "Show map info on join", CookieAccess_Public);
	g_hExtendedTiersCookie = new Cookie("jse_mapinfo_extendedtiers", "Show extended map tiers beyond T6", CookieAccess_Public);
	g_hViewModeCookie = new Cookie("jse_mapinfo_viewmode", "Default view mode for map info search results", CookieAccess_Public);

	SetCookieMenuItem(CookieMenuHandler_Settings, 0, "Map Info");

	LoadTranslations("common.phrases");
	LoadTranslations("nominations.phrases");
}

public void OnPluginEnd() {
	OnMapEnd();
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int sErrMax) {
	RegPluginLibrary("jse_mapinfo");

	CreateNative("MapInfo_CurrentMap", Native_CurrentMap);
	CreateNative("MapInfo_Lookup", Native_Lookup);
	CreateNative("MapInfo_LookupAll", Native_LookupAll);

	return APLRes_Success;
}

public void OnMapStart() {
	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

	MapInfo_Lookup(MapInfoResponse_FetchFromAPI, -1, true, true, sMapName);

	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && AreClientCookiesCached(i)) {
			OnClientCookiesCached(i);
		}
	}

	CreateTimer(10.0, Timer_MapStartInfo, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd() {
	for (int i=1; i<=MaxClients; i++) {
		ClearLookupStack(i);
	}

	delete g_hCurrentMapInfoList;
}

public void OnConfigsExecuted() {
	g_bExtendedTiers[0] = g_hCVExtendedTiers.BoolValue;
}

public void OnClientPostAdminCheck(int iClient) {
	int iHoldTime = g_hCVJoinMessageHold.IntValue;
	if (iHoldTime != -1 && g_bJoinMessage[iClient]) {
		InitLookupStack(iClient, g_hCurrentMapInfoList);
		ShowMapInfoPanel(iClient, iHoldTime, false);
	}
}

public void OnClientDisconnect(int iClient) {
	ClearLookupStack(iClient);
}

public void OnClientCookiesCached(int iClient) {
	if (IsFakeClient(iClient)) {
		return;
	}

	char sBuffer[8];

	g_hJoinMessageCookie.Get(iClient, sBuffer, sizeof(sBuffer));
	g_bJoinMessage[iClient] = sBuffer[0] ? StringToInt(sBuffer) != 0 : g_hCVJoinMessageHold.IntValue != -1;

	g_hExtendedTiersCookie.Get(iClient, sBuffer, sizeof(sBuffer));
	g_bExtendedTiers[iClient] = sBuffer[0] ? StringToInt(sBuffer) != 0 : g_hCVExtendedTiers.BoolValue;

	g_hViewModeCookie.Get(iClient, sBuffer, sizeof(sBuffer));
	g_bListView[iClient] = sBuffer[0] ? StringToInt(sBuffer) != 0 : false;
}

// Natives

public any Native_CurrentMap(Handle hPlugin, int iArgC) {
	// MapInfoResponse
	Function fnCallback = GetNativeFunction(1);

	any aData = GetNativeCell(2);

	Call_StartFunction(hPlugin, fnCallback);
	Call_PushCell(aData);
	Call_PushCell(g_hCurrentMapInfoList);
	Call_Finish();

	return 0;
}

public int Native_Lookup(Handle hPlugin, int iArgC) {
	// MapInfoResponse
	Function fnCallback = GetNativeFunction(1);

	any aData = GetNativeCell(2);

	bool bExtendedTiers = GetNativeCell(3) != 0;

	bool bExactMatch = GetNativeCell(4) != 0;

	char sSearchTerm[32];
	GetNativeString(5, sSearchTerm, sizeof(sSearchTerm));

	char sAuthorAuthID[32];
	GetNativeString(6, sAuthorAuthID, sizeof(sAuthorAuthID));

	char sAuthorName[32];
	GetNativeString(7, sAuthorName, sizeof(sAuthorName));

	TFClassType iClassType = GetNativeCell(8);
	int iIntendedTier = GetNativeCell(9);
	int iTierS = GetNativeCell(10);
	int iTierD = GetNativeCell(11);

	bool bLayout = GetNativeCell(12);

	DataPack hRequestDataPack = new DataPack();
	hRequestDataPack.WriteCell(hPlugin);
	hRequestDataPack.WriteFunction(fnCallback);
	hRequestDataPack.WriteCell(aData);

	FetchFromAPI(HTTPRequestCallback_NativeFetchFromAPI, hRequestDataPack, bExtendedTiers, bExactMatch, sSearchTerm, sAuthorAuthID, sAuthorName, iClassType, iIntendedTier, iTierS, iTierD, bLayout);

	return 0;
}

public int Native_LookupAll(Handle hPlugin, int iArgC) {
	// MapInfoResponse
	Function fnCallback = GetNativeFunction(1);

	any aData = GetNativeCell(2);

	bool bExtendedTiers = GetNativeCell(3) != 0;
	bool bExactMatch = GetNativeCell(4) != 0;

	char sSearchTerms[8190];
	GetNativeString(5, sSearchTerms, sizeof(sSearchTerms));

	char sSplit[32];
	GetNativeString(6, sSplit, sizeof(sSplit));

	char sAuthorAuthID[32];
	GetNativeString(7, sAuthorAuthID, sizeof(sAuthorAuthID));

	char sAuthorName[32];
	GetNativeString(8, sAuthorName, sizeof(sAuthorName));

	TFClassType iClassType = GetNativeCell(9);
	int iIntendedTier = GetNativeCell(10);
	int iTierS = GetNativeCell(11);
	int iTierD = GetNativeCell(12);

	bool bLayout = GetNativeCell(13);

	char sSearchTermsArray[1024][32];
	int iSearchTerms = ExplodeString(sSearchTerms, sSplit, sSearchTermsArray, sizeof(sSearchTermsArray), sizeof(sSearchTermsArray[]));

	DataPack hRequestDataPack = new DataPack();
	hRequestDataPack.WriteCell(hPlugin);
	hRequestDataPack.WriteFunction(fnCallback);
	hRequestDataPack.WriteCell(aData);

	FetchFromAPI_Multiple(HTTPRequestCallback_NativeFetchFromAPI, hRequestDataPack, bExtendedTiers, bExactMatch, sSearchTermsArray, iSearchTerms, sAuthorAuthID, sAuthorName, iClassType, iIntendedTier, iTierS, iTierD, bLayout);

	return 0;
}

// Custom callbacks

public Action Timer_MapStartInfo(Handle hTimer) {
	int iHoldTime = g_hCVJoinMessageHold.IntValue;
	if (iHoldTime != -1) {
		for (int i=1; i<=MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i) && g_bJoinMessage[i]) {
				InitLookupStack(i, g_hCurrentMapInfoList);
				ShowMapInfoPanel(i, iHoldTime, false);
			}
		}
	}

	return Plugin_Handled;
}

public void MapInfoResponse_FetchFromAPI(any aData, JSONArray hMapInfoList, const char[] sError) {
	if (!hMapInfoList) {
		ThrowError(sError);
	}

	int iCaller = aData;

	if (!hMapInfoList.Length) {
		if (iCaller <= 0) {
			LogError("No map information was found");
		} else {
			CPrintToChat(iCaller, "{dodgerblue}[jse] {white}No map information was found.");
		}

		return;
	}

	if (iCaller == -1) {
		g_hCurrentMapInfoList = view_as<JSONArray>(CloneHandle(hMapInfoList));
	} else {
		if (iCaller) {
			JSONArray hMapInfoListClone = view_as<JSONArray>(CloneHandle(hMapInfoList));
			if (g_hLookupStack[iCaller]) {
				InfoLookup eInfoLookup;
				eInfoLookup.hMapInfoList = hMapInfoListClone;
				eInfoLookup.fTimestamp = GetGameTime();
				g_hLookupStack[iCaller].PushArray(eInfoLookup);
				if (g_bListView[iCaller]) {
					ShowMapInfoListMenu(iCaller);
				} else {
					ShowMapInfoPanel(iCaller);
				}
			} else {
				InitLookupStack(iCaller, hMapInfoListClone);
				if (g_bListView[iCaller]) {
					ShowMapInfoListMenu(iCaller);
				} else {
					ShowMapInfoPanel(iCaller);
				}
			}

		} else {
			char sBuffer[1024];
			for (int i=0; i<hMapInfoList.Length; i++) {
				JSONObject hMapInfo = view_as<JSONObject>(hMapInfoList.Get(i));
				PrintMapInfo(hMapInfo, g_hCVExtendedTiers.BoolValue, sBuffer, sizeof(sBuffer));
				ReplyToCommand(iCaller, sBuffer);
				delete hMapInfo;
			}
		}
	}
}

public void HTTPRequestCallback_NativeFetchFromAPI(HTTPResponse mHTTPResponse, any aData, const char[] sError) {
	DataPack hRequestDataPack = view_as<DataPack>(aData);
	hRequestDataPack.Reset();

	Handle hPlugin = hRequestDataPack.ReadCell();
	Function fnCallback = hRequestDataPack.ReadFunction();
	aData = hRequestDataPack.ReadCell();

	delete hRequestDataPack;

	if (mHTTPResponse.Status != HTTPStatus_OK) {
		char sCallbackError[512];

		if (mHTTPResponse.Status == HTTPStatus_BadRequest) {
			JSONObject hError = view_as<JSONObject>(mHTTPResponse.Data);
			if (hError.HasKey("message")) {
				char sMessage[256];
				hError.GetString("message", sMessage, sizeof(sMessage));
				FormatEx(sCallbackError, sizeof(sCallbackError), "Error while looking up map (%s)", sMessage);

				Call_StartFunction(hPlugin, fnCallback);
				Call_PushCell(aData);
				Call_PushCell(0); // null
				Call_PushString(sCallbackError);
				Call_Finish();

				return;
			}
		}

		FormatEx(sCallbackError, sizeof(sCallbackError), "Unexpected HTTP response code %d while looking up map (%s)", mHTTPResponse.Status, sError);
		Call_StartFunction(hPlugin, fnCallback);
		Call_PushCell(aData);
		Call_PushCell(0); // null
		Call_PushString(sCallbackError);
		Call_Finish();

		return;
	}

	Call_StartFunction(hPlugin, fnCallback);
	Call_PushCell(aData);
	Call_PushCell(mHTTPResponse.Data);
	Call_PushString(NULL_STRING);
	Call_Finish();
}

public void ConVarQueryFinished_DisableHTMLMOTD(QueryCookie iCookie, int iClient, ConVarQueryResult iResult, const char[] sCvarName, const char[] sCvarValue) {
	if (!IsClientInGame(iClient) || !g_hLookupStack[iClient] || !g_hLookupStack[iClient].Length) {
		return;
	}

	InfoLookup eInfoLookup;
	g_hLookupStack[iClient].GetArray(g_hLookupStack[iClient].Length-1, eInfoLookup);

	JSONObject hMapInfo = view_as<JSONObject>(eInfoLookup.hMapInfoList.Get(eInfoLookup.iPage));
	JSONArray hAuthorList = view_as<JSONArray>(hMapInfo.Get("authors"));
	JSONObject hAuthor = view_as<JSONObject>(hAuthorList.Get(eInfoLookup.iSelectedAuthorIdx));

	char sAuthorID[32];
	hAuthor.GetInt64("id", sAuthorID, sizeof(sAuthorID));

	delete hAuthor;
	delete hAuthorList;
	delete hMapInfo;

	char sBuffer[64];
	Format(sBuffer, sizeof(sBuffer), "https://steamcommunity.com/profiles/%s", sAuthorID);

	if (iResult == ConVarQuery_Okay && StringToInt(sCvarValue) == 0) {
		KeyValues hKV = new KeyValues("data");
		hKV.SetString("title", "Steam Profile");
		hKV.SetNum("type", MOTDPANEL_TYPE_URL);
		hKV.SetString("msg", sBuffer);
		hKV.SetNum("customsvr", 1);

		ShowVGUIPanel(iClient, "info", hKV);
		delete hKV;
	} else {
		CPrintToChat(iClient, "{dodgerblue}[jse] {white}Enable HTML MOTD to open profile: {grey}%s", sBuffer);
	}
}

public Action Timer_MapChange(Handle hTimer, Handle hHandle) {
	DataPack hDataPack = view_as<DataPack>(hHandle);
	hDataPack.Reset();

	char sMapName[32];
	hDataPack.ReadString(sMapName, sizeof(sMapName));

	ForceChangeLevel(sMapName, "Admin forced map change");

	return Plugin_Handled;
}

// Helpers

void FetchFromAPI(HTTPRequestCallback fnCallback, any aData, bool bExtendedTiers, bool bExactMatch, const char sSearchTerm[32]="", const char[] sAuthorAuthID=NULL_STRING, const char[] sAuthorName=NULL_STRING, TFClassType iClassType=TFClass_Unknown, int iIntendedTier=0, int iTierS=0, int iTierD=0, bool bLayout=false) {
	char[][] sSearchTerms = new char[1][32];
	strcopy(sSearchTerms[0], 32, sSearchTerm);

	FetchFromAPI_Multiple(fnCallback, aData, bExtendedTiers, bExactMatch, sSearchTerms, sSearchTerm[0] ? 1 : 0, sAuthorAuthID, sAuthorName, iClassType, iIntendedTier, iTierS, iTierD, bLayout);
}

void FetchFromAPI_Multiple(HTTPRequestCallback fnCallback, any aData, bool bExtendedTiers, bool bExactMatch, const char[][] sSearchTerms={}, int iSearchTermsTotal=0, const char[] sAuthorAuthID=NULL_STRING, const char[] sAuthorName=NULL_STRING, TFClassType iClassType=TFClass_Unknown, int iIntendedTier=0, int iTierS=0, int iTierD=0, bool bLayout=false) {
	char sExtendedFilter[13];
	if (bExtendedTiers) {
		sExtendedFilter = "&extended=1";
	}

	char sExactFilter[16];
	if (bExactMatch) {
		sExactFilter = "&exact=1";
	}

	char sClassIntendedTierFilter[32];
	if (iClassType > TFClass_Unknown) {
		if (iIntendedTier) {
			FormatEx(sClassIntendedTierFilter, sizeof(sClassIntendedTierFilter), "&class=%d&tier=%d", iClassType, iIntendedTier);
		} else {
			FormatEx(sClassIntendedTierFilter, sizeof(sClassIntendedTierFilter), "&class=%d", iClassType);
		}
	}

	char sTierFilters[32];
	if (iTierS) {
		FormatEx(sTierFilters, sizeof(sTierFilters), "&tier_s=%d", iTierS);
	}
	if (iTierD) {
		Format(sTierFilters, sizeof(sTierFilters), "%s&tier_d=%d", sTierFilters, iTierD);
	}

	char sAuthorAuthIDFilter[32];
	if (sAuthorAuthID[0]) {
		FormatEx(sAuthorAuthIDFilter, sizeof(sAuthorAuthIDFilter), "&author=%s", sAuthorAuthID);
	}

	char sAuthorFilter[32];
	if (sAuthorName[0]) {
		FormatEx(sAuthorFilter, sizeof(sAuthorFilter), "&authorname=%s", sAuthorName);
	}

	char sSearchTermsFilter[8190];
	if (iSearchTermsTotal) {
		ImplodeStrings(sSearchTerms, iSearchTermsTotal, "+", sSearchTermsFilter, sizeof(sSearchTermsFilter));
		Format(sSearchTermsFilter, sizeof(sSearchTermsFilter), "&filename=%s", sSearchTermsFilter);
	}

	char sLayoutFilter[16];
	if (bLayout) {
		sLayoutFilter = "&layout=1";
	}

	char sURL[8190];
	FormatEx(sURL, sizeof(sURL), "%s?version=%s%s%s%s%s%s%s%s%s", API_URL, API_VERSION, sExtendedFilter, sExactFilter, sClassIntendedTierFilter, sTierFilters, sAuthorAuthIDFilter, sAuthorFilter, sSearchTermsFilter, sLayoutFilter);

#if defined DEBUG
	PrintToServer("Calling API: %s", sURL);
#endif

	HTTPRequest hRequest = new HTTPRequest(sURL);
	hRequest.Get(fnCallback, aData);
}

// Commands

public Action cmdMapInfo(int iClient, int iArgC) {
	TFClassType iFilterClass = TFClass_Unknown;
	int iFilterTier, iFilterTierS, iFilterTierD;

	char sSearchTerm[32];
	if (iArgC == 0) {
		if (GetCmdReplySource() == SM_REPLY_TO_CONSOLE) {
			CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Usage: sm_mi [S/D [intendedtier]] [s/d=tier] [a=authorname] [search terms]");
		}

		if (g_hCurrentMapInfoList == null) {
			CReplyToCommand(iClient, "{dodgerblue}[jse] {white}No map information was found.");
			return Plugin_Handled;
		}

		JSONObject hMapInfo = view_as<JSONObject>(g_hCurrentMapInfoList.Get(0));

		char sBuffer[1024];
		PrintMapInfo(hMapInfo, g_bExtendedTiers[iClient], sBuffer, sizeof(sBuffer));

		delete hMapInfo;

		if (!iClient) {
			ReplyToCommand(iClient, sBuffer);
		} else {
			InitLookupStack(iClient, g_hCurrentMapInfoList);
			ShowMapInfoPanel(iClient, 0, false);
		}
	} else {
		int iArgStart = 1;

		if (iArgC >= 1) {
			char sArg1[32];
			GetCmdArg(1, sArg1, sizeof(sArg1));

			bool bFilterS = StrEqual(sArg1, "s", false);
			bool bFilterD = StrEqual(sArg1, "d", false);

			if (bFilterS || bFilterD) {
				iArgStart = 2;

				iFilterClass = bFilterS ? TFClass_Soldier : TFClass_DemoMan;

				char sArg2[32];
				GetCmdArg(2, sArg2, sizeof(sArg2));

				if (String_IsNumeric(sArg2)) {
					int iTier = StringToInt(sArg2);
					if (MIN_TIER<=iTier<=MAX_EXTENDED_TIER) {
						if (iTier>MAX_REGULAR_TIER && !g_bExtendedTiers[iClient]) {
							CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Extended tiers are not enabled.");
							return Plugin_Handled;
						}

						iArgStart = 3;
						iFilterTier = iTier;
					}  else {
						CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Tiers must be between %d and %d.", MIN_TIER, g_bExtendedTiers[iClient] ? MAX_EXTENDED_TIER : MAX_REGULAR_TIER);
						return Plugin_Handled;
					}
				}
			}
		}

		Regex hRegexInvalid = new Regex("[^A-Za-z0-9_\\-]");

		char[][] sSearchTermsArray = new char[iArgC][32];
		int iSearchTermsTotal = 0;

		char sAuthorName[32];

		for (int i=iArgStart; i<=iArgC; i++) {
			GetCmdArg(i, sSearchTerm, 32);

			if (StrContains(sSearchTerm, "a=", false) == 0 && !hRegexInvalid.Match(sSearchTerm[2])) {
				strcopy(sAuthorName, sizeof(sAuthorName), sSearchTerm[2]);
				continue;
			}

			if (StrContains(sSearchTerm, "author=", false) == 0 && !hRegexInvalid.Match(sSearchTerm[7])) {
				strcopy(sAuthorName, sizeof(sAuthorName), sSearchTerm[7]);
				continue;
			}

			if (StrContains(sSearchTerm, "s=", false) == 0) {
				if (String_IsNumeric(sSearchTerm[2])) {
					int iTier = StringToInt(sSearchTerm[2]);
					if (MIN_TIER<=iTier<=MAX_EXTENDED_TIER) {
						if (iTier>MAX_REGULAR_TIER && !g_bExtendedTiers[iClient]) {
							CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Extended tiers are not enabled.");
							return Plugin_Handled;
						}

						iFilterTierS = iTier;
						continue;
					}  else {
						CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Tiers must be between %d and %d.", MIN_TIER, g_bExtendedTiers[iClient] ? MAX_EXTENDED_TIER : MAX_REGULAR_TIER);
						return Plugin_Handled;
					}
				}
			}

			if (StrContains(sSearchTerm, "d=", false) == 0) {
				if (String_IsNumeric(sSearchTerm[2])) {
					int iTier = StringToInt(sSearchTerm[2]);
					if (MIN_TIER<=iTier<=MAX_EXTENDED_TIER) {
						if (iTier>MAX_REGULAR_TIER && !g_bExtendedTiers[iClient]) {
							CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Extended tiers are not enabled.");
							return Plugin_Handled;
						}

						iFilterTierD = iTier;
						continue;
					}  else {
						CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Invalid tier");
						return Plugin_Handled;
					}
				}
			}

			if (hRegexInvalid.Match(sSearchTerm)) {
				CReplyToCommand(iClient, "{dodgerblue}[jse] {white}Invalid search term: %s", sSearchTerm);
				return Plugin_Handled;
			} else if (sSearchTerm[0]) {
				strcopy(sSearchTermsArray[iSearchTermsTotal++], 32, sSearchTerm);
			}
		}
		delete hRegexInvalid;

		if (iSearchTermsTotal || sAuthorName[0] || iFilterClass || iFilterTier || iFilterTierS || iFilterTierD) {
			char sSearchTerms[8190];
			ImplodeStrings(sSearchTermsArray, iSearchTermsTotal, "+", sSearchTerms, sizeof(sSearchTerms));

			ClearLookupStack(iClient);
			MapInfo_LookupAll(MapInfoResponse_FetchFromAPI, iClient, g_bExtendedTiers[iClient], false, sSearchTerms, "+", _, sAuthorName, iFilterClass, iFilterTier, iFilterTierS, iFilterTierD);
		} else {
			CReplyToCommand(iClient, "{dodgerblue}[jse] {white}No map information was found.");
		}
	}

	return Plugin_Handled;
}

// Helpers

void TF2_GetClassName(TFClassType iClass, char[] sName, iLength) {
	static const char sClass[][] = {"Unknown", "Scout", "Sniper", "Soldier", "Demoman", "Medic", "Heavy", "Pyro", "Spy", "Engineer"};
	strcopy(sName, iLength, sClass[view_as<int>(iClass)]);
}

void PrintMapInfo(JSONObject hMapInfo, bool bExtended, char[] sBuffer, int iBufferLength) {
	if (hMapInfo == null) {
		return;
	}

	char sMapName[32];
	char sAuthorID[20];
	char sAuthorName[64];

	hMapInfo.GetString("filename", sMapName, sizeof(sMapName));

	if (hMapInfo.HasKey("authors")) {
		JSONArray hAuthorList = view_as<JSONArray>(hMapInfo.Get("authors"));
		int iAuthorsLength = hAuthorList.Length;

		if (iAuthorsLength) {
			FormatEx(sBuffer, iBufferLength, "%s by", sMapName);

			for (int i=0; i<iAuthorsLength; i++) {
				JSONObject hAuthor = view_as<JSONObject>(hAuthorList.Get(i));

				hAuthor.GetInt64("id", sAuthorID, sizeof(sAuthorID));
				hAuthor.GetString("name", sAuthorName, sizeof(sAuthorName));

				if (i == 0) {
					Format(sBuffer, iBufferLength, "%s %s", sBuffer, sAuthorName);
				} else if (i < iAuthorsLength-1) {
					Format(sBuffer, iBufferLength, "%s, %s", sBuffer, sAuthorName);
				} else {
					Format(sBuffer, iBufferLength, "%s and %s", sBuffer, sAuthorName);
				}

				delete hAuthor;
			}
		} else {
			FormatEx(sBuffer, iBufferLength, "%s", sMapName);
		}

		delete hAuthorList;
	} else {
		FormatEx(sBuffer, iBufferLength, sMapName);
	}

	if (hMapInfo.HasKey("class")) {
		int iClass = hMapInfo.GetInt("class");

		char sClass[32];
		TF2_GetClassName(view_as<TFClassType>(iClass), sClass, sizeof(sClass));

		Format(sBuffer, iBufferLength, "%s\n    Class: %s", sBuffer, sClass);
	}

	char sTier[16];
	if (hMapInfo.HasKey("tier")) {
		JSONObject hTier = view_as<JSONObject>(hMapInfo.Get("tier"));

		if (hTier.HasKey("3")) {
			int iTier = hTier.GetInt("3");
			if (iTier > MAX_REGULAR_TIER && !bExtended) {
				iTier = MAX_REGULAR_TIER;
			}

			FormatEx(sTier, sizeof(sTier), " S-%d", iTier);
		}

		if (hTier.HasKey("4")) {
			int iTier = hTier.GetInt("4");
			if (iTier > MAX_REGULAR_TIER && !bExtended) {
				iTier = MAX_REGULAR_TIER;
			}

			Format(sTier, sizeof(sTier), "%s D-%d", sTier, iTier);
		}

		if (sTier[0]) {
			Format(sBuffer, iBufferLength, "%s\n     Tier:%s", sBuffer, sTier);
		}

		delete hTier;
	}

	if (hMapInfo.HasKey("type")) {
		char sLayout[16];
		switch (hMapInfo.GetInt("type")) {
			case 1:
				sLayout = "Connectors";
			case 2:
				sLayout = "Doors";
		}

		if (sLayout[0]) {
			Format(sBuffer, iBufferLength, "%s\n   Layout: %s", sBuffer, sLayout);
		}
	}

	if (hMapInfo.HasKey("courses")) {
		int iCourses = hMapInfo.GetInt("courses");

		Format(sBuffer, iBufferLength, "%s\n  Courses: %d", sBuffer, iCourses);

		if (hMapInfo.HasKey("jumps")) {
			int iJumps = hMapInfo.GetInt("jumps");
			Format(sBuffer, iBufferLength, "%s\n    Jumps: %d", sBuffer, iJumps);
		}

		if (hMapInfo.HasKey("bonus")) {
			int iBonus =  hMapInfo.GetInt("bonus");
			Format(sBuffer, iBufferLength, "%s (+%d)", sBuffer, iBonus);
		}
	}

	Format(sBuffer, iBufferLength, "%s\n", sBuffer);
}

void InitLookupStack(int iClient, JSONArray hMapInfoList=null) {
	ClearLookupStack(iClient);
	g_hLookupStack[iClient] = new ArrayList(sizeof(InfoLookup));

	if (hMapInfoList) {
		InfoLookup eInfoLookup;
		eInfoLookup.hMapInfoList = hMapInfoList;
		eInfoLookup.iSelectedAuthorIdx = -1;
		eInfoLookup.fTimestamp = GetGameTime();
		g_hLookupStack[iClient].PushArray(eInfoLookup);
	}
}

void ClearLookupStack(int iClient) {
	ArrayList hLookupStack = g_hLookupStack[iClient];
	if (!hLookupStack) {
		return;
	}

	InfoLookup eInfoLookup;
	int iLength = hLookupStack.Length;
	for (int i=0; i<iLength; i++) {
		hLookupStack.GetArray(i, eInfoLookup);
		if (eInfoLookup.hMapInfoList != g_hCurrentMapInfoList) {
			delete eInfoLookup.hMapInfoList;
		}
	}

	delete g_hLookupStack[iClient];
}

// Menus

public void CookieMenuHandler_Settings(int iClient, CookieMenuAction iAction, any aInfo, char[] sBuffer, int iMaxLength) {
	if (iAction == CookieMenuAction_SelectOption) {
		ShowSettingsPanel(iClient);
	}
}

void ShowSettingsPanel(int iClient) {
	char sBuffer[64];

	Panel hPanel = new Panel();
	hPanel.SetTitle("Map Info");

	FormatEx(sBuffer, sizeof(sBuffer), "[%s] Show current map on join", g_bJoinMessage[iClient] ? "x" : " ");
	hPanel.DrawItem(sBuffer);

	FormatEx(sBuffer, sizeof(sBuffer), "[%s] Use tiers beyond T6", g_bExtendedTiers[iClient] ? "x" : " ");
	hPanel.DrawItem(sBuffer);

	FormatEx(sBuffer, sizeof(sBuffer), "[%s] Show results as lists", g_bListView[iClient] ? "x" : " ");
	hPanel.DrawItem(sBuffer);

	hPanel.DrawText(" ");

	hPanel.CurrentKey = 8;
	hPanel.DrawItem("Back");

	hPanel.CurrentKey = 10;
	hPanel.DrawItem("Exit", ITEMDRAW_CONTROL);

	hPanel.Send(iClient, MenuHandler_Settings, 0);
	delete hPanel;
}

void ShowMapInfoPanel(int iClient, int iTime=0, bool bShowControls=true) {
	if (!g_hLookupStack[iClient] || !g_hLookupStack[iClient].Length) {
		return;
	}

	InfoLookup eInfoLookup;
	g_hLookupStack[iClient].GetArray(g_hLookupStack[iClient].Length-1, eInfoLookup);

	JSONObject hMapInfo = view_as<JSONObject>(eInfoLookup.hMapInfoList.Get(eInfoLookup.iPage));

	char sBuffer[256];
	char sMapName[32];
	char sAuthorID[20];
	char sAuthorName[64];
	char sClass[32];
	int iClass, iTierS, iTierD, iCourses, iJumps, iBonus;

	PrintMapInfo(hMapInfo, g_bExtendedTiers[iClient], sBuffer, sizeof(sBuffer));
	PrintToConsole(iClient, sBuffer);

	if (hMapInfo.HasKey("class")) {
		iClass = hMapInfo.GetInt("class");
	}

	if (hMapInfo.HasKey("tier")) {
		JSONObject hTier = view_as<JSONObject>(hMapInfo.Get("tier"));

		if (hTier.HasKey("3")) {
			iTierS = hTier.GetInt("3");

			if (iTierS > MAX_REGULAR_TIER && !g_bExtendedTiers[iClient]) {
				iTierS = MAX_REGULAR_TIER;
			}
		}

		if (hTier.HasKey("4")) {
			iTierD = hTier.GetInt("4");

			if (iTierD > MAX_REGULAR_TIER && !g_bExtendedTiers[iClient]) {
				iTierD = MAX_REGULAR_TIER;
			}
		}

		delete hTier;
	}

	if (hMapInfo.HasKey("courses")) {
		iCourses = hMapInfo.GetInt("courses");

		if (hMapInfo.HasKey("jumps")) {
			iJumps = hMapInfo.GetInt("jumps");
		}

		if (hMapInfo.HasKey("bonus")) {
			iBonus =  hMapInfo.GetInt("bonus");
		}
	}

	// Title and class
	TF2_GetClassName(view_as<TFClassType>(iClass), sClass, sizeof(sClass));

	Format(sBuffer, sizeof(sBuffer), "====");

	if (sClass[0]) {
		String_ToUpper(sClass, sClass, sizeof(sClass));
		Format(sBuffer, sizeof(sBuffer), "%s %s", sBuffer, sClass);
	}

	Format(sBuffer, sizeof(sBuffer), "%s map ====", sBuffer);

	Panel hPanel = new Panel();
	hPanel.SetTitle(sBuffer);

	hMapInfo.GetString("filename", sMapName, sizeof(sMapName));

	sBuffer = sMapName;

	// Left padding to center text
	int iLength = strlen(sBuffer);
	for (int i=0; i<15-iLength/2; i++) {
		Format(sBuffer, sizeof(sBuffer), " %s", sBuffer);
	}

	hPanel.DrawText(sBuffer);

	int iAuthorsLength;
	if (hMapInfo.HasKey("authors")) {
		JSONArray hAuthorList = view_as<JSONArray>(hMapInfo.Get("authors"));
		iAuthorsLength = hAuthorList.Length;

		if (iAuthorsLength) {
			FormatEx(sBuffer, sizeof(sBuffer), "by");

			for (int i=0; i<iAuthorsLength; i++) {
				JSONObject hAuthor = view_as<JSONObject>(hAuthorList.Get(i));

				hAuthor.GetInt64("id", sAuthorID, sizeof(sAuthorID));
				hAuthor.GetString("name", sAuthorName, sizeof(sAuthorName));

				if (i == 0) {
					Format(sBuffer, sizeof(sBuffer), "%s %s", sBuffer, sAuthorName);
				} else if (i < iAuthorsLength-1) {
					Format(sBuffer, sizeof(sBuffer), "%s, %s", sBuffer, sAuthorName);
				} else {
					Format(sBuffer, sizeof(sBuffer), "%s, and %s", sBuffer, sAuthorName);
				}

				delete hAuthor;

				if (strlen(sBuffer) > 14 && i < iAuthorsLength - 1) {
					Format(sBuffer, sizeof(sBuffer), "%s (+%d)", sBuffer, iAuthorsLength-i-1);
					break;
				}
			}

			iLength = strlen(sBuffer);
			for (int i=0; i<15-iLength/2; i++) {
				Format(sBuffer, sizeof(sBuffer), " %s", sBuffer);
			}

			hPanel.DrawText(sBuffer);
		}

		delete hAuthorList;
	} else {
		hPanel.DrawText(" ");
	}

	hPanel.DrawText(" ");

	// Tiers
	if (iTierS || iTierD) {
		FormatEx(sBuffer, sizeof(sBuffer), "Tier:  ");

		if (iTierS) {
			Format(sBuffer, sizeof(sBuffer), "%sS-%d  ", sBuffer, iTierS);
		}

		if (iTierS && iTierD) {
			Format(sBuffer, sizeof(sBuffer), "%s|  ", sBuffer, iTierD);
		}

		if (iTierD) {
			Format(sBuffer, sizeof(sBuffer), "%sD-%d", sBuffer, iTierD);
		}

		hPanel.DrawText(sBuffer);
	} else {
		hPanel.DrawText(" ");
	}

	hPanel.DrawText(" ");

	// Layout type between jumps
	if (hMapInfo.HasKey("type")) {
		char sLayout[16];
		switch (hMapInfo.GetInt("type")) {
			case 1:
				sLayout = "Connectors";
			case 2:
				sLayout = "Doors";
		}

		if (sLayout[0]) {
			FormatEx(sBuffer, sizeof(sBuffer), "  Layout:  %s", sLayout);
			hPanel.DrawText(sBuffer);
		}
	}  else {
		hPanel.DrawText(" ");
	}

	if (iCourses && iJumps) {
		FormatEx(sBuffer, sizeof(sBuffer), "Courses:  %d\n   Jumps:  %d", iCourses, iJumps);
		if (iBonus > 0) {
			Format(sBuffer, sizeof(sBuffer), "%s (+%d)", sBuffer, iBonus);
		}
		hPanel.DrawText(sBuffer);
	} else {
		hPanel.DrawText(" ");
	}

	hPanel.DrawText(" ");

	if (bShowControls) {
		bool bCanNominate = CheckCommandAccess(iClient, "sm_nominate", ADMFLAG_CHANGEMAP);
		bool bCanChangeMap = CheckCommandAccess(iClient, NULL_STRING, ADMFLAG_CHANGEMAP, true);

		char sFoundMapName[32];
		if (FindMap(sMapName, sFoundMapName, sizeof(sFoundMapName)) == FindMap_Found) {
			char sCurrentMapName[32];
			GetCurrentMap(sCurrentMapName, sizeof(sCurrentMapName));

			int iDrawStyle = StrEqual(sFoundMapName, sCurrentMapName, false) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;

			if (bCanNominate) {
				if (GetFeatureStatus(FeatureType_Native, "NominateMap") == FeatureStatus_Available && bCanNominate) {
					hPanel.CurrentKey = 1;
					hPanel.DrawItem("Nominate", iDrawStyle);
				} else {
					hPanel.DrawText(" ");
				}
			}

			if (bCanChangeMap) {
				hPanel.CurrentKey = 2;
				hPanel.DrawItem("Change Map", iDrawStyle);
			}
		} else {
			if (bCanNominate) {
				hPanel.DrawText(" ");
			}

			if (bCanChangeMap) {
				hPanel.DrawText(" ");
			}
		}

		if (bCanNominate || bCanChangeMap) {
			hPanel.DrawText(" ");
		}
	}

	if (hMapInfo.HasKey("authors")) {
		hPanel.CurrentKey = 4;

		if (iAuthorsLength == 1) {
			hPanel.DrawItem("Author");
		} else {
			FormatEx(sBuffer, sizeof(sBuffer), "Authors (%d)", iAuthorsLength);
			hPanel.DrawItem(sBuffer);
		}
	} else {
		hPanel.DrawText(" ");
	}

	delete hMapInfo;

	hPanel.DrawText(" ");

	if (bShowControls) {
		if (eInfoLookup.bListView) {
			hPanel.CurrentKey = 8;
			hPanel.DrawItem("Back");
		} else {
			if (eInfoLookup.hMapInfoList.Length > 1) {
				hPanel.CurrentKey = 7;
				hPanel.DrawItem("List View");
			}

			if (eInfoLookup.iPage > 0) {
				hPanel.CurrentKey = 8;
				FormatEx(sBuffer, sizeof(sBuffer), "Previous (%d)", eInfoLookup.iPage);
				hPanel.DrawItem(sBuffer);
			} else if (g_hLookupStack[iClient].Length > 1) {
				hPanel.CurrentKey = 8;
				hPanel.DrawItem("Back");
			} else {
				hPanel.DrawText(" ");
			}

			if (eInfoLookup.iPage < eInfoLookup.hMapInfoList.Length-1) {
				hPanel.CurrentKey = 9;
				FormatEx(sBuffer, sizeof(sBuffer), "Next (%d)", eInfoLookup.hMapInfoList.Length-eInfoLookup.iPage-1);
				hPanel.DrawItem(sBuffer);
			} else {
				hPanel.DrawText(" ");
			}
		}
	}

	hPanel.CurrentKey = 10;
	hPanel.DrawItem("Exit", ITEMDRAW_CONTROL);
	hPanel.Send(iClient, MenuHandler_MapInfo, iTime);

	delete hPanel;
}

void ShowMapInfoListMenu(int iClient) {
	if (!g_hLookupStack[iClient] || !g_hLookupStack[iClient].Length) {
		return;
	}

	g_hLookupStack[iClient].Set(g_hLookupStack[iClient].Length-1, true, InfoLookup::bListView);

	InfoLookup eInfoLookup;
	g_hLookupStack[iClient].GetArray(g_hLookupStack[iClient].Length-1, eInfoLookup);

	Menu hMenu = new Menu(MenuHandler_MapList);
	hMenu.SetTitle("========= Maps =========\n    S D Cls   Name");

	char sBuffer[64];

	for (int i=0; i<eInfoLookup.hMapInfoList.Length; i++) {
		char sMapIdx[8];
		IntToString(i, sMapIdx, sizeof(sMapIdx));

		JSONObject hMapInfo = view_as<JSONObject>(eInfoLookup.hMapInfoList.Get(i));

		char sMapName[32];
		hMapInfo.GetString("filename", sMapName, sizeof(sMapName));

		char sMapClass[8];
		if (hMapInfo.HasKey("class")) {
			switch (hMapInfo.GetInt("class")) {
				case 3:
					sMapClass = "S";
				case 4:
					sMapClass = "D";
				default:
					sMapClass = "\u2013";
			}
		} else {
			sMapClass = "\u2013";
		}

		char sMapTiers[8];
		if (hMapInfo.HasKey("tier")) {
			JSONObject hTier = view_as<JSONObject>(hMapInfo.Get("tier"));

			if (hTier.HasKey("3")) {
				int iTier = hTier.GetInt("3");
				if (iTier > MAX_REGULAR_TIER && !g_bExtendedTiers[iClient]) {
					iTier = MAX_REGULAR_TIER;
				}

				if (iTier > 9) {
					sMapTiers = "X";
				} else {
					FormatEx(sMapTiers, sizeof(sMapTiers), "%d", iTier);
				}
			} else {
				sMapTiers = "\u2013";
			}

			if (hTier.HasKey("4")) {
				int iTier = hTier.GetInt("4");
				if (iTier > MAX_REGULAR_TIER && !g_bExtendedTiers[iClient]) {
					iTier = MAX_REGULAR_TIER;
				}

				if (iTier > 9) {
					Format(sMapTiers, sizeof(sMapTiers), "%s X", sMapTiers);
				} else {
					Format(sMapTiers, sizeof(sMapTiers), "%s %d", sMapTiers, iTier);
				}
			} else {
				Format(sMapTiers, sizeof(sMapTiers), "%s \u2013", sMapTiers);
			}

			delete hTier;
		} else {
			sMapTiers = "\u2013 \u2013";
		}

		delete hMapInfo;

		FormatEx(sBuffer, sizeof(sBuffer), "%3s   %s    %s", sMapTiers, sMapClass, sMapName);
		hMenu.AddItem(sMapIdx, sBuffer);
	}

	hMenu.ExitBackButton = g_hLookupStack[iClient].Length > 1;
	hMenu.DisplayAt(iClient, 7*(eInfoLookup.iPage/7), 0);
}

void ShowMapAuthorsMenu(int iClient, bool bFromBack=false) {
	if (!g_hLookupStack[iClient] || !g_hLookupStack[iClient].Length) {
		return;
	}

	InfoLookup eInfoLookup;
	g_hLookupStack[iClient].GetArray(g_hLookupStack[iClient].Length-1, eInfoLookup);

	Menu hMenu = new Menu(MenuHandler_AuthorList);
	hMenu.SetTitle("==== Authors ====");

	JSONObject hMapInfo = view_as<JSONObject>(eInfoLookup.hMapInfoList.Get(eInfoLookup.iPage));

	int iAuthorsLength;
	if (hMapInfo.HasKey("authors")) {
		JSONArray hAuthorList = view_as<JSONArray>(hMapInfo.Get("authors"));
		iAuthorsLength = hAuthorList.Length;

		if (iAuthorsLength) {
			char sAuthorIdx[8];
			char sAuthorName[64];

			for (int i=0; i<iAuthorsLength; i++) {
				IntToString(i, sAuthorIdx, sizeof(sAuthorIdx));

				JSONObject hAuthor = view_as<JSONObject>(hAuthorList.Get(i));
				hAuthor.GetString("name", sAuthorName, sizeof(sAuthorName));
				delete hAuthor;

				hMenu.AddItem(sAuthorIdx, sAuthorName);
			}
		}

		delete hAuthorList;
	}

	delete hMapInfo;

	if (iAuthorsLength == 1) {
		delete hMenu;

		if (bFromBack) {
			if (g_bListView[iClient]) {
				ShowMapInfoListMenu(iClient);
			} else {
				ShowMapInfoPanel(iClient, 0, eInfoLookup.hMapInfoList != g_hCurrentMapInfoList);
			}
		} else {
			g_hLookupStack[iClient].Set(g_hLookupStack[iClient].Length-1, 0, InfoLookup::iSelectedAuthorIdx);
			ShowMapAuthorPanel(iClient);
		}
	} else {
		hMenu.ExitBackButton = true;
		hMenu.Display(iClient, 0);
	}
}

void ShowMapAuthorPanel(int iClient) {
	if (!g_hLookupStack[iClient] || !g_hLookupStack[iClient].Length) {
		return;
	}

	InfoLookup eInfoLookup;
	g_hLookupStack[iClient].GetArray(g_hLookupStack[iClient].Length-1, eInfoLookup);

	if (eInfoLookup.iSelectedAuthorIdx == -1) {
		return;
	}

	JSONObject hMapInfo = view_as<JSONObject>(eInfoLookup.hMapInfoList.Get(eInfoLookup.iPage));
	JSONArray hAuthorList = view_as<JSONArray>(hMapInfo.Get("authors"));
	JSONObject hAuthor = view_as<JSONObject>(hAuthorList.Get(eInfoLookup.iSelectedAuthorIdx));

	char sBuffer[256];
	hAuthor.GetString("name", sBuffer, sizeof(sBuffer));

	delete hAuthor;
	delete hAuthorList;
	delete hMapInfo;

	// Left padding to center text
	int iLength = strlen(sBuffer);
	for (int i=0; i<14-iLength/2; i++) {
		Format(sBuffer, sizeof(sBuffer), " %s", sBuffer);
	}

	Panel hPanel = new Panel();

	hPanel.SetTitle("==== Author ====");
	hPanel.DrawText(sBuffer);
	hPanel.DrawText(" ");

	hPanel.DrawItem("View Profile");
	hPanel.DrawItem("List Maps");

	hPanel.DrawText(" ");

	hPanel.CurrentKey = 8;
	hPanel.DrawItem("Back");

	hPanel.CurrentKey = 10;
	hPanel.DrawItem("Exit", ITEMDRAW_CONTROL);
	hPanel.Send(iClient, MenuHandler_AuthorInfo, 0);

	delete hPanel;
}

// Menu Handlers

public int MenuHandler_Settings(Menu hMenu, MenuAction iAction, int iClient, int iParam) {
	if (iAction == MenuAction_Select) {
		switch (iParam) {
			// Show current map on join
			case 1: {
				g_bJoinMessage[iClient] = !g_bJoinMessage[iClient];
				g_hJoinMessageCookie.Set(iClient, g_bJoinMessage[iClient] ? "1" : "0");
				ShowSettingsPanel(iClient);
			}
			// Use tiers beyond T6
			case 2: {
				g_bExtendedTiers[iClient] = !g_bExtendedTiers[iClient];
				g_hExtendedTiersCookie.Set(iClient, g_bExtendedTiers[iClient] ? "1" : "0");
				ShowSettingsPanel(iClient);
			}
			// Show results as lists
			case 3: {
				g_bListView[iClient] = !g_bListView[iClient];
				g_hViewModeCookie.Set(iClient, g_bListView[iClient] ? "1" : "0");
				ShowSettingsPanel(iClient);	
			}
			// Back
			case 8: {
				ShowCookieMenu(iClient);
			}
		}
	}

	return 0;
}

public int MenuHandler_MapInfo(Menu hMenu, MenuAction iAction, int iClient, int iParam) {
	if (!g_hLookupStack[iClient] || !g_hLookupStack[iClient].Length) {
		return 0;
	}

	InfoLookup eInfoLookup;
	g_hLookupStack[iClient].GetArray(g_hLookupStack[iClient].Length-1, eInfoLookup);

	switch (iAction) {
		case MenuAction_Select: {
			switch (iParam) {
				// Nominate
				case 1: {
					JSONObject hMapInfo = view_as<JSONObject>(eInfoLookup.hMapInfoList.Get(eInfoLookup.iPage));

					char sMapName[32];
					hMapInfo.GetString("filename", sMapName, sizeof(sMapName));

					delete hMapInfo;

					ArrayList hExcludeNominateList = new ArrayList();
					GetExcludeMapList(hExcludeNominateList);

					if (hExcludeNominateList.FindString(sMapName) != -1) {
						CPrintToChat(iClient, "{dodgerblue}[jse] {white}%t", "Map in Exclude List");
						delete hExcludeNominateList;
						return 0;
					}

					delete hExcludeNominateList;

					char sCurrentMapName[32];
					GetCurrentMap(sCurrentMapName, sizeof(sCurrentMapName));

					if (StrEqual(sMapName, sCurrentMapName, false)) {
						CPrintToChat(iClient, "{dodgerblue}[jse] {white}%t", "Can't Nominate Current Map");
					} else {
						switch (NominateMap(sMapName, false, iClient)) {
							case Nominate_AlreadyInVote: {
								CPrintToChat(iClient, "{dodgerblue}[jse] {white}%t", "Map Already In Vote", sMapName);
							}
							case Nominate_InvalidMap: {
								CPrintToChat(iClient, "{dodgerblue}[jse] {white}%t", "Map was not found", sMapName);
							}
							case Nominate_VoteFull: {
								CPrintToChat(iClient, "{dodgerblue}[jse] {white}%t", "Map Already Nominated", sMapName);
							}
							default: {
								char sName[MAX_NAME_LENGTH];
								GetClientName(iClient, sName, sizeof(sName));
								CPrintToChatAll("{dodgerblue}[jse] {white}%t", "Map Nominated", sName, sMapName);
							}
						}
					}
				}
				// Change Map
				case 2: {
					JSONObject hMapInfo = view_as<JSONObject>(eInfoLookup.hMapInfoList.Get(eInfoLookup.iPage));

					char sMapName[32];
					hMapInfo.GetString("filename", sMapName, sizeof(sMapName));

					delete hMapInfo;

					DataPack hDataPack;
					CreateDataTimer(5.0, Timer_MapChange, hDataPack);
					hDataPack.WriteString(sMapName);

					CPrintToChatAll("{dodgerblue}[jse] {white}%t", "Changing map", sMapName);
				}
				// Authors
				case 4: {
					ShowMapAuthorsMenu(iClient);
				}
				// List View
				case 7: {
					ShowMapInfoListMenu(iClient);
				}
				// Back
				case 8: {
					if (eInfoLookup.bListView) {
						ShowMapInfoListMenu(iClient);
					} else {
						if (eInfoLookup.iPage == 0) {
							if (g_hLookupStack[iClient].Length) {
								delete view_as<JSONArray>(g_hLookupStack[iClient].Get(g_hLookupStack[iClient].Length-1, InfoLookup::hMapInfoList));
								g_hLookupStack[iClient].Erase(g_hLookupStack[iClient].Length-1);
							}

							ShowMapAuthorPanel(iClient);
						} else {
							g_hLookupStack[iClient].Set(g_hLookupStack[iClient].Length-1, eInfoLookup.iPage-1, InfoLookup::iPage);
							ShowMapInfoPanel(iClient);
						}
					}
				}
				// Next
				case 9: {
					g_hLookupStack[iClient].Set(g_hLookupStack[iClient].Length-1, eInfoLookup.iPage+1, InfoLookup::iPage);
					ShowMapInfoPanel(iClient);
				}
				// Exit
				case 10: {
					ClearLookupStack(iClient);
				}
			}
		}

		case MenuAction_Cancel: {
			// Check prevents clobbering a newly replaced stack due to delayed call to this menu callback
			if (eInfoLookup.fTimestamp < GetGameTime()) {
				ClearLookupStack(iClient);
			}
		}
	}

	return 0;
}

public int MenuHandler_MapList(Menu hMenu, MenuAction iAction, int iClient, int iParam) {
	switch (iAction) {
		case MenuAction_Select: {
			if (!g_hLookupStack[iClient] || !g_hLookupStack[iClient].Length) {
				return 0;
			}

			char sMapIdx[8];
			hMenu.GetItem(iParam, sMapIdx, sizeof(sMapIdx));

			g_hLookupStack[iClient].Set(g_hLookupStack[iClient].Length-1, StringToInt(sMapIdx), InfoLookup::iPage);

			ShowMapInfoPanel(iClient);
		}

		case MenuAction_Cancel: {
			if (!g_hLookupStack[iClient] || !g_hLookupStack[iClient].Length) {
				return 0;
			}

			if (iParam == MenuCancel_ExitBack) {
				if (g_hLookupStack[iClient].Length) {
					g_hLookupStack[iClient].Erase(g_hLookupStack[iClient].Length-1);
				}

				ShowMapAuthorPanel(iClient);
			} else {
				InfoLookup eInfoLookup;
				g_hLookupStack[iClient].GetArray(g_hLookupStack[iClient].Length-1, eInfoLookup);

				// Check prevents clobbering a newly replaced stack due to delayed call to this menu callback
				if (eInfoLookup.fTimestamp < GetGameTime()) {
					ClearLookupStack(iClient);
				}
			}
		}

		case MenuAction_End: {
			delete hMenu;
		}
	}

	return 0;
}

public int MenuHandler_AuthorList(Menu hMenu, MenuAction iAction, int iClient, int iParam) {
	switch (iAction) {
		case MenuAction_Select: {
			if (!g_hLookupStack[iClient] || !g_hLookupStack[iClient].Length) {
				return 0;
			}

			char sAuthorIdx[8];
			hMenu.GetItem(iParam, sAuthorIdx, sizeof(sAuthorIdx));

			g_hLookupStack[iClient].Set(g_hLookupStack[iClient].Length-1, StringToInt(sAuthorIdx), InfoLookup::iSelectedAuthorIdx);

			ShowMapAuthorPanel(iClient);
		}

		case MenuAction_Cancel: {
			if (!g_hLookupStack[iClient] || !g_hLookupStack[iClient].Length) {
				return 0;
			}

			if (iParam == MenuCancel_ExitBack) {
				if (g_bListView[iClient]) {
					ShowMapInfoListMenu(iClient);
				} else {
					ShowMapInfoPanel(iClient);
				}
			} else {
				InfoLookup eInfoLookup;
				g_hLookupStack[iClient].GetArray(g_hLookupStack[iClient].Length-1, eInfoLookup);

				// Check prevents clobbering a newly replaced stack due to delayed call to this menu callback
				if (eInfoLookup.fTimestamp < GetGameTime()) {
					ClearLookupStack(iClient);
				}
			}
		}

		case MenuAction_End: {
			delete hMenu;
		}
	}

	return 0;
}

public int MenuHandler_AuthorInfo(Menu hMenu, MenuAction iAction, int iClient, int iParam) {
	if (!g_hLookupStack[iClient] || !g_hLookupStack[iClient].Length) {
		return 0;
	}

	InfoLookup eInfoLookup;
	g_hLookupStack[iClient].GetArray(g_hLookupStack[iClient].Length-1, eInfoLookup);

	switch (iAction) {
		case MenuAction_Select: {

			switch (iParam) {
				// View Profile
				case 1: {
					QueryClientConVar(iClient, "cl_disablehtmlmotd", ConVarQueryFinished_DisableHTMLMOTD);
					ShowMapAuthorPanel(iClient);
				}
				// List Maps
				case 2: {
					JSONObject hMapInfo = view_as<JSONObject>(eInfoLookup.hMapInfoList.Get(eInfoLookup.iPage));
					JSONArray hAuthorList = view_as<JSONArray>(hMapInfo.Get("authors"));
					JSONObject hAuthor = view_as<JSONObject>(hAuthorList.Get(eInfoLookup.iSelectedAuthorIdx));

					char sAuthorID[32];
					hAuthor.GetInt64("id", sAuthorID, sizeof(sAuthorID));

					delete hAuthor;
					delete hAuthorList;
					delete hMapInfo;

					MapInfo_Lookup(MapInfoResponse_FetchFromAPI, iClient, g_bExtendedTiers[iClient], _, _, sAuthorID);
				}
				// Back
				case 8: {
					g_hLookupStack[iClient].Set(g_hLookupStack[iClient].Length-1, -1, InfoLookup::iSelectedAuthorIdx);
					ShowMapAuthorsMenu(iClient, true);
				}
			}

		}

		case MenuAction_Cancel: {
			// Check prevents clobbering a newly replaced stack due to delayed call to this menu callback
			if (eInfoLookup.fTimestamp < GetGameTime()) {
				ClearLookupStack(iClient);
			}
		}
	}

	return 0;	
}
