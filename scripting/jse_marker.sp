#pragma semicolon 1

#define PLUGIN_AUTHOR		"AI"
#define PLUGIN_VERSION		"0.1.0"

#define Annotation_sText	0
#define Annotation_fPosX	8
#define Annotation_fPosY	9
#define Annotation_fPosZ	10
#define Annotation_iTarget	11
#define Annotation_iID		12
#define Annotation_Size		13

#define ANNOTATIONS_ID_OFFSET 	1000
#define ANNOTATIONS_CLIENT_MAX	20

#include <sourcemod>
#include <sdktools>
#include <smlib/arrays>
#include <smlib/clients>
#include <smlib/entities>

#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL	"http://jumpacademy.tf/plugins/jse/marker/updatefile.txt"

ArrayList g_hAnnotations[MAXPLAYERS+1] = {null, ...};

ConVar g_hLimit;

public Plugin myinfo = {
	name = "Jump Server Essentials - Marker",
	author = PLUGIN_AUTHOR,
	description = "JSE marker module for tagging map elements",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	CreateConVar("jse_marker_version", PLUGIN_VERSION, "Jump Server Essentials marker version -- Do not modify", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_hLimit = CreateConVar("jse_marker_limit", "1", "Marker limit per player", FCVAR_NONE, true, 0.0, true, float(ANNOTATIONS_CLIENT_MAX));

	RegConsoleCmd("sm_mark",		cmdMark, "Mark a foresight annotation");
	RegConsoleCmd("sm_unmark",		cmdUnmark, "Remove a foresight annotation");
	RegConsoleCmd("sm_unmarkall",	cmdUnmarkAll, "Remove all foresight annotations");

	HookEvent("player_spawn", Event_PlayerSpawn);
}

public void OnPluginEnd() {
	Cleanup();
}

public void OnMapEnd() {
	Cleanup();
}

public void OnClientDisconnect(int iClient) {
	if (g_hAnnotations[iClient] != null) {
		delete g_hAnnotations[iClient];
	}
}

// Custom callbacks

public Action Event_PlayerSpawn(Event hEvent, const char[] sName, bool bDontBroadcast) {
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	CreateTimer(0.1, Timer_ShowAnnotations, iClient);
	
	return Plugin_Continue;
}


public Action Timer_ShowAnnotations(Handle hTimer, any aData) {
	ShowAnnotations(aData);
	return Plugin_Handled;
}

public bool TraceFilter_Mark(int iEntity, int iContentMask, any aData)  {
	if (iEntity == aData) {
		return false;
	}

	return Client_IsValid(iEntity);
}

// Commands

public Action cmdMark(int iClient, int iArgC) {
	ArrayList hAnnotations = g_hAnnotations[iClient];
	if (hAnnotations == null) {
		hAnnotations = g_hAnnotations[iClient] = new ArrayList(Annotation_Size);
	} else {
		int iLimit = CheckCommandAccess(iClient, "jse_marker_maxlimit", ADMFLAG_RESERVATION) ? ANNOTATIONS_CLIENT_MAX : g_hLimit.IntValue;
		if (hAnnotations.Length >= iLimit) {
			bool bAvailable = false;
			for (int i=0; i<hAnnotations.Length; i++) {
				if (hAnnotations.Get(i, Annotation_iID) == -1) {
					bAvailable = true;
					break;
				}
			}

			if (!bAvailable) {
				return Plugin_Handled;
			}
		}
	}

	float fPos[3], fAng[3];
	GetClientEyePosition(iClient, fPos);
	GetClientEyeAngles(iClient, fAng);

	Handle hTr = TR_TraceRayFilterEx(fPos, fAng, MASK_SHOT_HULL, RayType_Infinite, TraceFilter_Mark, iClient);
	if (TR_DidHit(hTr)) {
		float fPosHit[3];
		TR_GetEndPosition(fPosHit, hTr);
		
		char sText[32];
		if (iArgC) {
			GetCmdArgString(sText, sizeof(sText));
		}

		any aData[Annotation_Size];

		int iTraceEnt = TR_GetEntityIndex(hTr);
		if (iTraceEnt > 0) {
			aData[Annotation_iTarget] = iTraceEnt;

			for (int i=0; i<hAnnotations.Length; i++) {
				if (hAnnotations.Get(i, Annotation_iTarget) == iTraceEnt) {
					CloseHandle(hTr);
					return Plugin_Handled;
				}
			}
		} else {
			aData[Annotation_fPosX] = fPosHit[0];
			aData[Annotation_fPosY] = fPosHit[1];
			aData[Annotation_fPosZ] = fPosHit[2];
		}

		int iIdx = -1;
		for (int i=0; i<hAnnotations.Length; i++) {
			if (hAnnotations.Get(i, Annotation_iID) == -1) {
				iIdx = i;
				break;
			}
		}

		if (iIdx == -1) {
			hAnnotations.PushArray(aData);
			iIdx = hAnnotations.Length-1;
		} else {
			hAnnotations.SetArray(iIdx, aData);
		}

		if (iArgC == 0) {
			FormatEx(sText, sizeof(sText), "%d", iIdx+1);
		}

		hAnnotations.SetString(iIdx, sText);
		ShowAnnotation(iClient, iIdx);
	}
	CloseHandle(hTr);

	return Plugin_Handled;
}

public Action cmdUnmark(int iClient, int iArgC) {
	float fPos[3], fAng[3];
	GetClientEyePosition(iClient, fPos);
	GetClientEyeAngles(iClient, fAng);

	ArrayList hAnnotations = g_hAnnotations[iClient];
	if (hAnnotations == null || !hAnnotations.Length) {
		return Plugin_Handled;
	}

	Handle hTr = TR_TraceRayFilterEx(fPos, fAng, MASK_SHOT_HULL, RayType_Infinite, TraceFilter_Mark, iClient);
	if (TR_DidHit(hTr)) {
		float fPosHit[3];
		TR_GetEndPosition(fPosHit, hTr);

		int iIdx = -1;
		int iAnnotationID = 0;
		int iTraceEnt = TR_GetEntityIndex(hTr);
		if (iTraceEnt > 0) {
			for (int i=0; i<hAnnotations.Length; i++) {
				if (hAnnotations.Get(i, Annotation_iTarget) == iTraceEnt) {
					iAnnotationID = hAnnotations.Get(i, Annotation_iID);
					iIdx = i;
					hAnnotations.Set(iIdx, 0, Annotation_iTarget);
					break;
				}
			}
		} else {
			float fMinDist = 100.0;
			for (int i=0; i<hAnnotations.Length; i++) {
				fPos[0] = hAnnotations.Get(i, Annotation_fPosX);
				fPos[1] = hAnnotations.Get(i, Annotation_fPosY);
				fPos[2] = hAnnotations.Get(i, Annotation_fPosZ);

				float fDist = GetVectorDistance(fPos, fPosHit);
				if (fDist < fMinDist) {
					iAnnotationID = hAnnotations.Get(i, Annotation_iID);
					fMinDist = fDist;

					iIdx = i;
				}
			}
		}

		if (iIdx != -1) {
			HideAnnotation(iAnnotationID, iClient);
			hAnnotations.Set(iIdx, -1, Annotation_iID);
		}
	}
	CloseHandle(hTr);

	return Plugin_Handled;
}

public Action cmdUnmarkAll(int iClient, int iArgC) {
	ArrayList hAnnotations = g_hAnnotations[iClient];
	if (hAnnotations != null) {
		for (int i=0; i<hAnnotations.Length; i++) {
			int iAnnotationID = hAnnotations.Get(i, Annotation_iID);
			HideAnnotation(iAnnotationID, iClient);
		}

		hAnnotations.Clear();
	}

	return Plugin_Handled;
}

// Helpers

void Cleanup() {
	for (int i=1; i<=MaxClients; i++) {
		if (g_hAnnotations[i] != null) {
			ArrayList hAnnotations = g_hAnnotations[i];
			for (int j=0; j<hAnnotations.Length; j++) {
				int iAnnotationID = hAnnotations.Get(j, Annotation_iID);
				HideAnnotation(iAnnotationID, i);
			}

			delete g_hAnnotations[i];
		}
	}
}

void ShowAnnotations(int iClient) {
	ArrayList hAnnotations = g_hAnnotations[iClient];
	if (hAnnotations == null) {
		return;
	}

	for (int i=0; i<hAnnotations.Length; i++) {
		ShowAnnotation(iClient, i);
	}
}

void ShowAnnotation(int iClient, int iIdx) {
	ArrayList hAnnotations = g_hAnnotations[iClient];
	if (hAnnotations == null) {
		return;
	}

	int iAnnotationID = hAnnotations.Get(iIdx, Annotation_iID);
	if (iAnnotationID == -1) {
		return;
	} else if (!iAnnotationID) {
		iAnnotationID = ANNOTATIONS_ID_OFFSET + ANNOTATIONS_CLIENT_MAX*iClient + iIdx;
	}

	Event hEvent = CreateEvent("show_annotation");
	if (hEvent == null) {
		return;
	}

	char sText[32];
	hAnnotations.GetString(iIdx, sText, sizeof(sText));

	float fPos[3];
	fPos[0] = hAnnotations.Get(iIdx, Annotation_fPosX);
	fPos[1] = hAnnotations.Get(iIdx, Annotation_fPosY);
	fPos[2] = hAnnotations.Get(iIdx, Annotation_fPosZ);
	
	hAnnotations.Set(iIdx, iAnnotationID, Annotation_iID);

	hEvent.SetFloat("worldPosX", fPos[0]);
	hEvent.SetFloat("worldPosY", fPos[1]);
	hEvent.SetFloat("worldPosZ", fPos[2]);
	hEvent.SetFloat("lifetime", view_as<float>(0x7F800000)); // +inf
	hEvent.SetInt("id", iAnnotationID);

	int iFollowTarget = hAnnotations.Get(iIdx, Annotation_iTarget);
	if (iFollowTarget) {
		hEvent.SetInt("follow_entindex", iFollowTarget);
	}

	hEvent.SetBool("show_distance", true);
	hEvent.SetString("text", sText);
	hEvent.SetString("play_sound", "vo/null.wav");
	hEvent.FireToClient(iClient);
}

void HideAnnotation(int iAnnotationID, int iClient) {
	Event hEvent = CreateEvent("hide_annotation");
	if (hEvent == null) {
		return;
	}

	hEvent.SetInt("id", iAnnotationID);
	hEvent.FireToClient(iClient);
}
