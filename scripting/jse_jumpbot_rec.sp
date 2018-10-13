#if defined _RECORDING_included
 #endinput
#endif
#define _RECORDING_included

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

methodmap ClientInfo {
	property int Idx {
		public get() {
			return view_as<int>(this);
		}
	}
	
	public void GetAuthID(char[] sAuthID, int iLength) {
		int iArr[6];
		hClientInfo.GetArray(view_as<int>(this), iArr, sizeof(iArr));
		
		IntArrayToString(iArr[ClientInfo_sAuthID], 6, sAuthID, iLength);
	}
	
	public void SetAuthID(char[] sAuthID) {
		int iArr[ClientInfo_Size];
		hClientInfo.GetArray(view_as<int>(this), iArr, sizeof(iArr));
		
		StringToIntArray(sAuthID, iArr[ClientInfo_sAuthID], 6);
		
		hClientInfo.SetArray(view_as<int>(this), iArr, sizeof(iArr));
	}

	public void GetName(char[] sName, int iLength) {
		int iArr[14]; // sAuthID + sName
		hClientInfo.GetArray(view_as<int>(this), iArr, sizeof(iArr));
		
		IntArrayToString(iArr[ClientInfo_sName], 8, sName, iLength);
	}
	
	public void SetName(char[] sName) {
		int iArr[ClientInfo_Size];
		hClientInfo.GetArray(view_as<int>(this), iArr, sizeof(iArr));

		StringToIntArray(sName, iArr[ClientInfo_sName], 8);
		
		hClientInfo.SetArray(view_as<int>(this), iArr, sizeof(iArr));
	}

	property TFTeam Team {
		public get() {
			return view_as<TFTeam>(hClientInfo.Get(view_as<int>(this), ClientInfo_iTeam));
		}
		public set(TFTeam iTeam) {
			hClientInfo.Set(view_as<int>(this), iTeam, ClientInfo_iTeam);
		}
	}

	property TFClassType Class {
		public get() {
			return view_as<TFClassType>(hClientInfo.Get(view_as<int>(this), ClientInfo_iClass));
		}
		public set(TFClassType iClass) {
			hClientInfo.Set(view_as<int>(this), iClass, ClientInfo_iClass);
		}
	}
	
	public void GetStartPos(float fStartPos[3]) {
		fStartPos[0] = hClientInfo.Get(view_as<int>(this), ClientInfo_fStartPos  );
		fStartPos[1] = hClientInfo.Get(view_as<int>(this), ClientInfo_fStartPos+1);
		fStartPos[2] = hClientInfo.Get(view_as<int>(this), ClientInfo_fStartPos+2);
	}
	
	public void SetStartPos(float fStartPos[3]) {
		hClientInfo.Set(view_as<int>(this), fStartPos[0], ClientInfo_fStartPos  );
		hClientInfo.Set(view_as<int>(this), fStartPos[1], ClientInfo_fStartPos+1);
		hClientInfo.Set(view_as<int>(this), fStartPos[2], ClientInfo_fStartPos+2);
	}
	
	public void GetStartAng(float fStartAng[3]) {
		fStartAng[0] = hClientInfo.Get(view_as<int>(this), ClientInfo_fStartAng  );
		fStartAng[1] = hClientInfo.Get(view_as<int>(this), ClientInfo_fStartAng+1);
		fStartAng[2] = 0.0;
	}
	
	public void SetStartAng(float fStartAng[3]) {
		hClientInfo.Set(view_as<int>(this), fStartAng[0], ClientInfo_fStartAng  );
		hClientInfo.Set(view_as<int>(this), fStartAng[1], ClientInfo_fStartAng+1);
	}

	public int GetEquipItemDefIdx(int iSlot) {
		return hClientInfo.Get(view_as<int>(this), ClientInfo_iEquipItemDefIdx + iSlot);
	}

	public void SetEquipItemDefIdx(int iSlot, int iItemDefIdx) {
		hClientInfo.Set(view_as<int>(this), iItemDefIdx, ClientInfo_iEquipItemDefIdx + iSlot);

		int iArr[ClientInfo_Size];
		hClientInfo.GetArray(view_as<int>(this), iArr, sizeof(iArr));

		/*
		PrintToServer("SetEquipItemDefIdx(%d, %d):", iSlot, iItemDefIdx);
		for (int i=0; i<8; i++) {
			PrintToServer("\tiEquipItemDefIdx[%d]=%d", i, iArr[ClientInfo_iEquipItemDefIdx + i]);
		}
		*/
	}

	public void GetEquipClassName(int iSlot, char[] sClassName, int iLength) {
		int iArr[ClientInfo_Size];
		hClientInfo.GetArray(view_as<int>(this), iArr, sizeof(iArr));

		IntArrayToString(iArr[ClientInfo_sEquipClassName + 32*iSlot], 32, sClassName, iLength);
	}

	public void SetEquipClassName(int iSlot, char[] sClassName) {
		int iArr[ClientInfo_Size];
		hClientInfo.GetArray(view_as<int>(this), iArr, sizeof(iArr));

		StringToIntArray(sClassName, iArr[ClientInfo_sEquipClassName + 32*iSlot], 32);
		
		hClientInfo.SetArray(view_as<int>(this), iArr, sizeof(iArr));
		/*
		PrintToServer("SetEquipClassName(%d, %s):", iSlot, sClassName);
		for (int i=0; i<8; i++) {
			char sClassName0[128];
			IntArrayToString(iArr[ClientInfo_sEquipClassName + 32*i], 32, sClassName0, 128);
			PrintToServer("\tsEquipClassName[%d]=%s", i, sClassName0);
		}
		*/
	}

	public static ClientInfo Instance() {
		if (hClientInfo == null) {
			hClientInfo = new ArrayList(ClientInfo_Size);
		}

		static int iEmptyClientInfo[ClientInfo_Size] = { 0, ... };

		for (int i=0; i<hClientInfo.Length; i++) {
			if (hClientInfo.Get(i, ClientInfo_bGCFlag)) {
				hClientInfo.SetArray(i, iEmptyClientInfo);
				return view_as<ClientInfo>(i);
			}
		}
		
		hClientInfo.PushArray(iEmptyClientInfo);
		return view_as<ClientInfo>(hClientInfo.Length-1);
	}

	public static void Destroy(ClientInfo iClientInfo) {
		if (hClientInfo != null) {
			hClientInfo.Set(iClientInfo.Idx, 0, ClientInfo_bGCFlag);
		}
	}

	public static void DestroyAll() {
		if (hClientInfo != null) {
			hClientInfo.Clear();
		}
	}
}

// class Recording

#define Recording_sFilePath		0	// char[256] = char[PLATFORM_MAX_PATH] = int[64]
#define Recording_bRepo			64	// int
#define Recording_iDownloading	65	// int
#define Recording_iFileSize		66	// int
#define Recording_iTimestamp	67	// int
#define Recording_hFrames		68	// int
#define Recording_iLength		69	// int
#define Recording_hClientInfo	70	// int
#define Recording_iNodeModel	71	// int
#define Recording_iWeaponModel	72	// int
#define Recording_bGCFlag		73	// int
#define Recording_Size			74

static ArrayList hRecordings = null;
const Recording NULL_RECORDING = view_as<Recording>(-1);

methodmap Recording {
	public void GetFilePath(char[] sFilePath, int iLength) {
		hRecordings.GetString(view_as<int>(this), sFilePath, iLength);
	}

	public void SetFilePath(char[] sFilePath) {
		int iArr[Recording_Size];
		hRecordings.GetArray(view_as<int>(this), iArr, sizeof(iArr));
		
		StringToIntArray(sFilePath, iArr[Recording_sFilePath], 64);
		
		hRecordings.SetArray(view_as<int>(this), iArr, sizeof(iArr));
	}
		
	property bool Repo {
		public get() {
			return view_as<bool>(hRecordings.Get(view_as<int>(this), Recording_bRepo));
		}
		public set(bool bRepo) {
			hRecordings.Set(view_as<int>(this), view_as<int>(bRepo), Recording_bRepo);
		}
	}
	
	property int Downloading {
		public get() {
			return hRecordings.Get(view_as<int>(this), Recording_iDownloading);
		}
		public set(int iDownloading) {
			hRecordings.Set(view_as<int>(this), iDownloading, Recording_iDownloading);
		}
	}
	
	property int FileSize {
		public get() {
			return hRecordings.Get(view_as<int>(this), Recording_iFileSize);
		}
		public set(int iFileSize) {
			hRecordings.Set(view_as<int>(this), iFileSize, Recording_iFileSize);
		}
	}

	property int Timestamp {
		public get() {
			return hRecordings.Get(view_as<int>(this), Recording_iTimestamp);
		}
		public set(int iTimestamp) {
			hRecordings.Set(view_as<int>(this), iTimestamp, Recording_iTimestamp);
		}
	}
	
	property ArrayList Frames {
		public get() {
			return hRecordings.Get(view_as<int>(this), Recording_hFrames);
		}
	}

	property int Length {
		public get() {
			return hRecordings.Get(view_as<int>(this), Recording_iLength);
		}
		public set(int iLength) {
			hRecordings.Set(view_as<int>(this), iLength, Recording_iLength);
		}
	}

	property ArrayList RecClientInfo {
		public get() {
			return hRecordings.Get(view_as<int>(this), Recording_hClientInfo);
		}
	}
	
	property int NodeModel {
		public get() {
			return hRecordings.Get(view_as<int>(this), Recording_iNodeModel);
		}
		
		public set(int iNodeModel) {
			hRecordings.Set(view_as<int>(this), iNodeModel, Recording_iNodeModel);
		}
	}
	
	property int WeaponModel {
		public get() {
			return hRecordings.Get(view_as<int>(this), Recording_iWeaponModel);
		}
		
		public set(int iWeaponModel) {
			hRecordings.Set(view_as<int>(this), iWeaponModel, Recording_iWeaponModel);
		}
	}

	// public static class functions
	
	public static Recording Instance() {
		if (hRecordings == null) {
			hRecordings = new ArrayList(Recording_Size);
		}
		
		static int iEmptyRecording[Recording_Size] =  { 0, ... };

		for (int i=0; i<hRecordings.Length; i++) {
			if (hRecordings.Get(i, Recording_bGCFlag)) {
				hRecordings.SetArray(i, iEmptyRecording);
				hRecordings.Set(i, new ArrayList(ClientInfo_Size), Recording_hClientInfo);
				hRecordings.Set(i, new ArrayList(), Recording_hFrames);
				
				return view_as<Recording>(i);
			}
		}
		
		hRecordings.PushArray(iEmptyRecording);
		hRecordings.Set(hRecordings.Length-1, new ArrayList(ClientInfo_Size), Recording_hClientInfo);
		hRecordings.Set(hRecordings.Length-1, new ArrayList(), Recording_hFrames);

		return view_as<Recording>(hRecordings.Length-1);
	}

	public static void Destroy(Recording iRecording) {
		if (hRecordings != null) {
			hRecordings.Set(view_as<int>(iRecording), 1, Recording_bGCFlag);
			
			ArrayList hRecClientInfo = iRecording.RecClientInfo;
			ArrayList hFrames = hRecordings.Get(view_as<int>(iRecording), Recording_hFrames);
			delete hFrames;

			for (int i=0; i<hRecClientInfo.Length; i++) {
				ClientInfo iClientInfo = hRecClientInfo.Get(i);
				ClientInfo.Destroy(iClientInfo);
			}
			
			hRecClientInfo.Clear();
			
		}
	}

	public static void DestroyAll() {
		if (hRecordings != null) {
			for (int i=0; i<hRecordings.Length; i++) {
				Recording iRecording = view_as<Recording>(i);
				ArrayList hRecClientInfo = iRecording.RecClientInfo;
				for (int j=0; j<hRecClientInfo.Length; j++) {
					ClientInfo iClientInfo = hRecClientInfo.Get(j);
					ClientInfo.Destroy(iClientInfo);
					delete hRecClientInfo;
				}
				ArrayList hFrames = iRecording.Frames;
				delete hFrames;

				hRecClientInfo.Clear();
			}

			hRecordings.Clear();
		}
	}
	/*
	public static void Sort() {
		if (hRecordings != null) {
			SortADTArrayCustom(hRecordings, Sort_Recordings);
		}
	}

	*/
}

public int Sort_Recordings(int iIdx1, int iIdx2, Handle hArray, Handle hParam) {
	Recording iRecording1 = view_as<Recording>(iIdx1);
	Recording iRecording2 = view_as<Recording>(iIdx2);
	
	if (iRecording1.Repo && !iRecording2.Repo) {
		return -1;
	} else if (iRecording1.Repo && !iRecording2.Repo) {
		return 1;
	} else if (iRecording1.Repo && iRecording2.Repo) {
		return 0;
	}
	
	char sFilePath1[PLATFORM_MAX_PATH];
	char sFilePath2[PLATFORM_MAX_PATH];
	iRecording1.GetFilePath(sFilePath1, sizeof(sFilePath1));
	iRecording2.GetFilePath(sFilePath2, sizeof(sFilePath2));
	
	return strcmp(sFilePath1, sFilePath2);
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