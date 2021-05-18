enum struct _ClientInfo {
	char sAuthID[24];
	char sName[32];
	TFTeam iTeam;
	TFClassType iClass;
	float fStartPos[3];
	float fStartAng[3];
	int iEquipItemDefIdx[8];
	char sEquipClassName[8*128];
	bool bGCFlag;
}

static ArrayList hClientInfo = null;
const ClientInfo NULL_CLIENTINFO = view_as<ClientInfo>(0);

public void ClientInfo_SetupNatives() {
	CreateNative("ClientInfo.GetAuthID",			Native_ClientInfo_GetAuthID);
	CreateNative("ClientInfo.SetAuthID",			Native_ClientInfo_SetAuthID);
	
	CreateNative("ClientInfo.GetName",				Native_ClientInfo_GetName);
	CreateNative("ClientInfo.SetName",				Native_ClientInfo_SetName);
	
	CreateNative("ClientInfo.Team.get",				Native_ClientInfo_GetTeam);
	CreateNative("ClientInfo.Team.set",				Native_ClientInfo_SetTeam);
	
	CreateNative("ClientInfo.Class.get",			Native_ClientInfo_GetClass);
	CreateNative("ClientInfo.Class.set",			Native_ClientInfo_SetClass);
	
	CreateNative("ClientInfo.GetStartPos",			Native_ClientInfo_GetStartPos);
	CreateNative("ClientInfo.SetStartPos",			Native_ClientInfo_SetStartPos);
	
	CreateNative("ClientInfo.GetStartAng",			Native_ClientInfo_GetStartAng);
	CreateNative("ClientInfo.SetStartAng",			Native_ClientInfo_SetStartAng);
	
	CreateNative("ClientInfo.GetEquipItemDefIdx",	Native_ClientInfo_GetEquipItemDefIdx);
	CreateNative("ClientInfo.SetEquipItemDefIdx",	Native_ClientInfo_SetEquipItemDefIdx);
	
	CreateNative("ClientInfo.GetEquipClassName",	Native_ClientInfo_GetEquipClassName);
	CreateNative("ClientInfo.SetEquipClassName",	Native_ClientInfo_SetEquipClassName);

	CreateNative("ClientInfo.Instance",				Native_ClientInfo_Instance);
	CreateNative("ClientInfo.Destroy",				Native_ClientInfo_Destroy);
}

public int Native_ClientInfo_GetAuthID(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iLength = GetNativeCell(3);

	_ClientInfo eClientInfo;
	hClientInfo.GetArray(iThis, eClientInfo);

	SetNativeString(2, eClientInfo.sAuthID, iLength);
}

public int Native_ClientInfo_SetAuthID(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	
	_ClientInfo eClientInfo;
	hClientInfo.GetArray(iThis, eClientInfo);

	GetNativeString(2, eClientInfo.sAuthID, sizeof(_ClientInfo::sAuthID));
	
	hClientInfo.SetArray(iThis, eClientInfo);
}

public int Native_ClientInfo_GetName(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iLength = GetNativeCell(3);

	_ClientInfo eClientInfo;
	hClientInfo.GetArray(iThis, eClientInfo);
	
	SetNativeString(2, eClientInfo.sName, iLength);
}

public int Native_ClientInfo_SetName(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_ClientInfo eClientInfo;
	hClientInfo.GetArray(iThis, eClientInfo);

	GetNativeString(2, eClientInfo.sName, sizeof(_ClientInfo::sName));
	
	hClientInfo.SetArray(iThis, eClientInfo);
}

public int Native_ClientInfo_GetTeam(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return hClientInfo.Get(iThis, _ClientInfo::iTeam);
}

public int Native_ClientInfo_SetTeam(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iTeam = GetNativeCell(2);
	hClientInfo.Set(iThis, iTeam, _ClientInfo::iTeam);
}

public int Native_ClientInfo_GetClass(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return hClientInfo.Get(iThis, _ClientInfo::iClass);
}

public int Native_ClientInfo_SetClass(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iClass = GetNativeCell(2);
	hClientInfo.Set(iThis, iClass, _ClientInfo::iClass);
}

public int Native_ClientInfo_GetStartPos(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	float fStartPos[3];
	fStartPos[0] = hClientInfo.Get(iThis, _ClientInfo::fStartPos  );
	fStartPos[1] = hClientInfo.Get(iThis, _ClientInfo::fStartPos+1);
	fStartPos[2] = hClientInfo.Get(iThis, _ClientInfo::fStartPos+2);

	SetNativeArray(2, fStartPos, sizeof(fStartPos));
}

public int Native_ClientInfo_SetStartPos(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	float fStartPos[3];
	GetNativeArray(2, fStartPos, sizeof(fStartPos));

	hClientInfo.Set(iThis, fStartPos[0], _ClientInfo::fStartPos  );
	hClientInfo.Set(iThis, fStartPos[1], _ClientInfo::fStartPos+1);
	hClientInfo.Set(iThis, fStartPos[2], _ClientInfo::fStartPos+2);
}

public int Native_ClientInfo_GetStartAng(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	float fStartAng[3];
	fStartAng[0] = hClientInfo.Get(iThis, _ClientInfo::fStartAng  );
	fStartAng[1] = hClientInfo.Get(iThis, _ClientInfo::fStartAng+1);

	SetNativeArray(2, fStartAng, sizeof(fStartAng));
}

public int Native_ClientInfo_SetStartAng(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	float fStartAng[3];
	GetNativeArray(2, fStartAng, sizeof(fStartAng));

	hClientInfo.Set(iThis, fStartAng[0], _ClientInfo::fStartAng  );
	hClientInfo.Set(iThis, fStartAng[1], _ClientInfo::fStartAng+1);
}

public int Native_ClientInfo_GetEquipItemDefIdx(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iSlot = GetNativeCell(2);

	return hClientInfo.Get(iThis, _ClientInfo::iEquipItemDefIdx + iSlot);
}

public int Native_ClientInfo_SetEquipItemDefIdx(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iSlot = GetNativeCell(2);
	int iItemDefIdx = GetNativeCell(3);

	hClientInfo.Set(iThis, iItemDefIdx, _ClientInfo::iEquipItemDefIdx + iSlot);
}

public int Native_ClientInfo_GetEquipClassName(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iSlot = GetNativeCell(2);
	int iLength = GetNativeCell(4);

	_ClientInfo eClientInfo;
	hClientInfo.GetArray(iThis, eClientInfo);

	SetNativeString(3, eClientInfo.sEquipClassName[128*iSlot], iLength);
}

public int Native_ClientInfo_SetEquipClassName(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iSlot = GetNativeCell(2);

	_ClientInfo eClientInfo;
	hClientInfo.GetArray(iThis, eClientInfo);

	GetNativeString(3, eClientInfo.sEquipClassName[128*iSlot], 128);
	
	hClientInfo.SetArray(iThis, eClientInfo);
}

public int Native_ClientInfo_Instance(Handle hPlugin, int iArgC) {
	if (hClientInfo == null) {
		hClientInfo = new ArrayList(sizeof(_ClientInfo));
	}

	static _ClientInfo eEmptyClientInfo;

	for (int i=0; i<hClientInfo.Length; i++) {
		if (hClientInfo.Get(i, _ClientInfo::bGCFlag)) {
			hClientInfo.SetArray(i, eEmptyClientInfo);
			return i+1;
		}
	}
	
	hClientInfo.PushArray(eEmptyClientInfo);
	return hClientInfo.Length;
}

public int Native_ClientInfo_Destroy(Handle hPlugin, int iArgC) {
	if (hClientInfo != null) {
		int iClientInfo = GetNativeCell(1);
		hClientInfo.Set(iClientInfo-1, 1, _ClientInfo::bGCFlag);
	}
}

// class Recording

enum struct _Recording {
	char sFilePath[256];
	bool bRepo;
	int iDownloading;
	int iFileSize;
	int iTimestamp;
	ArrayList hFrames;
	int iFramesExpected;
	int iLength;
	ArrayList hClientInfo;
	int iEquipFilter;
	int iNodeModel;
	int iWeaponModel;
	int iVisibility[2];
	bool bGCFlag;
}

static ArrayList hRecordings = null;
const Recording NULL_RECORDING = view_as<Recording>(0);

public void Recording_SetupNatives() {
	CreateNative("Recording.GetFilePath",			Native_Recording_GetFilePath);
	CreateNative("Recording.SetFilePath",			Native_Recording_SetFilePath);
	
	CreateNative("Recording.Repo.get",				Native_Recording_GetRepo);
	CreateNative("Recording.Repo.set",				Native_Recording_SetRepo);
	
	CreateNative("Recording.Downloading.get",		Native_Recording_GetDownloading);
	CreateNative("Recording.Downloading.set",		Native_Recording_SetDownloading);
	
	CreateNative("Recording.FileSize.get",			Native_Recording_GetFileSize);
	CreateNative("Recording.FileSize.set",			Native_Recording_SetFileSize);
	
	CreateNative("Recording.Timestamp.get",			Native_Recording_GetTimestamp);
	CreateNative("Recording.Timestamp.set",			Native_Recording_SetTimestamp);
	
	CreateNative("Recording.Frames.get",			Native_Recording_GetFrames);
	
	CreateNative("Recording.FramesExpected.get",	Native_Recording_GetFramesExpected);
	CreateNative("Recording.FramesExpected.set",	Native_Recording_SetFramesExpected);
	
	CreateNative("Recording.Length.get",			Native_Recording_GetLength);
	CreateNative("Recording.Length.set",			Native_Recording_SetLength);
	
	CreateNative("Recording.ClientInfo.get",		Native_Recording_GetClientInfo);

	CreateNative("Recording.GetEquipFilter",		Native_Recording_GetEquipFilter);
	CreateNative("Recording.SetEquipFilter",		Native_Recording_SetEquipFilter);
	
	CreateNative("Recording.NodeModel.get",			Native_Recording_GetNodeModel);
	CreateNative("Recording.NodeModel.set",			Native_Recording_SetNodeModel);
	
	CreateNative("Recording.WeaponModel.get",		Native_Recording_GetWeaponModel);
	CreateNative("Recording.WeaponModel.set",		Native_Recording_SetWeaponModel);

	CreateNative("Recording.GetVisibility",			Native_Recording_GetVisibility);
	CreateNative("Recording.SetVisibility",			Native_Recording_SetVisibility);
	
	CreateNative("Recording.ResetVisibility",		Native_Recording_ResetVisibility);

	CreateNative("Recording.Instance",				Native_Recording_Instance);
	CreateNative("Recording.Destroy",				Native_Recording_Destroy);
}

public int Native_Recording_GetFilePath(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iLength = GetNativeCell(3);

	char sFilePath[256];
	hRecordings.GetString(iThis, sFilePath, iLength);

	_Recording eRecording;
	hRecordings.GetArray(iThis, eRecording);
	
	SetNativeString(2, eRecording.sFilePath, iLength);
}

public int Native_Recording_SetFilePath(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_Recording eRecording;
	hRecordings.GetArray(iThis, eRecording);

	GetNativeString(2, eRecording.sFilePath, sizeof(_Recording::sFilePath));
	
	hRecordings.SetArray(iThis, eRecording);
}

public int Native_Recording_GetRepo(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return hRecordings.Get(iThis, _Recording::bRepo);
}

public int Native_Recording_SetRepo(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	bool bRepo = GetNativeCell(2) != 0;

	hRecordings.Set(iThis, bRepo, _Recording::bRepo);
}

public int Native_Recording_GetDownloading(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return hRecordings.Get(iThis, _Recording::iDownloading);
}

public int Native_Recording_SetDownloading(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iDownloading = GetNativeCell(2);
	hRecordings.Set(iThis, iDownloading, _Recording::iDownloading);
}

public int Native_Recording_GetFileSize(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return hRecordings.Get(iThis, _Recording::iFileSize);
}

public int Native_Recording_SetFileSize(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iFileSize = GetNativeCell(2);
	hRecordings.Set(iThis, iFileSize, _Recording::iFileSize);
}

public int Native_Recording_GetTimestamp(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return hRecordings.Get(iThis, _Recording::iTimestamp);
}

public int Native_Recording_SetTimestamp(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iTimestamp = GetNativeCell(2);
	hRecordings.Set(iThis, iTimestamp, _Recording::iTimestamp);
}

public int Native_Recording_GetFrames(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return hRecordings.Get(iThis, _Recording::hFrames);
}

public int Native_Recording_GetFramesExpected(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return hRecordings.Get(iThis, _Recording::iFramesExpected);
}

public int Native_Recording_SetFramesExpected(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iFrames = GetNativeCell(2);
	hRecordings.Set(iThis, iFrames, _Recording::iFramesExpected);
}

public int Native_Recording_GetLength(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return hRecordings.Get(iThis, _Recording::iLength);
}

public int Native_Recording_SetLength(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iLength = GetNativeCell(2);
	hRecordings.Set(iThis, iLength, _Recording::iLength);
}

public int Native_Recording_GetClientInfo(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return hRecordings.Get(iThis, _Recording::hClientInfo);
}

public int Native_Recording_GetEquipFilter(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	int iEquipFilter = hRecordings.Get(iThis, _Recording::iEquipFilter);
	int iSlot = iEquipFilter & 0xFF;
	int iItemDefIdx = (iEquipFilter >> 16);

	SetNativeCellRef(2, iSlot);
	SetNativeCellRef(3, iItemDefIdx);
}

public int Native_Recording_SetEquipFilter(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iSlot = GetNativeCell(2);
	int iItemDefIdx = GetNativeCell(3);

	int iEquipFilter = (iItemDefIdx << 16) | (iSlot & 0xFF);
	hRecordings.Set(iThis, iEquipFilter, _Recording::iEquipFilter);
}

public int Native_Recording_GetNodeModel(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return hRecordings.Get(iThis, _Recording::iNodeModel);
}

public int Native_Recording_SetNodeModel(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iNodeModel = GetNativeCell(2);
	hRecordings.Set(iThis, iNodeModel, _Recording::iNodeModel);
}

public int Native_Recording_GetWeaponModel(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return hRecordings.Get(iThis, _Recording::iWeaponModel);
}

public int Native_Recording_SetWeaponModel(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iWeaponModel = GetNativeCell(2);
	hRecordings.Set(iThis, iWeaponModel, _Recording::iWeaponModel);
}

public int Native_Recording_GetVisibility(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iClient = GetNativeCell(2);

	int iOffset = iClient/32;
	int iBit = iClient % 32;

	return (hRecordings.Get(iThis, _Recording::iVisibility+iOffset) & 1<<iBit) != 0;
}

public int Native_Recording_SetVisibility(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iClient = GetNativeCell(2);
	bool bVisible = GetNativeCell(3) != 0;

	int iOffset = iClient/32;
	int iBit = iClient % 32;

	int iMask = hRecordings.Get(iThis, _Recording::iVisibility+iOffset) & ~(1<<iBit);
	hRecordings.Set(iThis, iMask | view_as<int>(bVisible)<<iBit, _Recording::iVisibility+iOffset);

	return bVisible;
}

public int Native_Recording_ResetVisibility(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	hRecordings.Set(iThis, 0, _Recording::iVisibility);
	hRecordings.Set(iThis, 0, _Recording::iVisibility+1);
}

public int Native_Recording_Instance(Handle hPlugin, int iArgC) {
	if (hRecordings == null) {
		hRecordings = new ArrayList(sizeof(_Recording));
	}
	
	static _Recording eEmptyRecording;	
	eEmptyRecording.iNodeModel = INVALID_ENT_REFERENCE;
	eEmptyRecording.iWeaponModel = INVALID_ENT_REFERENCE;
	eEmptyRecording.hClientInfo = new ArrayList();
	eEmptyRecording.hFrames = new ArrayList();

	for (int i=0; i<hRecordings.Length; i++) {
		if (hRecordings.Get(i, _Recording::bGCFlag)) {
			hRecordings.SetArray(i, eEmptyRecording);
			
			return i+1;
		}
	}
	
	hRecordings.PushArray(eEmptyRecording);

	return hRecordings.Length;
}

public int Native_Recording_Destroy(Handle hPlugin, int iArgC) {
	if (hRecordings != null) {
		Recording iRecording = GetNativeCell(1);

		hRecordings.Set(view_as<int>(iRecording)-1, 1, _Recording::bGCFlag);
		
		ArrayList hRecClientInfo = iRecording.ClientInfo;
		ArrayList hFrames = hRecordings.Get(view_as<int>(iRecording)-1, _Recording::hFrames);
		delete hFrames;

		for (int i=0; i<hRecClientInfo.Length; i++) {
			ClientInfo iClientInfo = hRecClientInfo.Get(i);
			ClientInfo.Destroy(iClientInfo);
		}
		
		delete hRecClientInfo;
	}
}

public int Sort_Recordings(int iIdx1, int iIdx2, Handle hArray, Handle hParam) {
	ArrayList hArrayList = view_as<ArrayList>(hArray);
	Recording iRecording1 = view_as<Recording>(hArrayList.Get(iIdx1));
	Recording iRecording2 = view_as<Recording>(hArrayList.Get(iIdx2));
	
	if (iRecording1.Repo) {
		if (iRecording2.Repo) {
			return iRecording1.Timestamp - iRecording2.Timestamp;
		}

		return -1;
	}

	if (iRecording2.Repo) {
		return 1;
	}
	
	return iRecording1.Timestamp - iRecording2.Timestamp;
}
