#if defined _JSE_JUMPBOT_included
 #endinput
#endif
#define _JSE_JUMPBOT_included

#include <sourcemod>

public SharedPlugin __pl_jse_jumpbot = {
	name = "jse_jumpbot",
	file = "jse_jumpbot.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};


#if !defined REQUIRE_PLUGIN
public void __pl_jse_jumpbot_SetNTVOptional() {
	MarkNativeAsOptional("JSE_JB_Shutdown");
	MarkNativeAsOptional("JSE_JB_LoadRecordings");
	MarkNativeAsOptional("JSE_JB_GetRecordings");
	MarkNativeAsOptional("JSE_JB_PlayRecording");
	MarkNativeAsOptional("JSE_JB_PlayRecordingQueueClient");

	MarkNativeAsOptional("ClientInfo.GetAuthID");
	MarkNativeAsOptional("ClientInfo.SetAuthID");
	MarkNativeAsOptional("ClientInfo.GetName");
	MarkNativeAsOptional("ClientInfo.SetName");
	MarkNativeAsOptional("ClientInfo.Team.get");
	MarkNativeAsOptional("ClientInfo.Team.set");
	MarkNativeAsOptional("ClientInfo.Class.get");
	MarkNativeAsOptional("ClientInfo.Class.set");
	MarkNativeAsOptional("ClientInfo.GetStartPos");
	MarkNativeAsOptional("ClientInfo.SetStartPos");
	MarkNativeAsOptional("ClientInfo.GetStartAng");
	MarkNativeAsOptional("ClientInfo.SetStartAng");
	MarkNativeAsOptional("ClientInfo.GetEquipItemDefIdx");
	MarkNativeAsOptional("ClientInfo.SetEquipItemDefIdx");
	MarkNativeAsOptional("ClientInfo.GetEquipClassName");
	MarkNativeAsOptional("ClientInfo.SetEquipClassName");
	MarkNativeAsOptional("ClientInfo.Instance");
	MarkNativeAsOptional("ClientInfo.Destroy");

	MarkNativeAsOptional("Recording.GetFilePath");
	MarkNativeAsOptional("Recording.SetFilePath");
	MarkNativeAsOptional("Recording.Repo.get");
	MarkNativeAsOptional("Recording.Repo.set");
	MarkNativeAsOptional("Recording.Downloading.get");
	MarkNativeAsOptional("Recording.Downloading.set");
	MarkNativeAsOptional("Recording.FileSize.get");
	MarkNativeAsOptional("Recording.FileSize.set");
	MarkNativeAsOptional("Recording.Timestamp.get");
	MarkNativeAsOptional("Recording.Timestamp.set");
	MarkNativeAsOptional("Recording.Frames.get");
	MarkNativeAsOptional("Recording.FramesExpected.get");
	MarkNativeAsOptional("Recording.FramesExpected.set");
	MarkNativeAsOptional("Recording.Length.get");
	MarkNativeAsOptional("Recording.Length.set");
	MarkNativeAsOptional("Recording.ClientInfo.get");
	MarkNativeAsOptional("Recording.NodeModel.get");
	MarkNativeAsOptional("Recording.NodeModel.set");
	MarkNativeAsOptional("Recording.WeaponModel.get");
	MarkNativeAsOptional("Recording.WeaponModel.set");
	MarkNativeAsOptional("Recording.Instance");
	MarkNativeAsOptional("Recording.Destroy");
}
#endif

methodmap ClientInfo {
	public native void GetAuthID(char[] sAuthID, int iLength);
	public native void SetAuthID(char[] sAuthID);
	public native void GetName(char[] sName, int iLength);
	public native void SetName(char[] sName);

	property TFTeam Team {
		public native get();
		public native set(TFTeam iTeam);
	}

	property TFClassType Class {
		public native get();
		public native set(TFClassType iClass);
	}

	public native void GetStartPos(float fStartPos[3]);
	public native void SetStartPos(float fStartPos[3]);
	
	public native void GetStartAng(float fStartAng[3]);
	public native void SetStartAng(float fStartAng[3]);
	
	public native int GetEquipItemDefIdx(int iSlot);
	public native void SetEquipItemDefIdx(int iSlot, int iItemDefIdx);
	
	public native void GetEquipClassName(int iSlot, char[] sClassName, int iLength);
	public native void SetEquipClassName(int iSlot, char[] sClassName);
	
	/**
	 * Creates a new ClientInfo instance
	 */
	public static native ClientInfo Instance();

	/**
	 * Flags ClientInfo for garbage collection
	 * @param 			Recording created from prior call to Instance
	 */
	public static native void Destroy(ClientInfo iClientInfo);
}

methodmap Recording {
	public native void GetFilePath(char[] sFilePath, int iLength);
	public native void SetFilePath(char[] sFilePath);
		
	property bool Repo {
		public native get();
		public native set(bool bRepo);
	}
	
	property int Downloading {
		public native get();
		public native set(int iDownloading);
	}
	
	property int FileSize {
		public native get();
		public native set(int iFileSize);
	}

	property int Timestamp {
		public native get();
		public native set(int iTimestamp);
	}
	
	property ArrayList Frames {
		public native get();
	}

	property int FramesExpected {
		public native get();
		public native set(int iFrames);
	}

	property int Length {
		public native get();
		public native set(int iLength);
	}

	property ArrayList ClientInfo {
		public native get();
	}

	property int NodeModel {
		public native get();
		public native set(int iNodeModel);
	}

	property int WeaponModel {
		public native get();
		public native set(int iWeaponModel)
	}

	/**
	 * Creates a new Recording instance
	 */
	public static native Recording Instance();

	/**
	 * Flags Recording for garbage collection
	 * @param 			Recording created from prior call to Instance
	 */
	public static native void Destroy(Recording iRecording);
}

/**
 * Prepares plugin for shutdown prior to map change
 * @note				This will kick the bots
 */
native void JSE_JB_Shutdown();

/**
 * Triggers refresh of recordings cache
 * @note 				This will also stop and reset all current plugin operations.
 */
native void JSE_JB_LoadRecordings();

/**
 * Gets currently loaded recordings on the map
 *
 * @note 				Returned handle must be closed 
 * @note 				List contents are of Recording type
 * @return 				Cloned ArrayList of loaded recordings
 */
native ArrayList JSE_JB_GetRecordings();

/**
 * Play a particular recording
 * @param iRecording 	Recording retrieved from JSE_JB_GetRecordings
 * @param iClient 		Optionally allow a client to control the playback
 * @param bRespawn 		Optionally respawn client after playback
 * @param iPerspective	Optionally force view perspective (-1: client preference, 0: no spectate, 1: first-person, 3: third-person)
 * @return 				True on success, false otherwise
 * @note				This will also stop and empty the client playback queue.
 */
native bool JSE_JB_PlayRecording(Recording iRecording, int iClient=0, bool bRespawn=false, int iPerspective=-1);

/**
 * Queues a client to play a particular recording
 * @param iRecording 	Recording retrieved from JSE_JB_GetRecordings
 * @param iClient 		Client to queue recording for
 * @param iPerspective	Optionally force view perspective (-1: client preference, 0: no spectate, 1: first-person, 3: third-person)
 * @return 				True on success, false otherwise
 * @note				Client will auto respawn after playback just like normal queue behavior
 */
native bool JSE_JB_PlayRecordingQueueClient(Recording iRecording, int iClient, int iPerspective=-1);
