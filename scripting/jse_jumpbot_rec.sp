// class ClientInfo

#define ClientInfo_sAuthID			0	// char[24] = int[6]
#define ClientInfo_sName			6	// char[32] = int[8]
#define ClientInfo_iTeam			14	// int
#define ClientInfo_iClass			15	// int
#define ClientInfo_fStartPos		16	// float[3]
#define ClientInfo_fStartAng		19	// float[2]
#define ClientInfo_iEquipItemDefIdx	21	// int[8]
#define ClientInfo_sEquipClassName	29	// char[8][128] = int[8][32] = int[256]
#define ClientInfo_bGCFlag			285	// int
#define ClientInfo_Size				286

static ArrayList hClientInfo = null;
const ClientInfo NULL_CLIENTINFO = view_as<ClientInfo>(-1);

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
	int iThis = GetNativeCell(1);
	int iLength = GetNativeCell(3);

	int iArr[6];
	hClientInfo.GetArray(iThis, iArr, sizeof(iArr));

	char sAuthID[24];
	IntArrayToString(iArr[ClientInfo_sAuthID], 6, sAuthID, sizeof(sAuthID));

	SetNativeString(2, sAuthID, iLength);
}

public int Native_ClientInfo_SetAuthID(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	
	char sAuthID[24];
	GetNativeString(2, sAuthID, sizeof(sAuthID));

	int iArr[ClientInfo_Size];
	hClientInfo.GetArray(iThis, iArr, sizeof(iArr));
	
	StringToIntArray(sAuthID, iArr[ClientInfo_sAuthID], 6);
	
	hClientInfo.SetArray(iThis, iArr, sizeof(iArr));
}

public int Native_ClientInfo_GetName(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iLength = GetNativeCell(3);

	int iArr[14]; // sAuthID + sName
	hClientInfo.GetArray(iThis, iArr, sizeof(iArr));
	
	char sName[32];
	IntArrayToString(iArr[ClientInfo_sName], 8, sName, sizeof(sName));

	SetNativeString(2, sName, iLength);
}

public int Native_ClientInfo_SetName(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	char sName[32];
	GetNativeString(2, sName, sizeof(sName));

	int iArr[ClientInfo_Size];
	hClientInfo.GetArray(iThis, iArr, sizeof(iArr));

	StringToIntArray(sName, iArr[ClientInfo_sName], 8);
	
	hClientInfo.SetArray(iThis, iArr, sizeof(iArr));
}

public int Native_ClientInfo_GetTeam(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hClientInfo.Get(iThis, ClientInfo_iTeam);
}

public int Native_ClientInfo_SetTeam(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iTeam = GetNativeCell(2);
	hClientInfo.Set(iThis, iTeam, ClientInfo_iTeam);
}

public int Native_ClientInfo_GetClass(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hClientInfo.Get(iThis, ClientInfo_iClass);
}

public int Native_ClientInfo_SetClass(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iClass = GetNativeCell(2);
	hClientInfo.Set(iThis, iClass, ClientInfo_iClass);
}

public int Native_ClientInfo_GetStartPos(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	float fStartPos[3];
	fStartPos[0] = hClientInfo.Get(iThis, ClientInfo_fStartPos  );
	fStartPos[1] = hClientInfo.Get(iThis, ClientInfo_fStartPos+1);
	fStartPos[2] = hClientInfo.Get(iThis, ClientInfo_fStartPos+2);

	SetNativeArray(2, fStartPos, sizeof(fStartPos));
}

public int Native_ClientInfo_SetStartPos(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	float fStartPos[3];
	GetNativeArray(2, fStartPos, sizeof(fStartPos));

	hClientInfo.Set(iThis, fStartPos[0], ClientInfo_fStartPos  );
	hClientInfo.Set(iThis, fStartPos[1], ClientInfo_fStartPos+1);
	hClientInfo.Set(iThis, fStartPos[2], ClientInfo_fStartPos+2);
}

public int Native_ClientInfo_GetStartAng(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	float fStartAng[3];
	fStartAng[0] = hClientInfo.Get(iThis, ClientInfo_fStartAng  );
	fStartAng[1] = hClientInfo.Get(iThis, ClientInfo_fStartAng+1);

	SetNativeArray(2, fStartAng, sizeof(fStartAng));
}

public int Native_ClientInfo_SetStartAng(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	float fStartAng[3];
	GetNativeArray(2, fStartAng, sizeof(fStartAng));

	hClientInfo.Set(iThis, fStartAng[0], ClientInfo_fStartAng  );
	hClientInfo.Set(iThis, fStartAng[1], ClientInfo_fStartAng+1);
}

public int Native_ClientInfo_GetEquipItemDefIdx(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iSlot = GetNativeCell(2);

	return hClientInfo.Get(iThis, ClientInfo_iEquipItemDefIdx + iSlot);
}

public int Native_ClientInfo_SetEquipItemDefIdx(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iSlot = GetNativeCell(2);
	int iItemDefIdx = GetNativeCell(3);

	hClientInfo.Set(iThis, iItemDefIdx, ClientInfo_iEquipItemDefIdx + iSlot);

	int iArr[ClientInfo_Size];
	hClientInfo.GetArray(iThis, iArr, sizeof(iArr));
}

public int Native_ClientInfo_GetEquipClassName(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iSlot = GetNativeCell(2);
	int iLength = GetNativeCell(4);

	int iArr[ClientInfo_Size];
	hClientInfo.GetArray(iThis, iArr, sizeof(iArr));

	char sClassName[128];
	IntArrayToString(iArr[ClientInfo_sEquipClassName + 32*iSlot], 32, sClassName, iLength);

	SetNativeString(3, sClassName, iLength);
}

public int Native_ClientInfo_SetEquipClassName(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iSlot = GetNativeCell(2);

	char sClassName[128];
	GetNativeString(3, sClassName, sizeof(sClassName));

	int iArr[ClientInfo_Size];
	hClientInfo.GetArray(iThis, iArr, sizeof(iArr));

	StringToIntArray(sClassName, iArr[ClientInfo_sEquipClassName + 32*iSlot], 32);
	
	hClientInfo.SetArray(iThis, iArr, sizeof(iArr));
}

public int Native_ClientInfo_Instance(Handle hPlugin, int iArgC) {
	if (hClientInfo == null) {
		hClientInfo = new ArrayList(ClientInfo_Size);
	}

	static int iEmptyClientInfo[ClientInfo_Size] = { 0, ... };

	for (int i=0; i<hClientInfo.Length; i++) {
		if (hClientInfo.Get(i, ClientInfo_bGCFlag)) {
			hClientInfo.SetArray(i, iEmptyClientInfo);
			return i;
		}
	}
	
	hClientInfo.PushArray(iEmptyClientInfo);
	return hClientInfo.Length-1;
}

public int Native_ClientInfo_Destroy(Handle hPlugin, int iArgC) {
	if (hClientInfo != null) {
		int iClientInfo = GetNativeCell(1);
		hClientInfo.Set(iClientInfo, 1, ClientInfo_bGCFlag);
	}
}

// class Recording

#define Recording_sFilePath			0	// char[256] = char[PLATFORM_MAX_PATH] = int[64]
#define Recording_bRepo				64	// int
#define Recording_iDownloading		65	// int
#define Recording_iFileSize			66	// int
#define Recording_iTimestamp		67	// int
#define Recording_hFrames			68	// int
#define Recording_iFramesExpected	69	// int
#define Recording_iLength			70	// int
#define Recording_hClientInfo		71	// int
#define Recording_iEquipFilter		72	// int
#define Recording_iNodeModel		73	// int
#define Recording_iWeaponModel		74	// int
#define Recording_bGCFlag			75	// int
#define Recording_Size				76

static ArrayList hRecordings = null;
const Recording NULL_RECORDING = view_as<Recording>(-1);

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
	
	CreateNative("Recording.Instance",				Native_Recording_Instance);
	CreateNative("Recording.Destroy",				Native_Recording_Destroy);
}

public int Native_Recording_GetFilePath(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iLength = GetNativeCell(3);

	char sFilePath[256];
	hRecordings.GetString(iThis, sFilePath, iLength);
	
	SetNativeString(2, sFilePath, iLength);
}

public int Native_Recording_SetFilePath(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);

	char sFilePath[256];
	GetNativeString(2, sFilePath, sizeof(sFilePath));

	int iArr[Recording_Size];
	hRecordings.GetArray(iThis, iArr, sizeof(iArr));
	
	StringToIntArray(sFilePath, iArr[Recording_sFilePath], 64);
	
	hRecordings.SetArray(iThis, iArr, sizeof(iArr));
}

public int Native_Recording_GetRepo(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hRecordings.Get(iThis, Recording_bRepo);
}

public int Native_Recording_SetRepo(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iRepo = GetNativeCell(2) ? 1 : 0;

	hRecordings.Set(iThis, iRepo, Recording_bRepo);
}

public int Native_Recording_GetDownloading(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hRecordings.Get(iThis, Recording_iDownloading);
}

public int Native_Recording_SetDownloading(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iDownloading = GetNativeCell(2);
	hRecordings.Set(iThis, iDownloading, Recording_iDownloading);
}

public int Native_Recording_GetFileSize(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hRecordings.Get(iThis, Recording_iFileSize);
}

public int Native_Recording_SetFileSize(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iFileSize = GetNativeCell(2);
	hRecordings.Set(iThis, iFileSize, Recording_iFileSize);
}

public int Native_Recording_GetTimestamp(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hRecordings.Get(iThis, Recording_iTimestamp);
}

public int Native_Recording_SetTimestamp(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iTimestamp = GetNativeCell(2);
	hRecordings.Set(iThis, iTimestamp, Recording_iTimestamp);
}

public int Native_Recording_GetFrames(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hRecordings.Get(iThis, Recording_hFrames);
}

public int Native_Recording_GetFramesExpected(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hRecordings.Get(iThis, Recording_iFramesExpected);
}

public int Native_Recording_SetFramesExpected(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iFrames = GetNativeCell(2);
	hRecordings.Set(iThis, iFrames, Recording_iFramesExpected);
}

public int Native_Recording_GetLength(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hRecordings.Get(iThis, Recording_iLength);
}

public int Native_Recording_SetLength(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iLength = GetNativeCell(2);
	hRecordings.Set(iThis, iLength, Recording_iLength);
}

public int Native_Recording_GetClientInfo(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hRecordings.Get(iThis, Recording_hClientInfo);
}

public int Native_Recording_GetEquipFilter(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);

	int iEquipFilter = hRecordings.Get(iThis, Recording_iEquipFilter);
	int iSlot = iEquipFilter & 0xFF;
	int iItemDefIdx = (iEquipFilter >> 16);

	SetNativeCellRef(2, iSlot);
	SetNativeCellRef(3, iItemDefIdx);
}

public int Native_Recording_SetEquipFilter(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iSlot = GetNativeCell(2);
	int iItemDefIdx = GetNativeCell(3);

	int iEquipFilter = (iItemDefIdx << 16) | (iSlot & 0xFF);
	hRecordings.Set(iThis, iEquipFilter, Recording_iEquipFilter);
}

public int Native_Recording_GetNodeModel(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hRecordings.Get(iThis, Recording_iNodeModel);
}

public int Native_Recording_SetNodeModel(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iNodeModel = GetNativeCell(2);
	hRecordings.Set(iThis, iNodeModel, Recording_iNodeModel);
}

public int Native_Recording_GetWeaponModel(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hRecordings.Get(iThis, Recording_iWeaponModel);
}

public int Native_Recording_SetWeaponModel(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iWeaponModel = GetNativeCell(2);
	hRecordings.Set(iThis, iWeaponModel, Recording_iWeaponModel);
}

public int Native_Recording_Instance(Handle hPlugin, int iArgC) {
	if (hRecordings == null) {
		hRecordings = new ArrayList(Recording_Size);
	}
	
	static int iEmptyRecording[Recording_Size] =  { 0, ... };
	iEmptyRecording[Recording_iNodeModel] = INVALID_ENT_REFERENCE;
	iEmptyRecording[Recording_iWeaponModel] = INVALID_ENT_REFERENCE;

	for (int i=0; i<hRecordings.Length; i++) {
		if (hRecordings.Get(i, Recording_bGCFlag)) {
			hRecordings.SetArray(i, iEmptyRecording);
			hRecordings.Set(i, new ArrayList(), Recording_hClientInfo);
			hRecordings.Set(i, new ArrayList(), Recording_hFrames);
			
			return i;
		}
	}
	
	hRecordings.PushArray(iEmptyRecording);
	hRecordings.Set(hRecordings.Length-1, new ArrayList(), Recording_hClientInfo);
	hRecordings.Set(hRecordings.Length-1, new ArrayList(), Recording_hFrames);

	return hRecordings.Length-1;
}

public int Native_Recording_Destroy(Handle hPlugin, int iArgC) {
	if (hRecordings != null) {
		Recording iRecording = GetNativeCell(1);

		hRecordings.Set(view_as<int>(iRecording), 1, Recording_bGCFlag);
		
		ArrayList hRecClientInfo = iRecording.ClientInfo;
		ArrayList hFrames = hRecordings.Get(view_as<int>(iRecording), Recording_hFrames);
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
	
	if (iRecording1.Repo && !iRecording2.Repo) {
		return -1;
	} else if (iRecording1.Repo && !iRecording2.Repo) {
		return 1;
	} else if (iRecording1.Repo && iRecording2.Repo) {
		return 0;
	}
	
	return iRecording1.Timestamp - iRecording2.Timestamp;
}

// Stocks

stock void StringToIntArray(char[] sString, int[] iArray, int iArrayLength) {
	int iStrLen = strlen(sString)+1;
		
	int iBlocks = Math_Max(iStrLen / 4, iArrayLength);
	for (int i = 0; i < iBlocks; i++) {
		iArray[i] = (sString[4*i]) | (sString[4*i+1] << 8) | (sString[4*i+2] << 16) | (sString[4*i+3] << 24);
	}
	
	if (iBlocks < iArrayLength && iStrLen % 4 != 0) {
		switch (iStrLen % 4) {
			case 1: {
				iArray[iBlocks] = view_as<int>(sString[4*iBlocks] << 8);
			}
			case 2: {
				iArray[iBlocks] = view_as<int>((sString[4*iBlocks]) | (sString[4*iBlocks+1] << 8));
			}
			case 3: {
				iArray[iBlocks] = view_as<int>((sString[4*iBlocks]) | (sString[4*iBlocks+1] << 8) | (sString[4*iBlocks+2] << 16));
			}
		}
	}
}

stock void IntArrayToString(int[] iArray, int iArrayLength, char[] sString, int iStringLength) {
	int iBlocks = Math_Max(iArrayLength, iStringLength / 4);
	for (int i = 0; i < iBlocks; i++) {
		sString[4*i  ] = (iArray[i]      ) & 0xFF;
		sString[4*i+1] = (iArray[i] >>  8) & 0xFF;
		sString[4*i+2] = (iArray[i] >> 16) & 0xFF;
		sString[4*i+3] = (iArray[i] >> 24) & 0xFF;
	}
	
	if (iBlocks*4 < iStringLength) {
		switch (iStringLength % 4) {
			case 1: {
				sString[4*iBlocks  ] = (iArray[iBlocks]      ) & 0xFF;
			}
			case 2: {
				sString[4*iBlocks  ] = (iArray[iBlocks]      ) & 0xFF;
				sString[4*iBlocks+1] = (iArray[iBlocks] >>  8) & 0xFF;
			}
			case 3: {
				sString[4*iBlocks  ] = (iArray[iBlocks]      ) & 0xFF;
				sString[4*iBlocks+1] = (iArray[iBlocks] >>  8) & 0xFF;
				sString[4*iBlocks+2] = (iArray[iBlocks] >> 16) & 0xFF;
			}
		}
	}
}