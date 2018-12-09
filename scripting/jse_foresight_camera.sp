// class FSCamera

#define Camera_iClient			0
#define Camera_iEntity			1
#define Camera_iViewControl		2
#define Camera_fStartTime		3
#define Camera_bGCFlag			4
#define Camera_Size				5

static ArrayList hCameras = null;
const FSCamera NULL_CAMERA = view_as<FSCamera>(-1);

public void Camera_SetupNatives() {
	CreateNative("FSCamera.Client.get",			Native_Camera_GetClient);
	CreateNative("FSCamera.Client.set",			Native_Camera_SetClient);

	CreateNative("FSCamera.Entity.get",			Native_Camera_GetEntity);
	CreateNative("FSCamera.Entity.set",			Native_Camera_SetEntity);

	CreateNative("FSCamera.ViewControl.get",		Native_Camera_GetViewControl);
	CreateNative("FSCamera.ViewControl.set",		Native_Camera_SetViewControl);

	CreateNative("FSCamera.StartTime.get",		Native_Camera_GetStartTime);
	CreateNative("FSCamera.StartTime.set",		Native_Camera_SetStartTime);

	CreateNative("FSCamera.Instance",				Native_Camera_Instance);
	CreateNative("FSCamera.Destroy",				Native_Camera_Destroy);
}

public int Native_Camera_GetClient(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hCameras.Get(iThis, Camera_iClient);
}

public int Native_Camera_SetClient(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iClient = GetNativeCell(2);
	hCameras.Set(iThis, iClient, Camera_iClient);
}

public int Native_Camera_GetEntity(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hCameras.Get(iThis, Camera_iEntity);
}

public int Native_Camera_SetEntity(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iEntity = GetNativeCell(2);
	hCameras.Set(iThis, iEntity, Camera_iEntity);
}

public int Native_Camera_GetViewControl(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hCameras.Get(iThis, Camera_iViewControl);
}

public int Native_Camera_SetViewControl(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	int iViewControl = GetNativeCell(2);
	hCameras.Set(iThis, iViewControl, Camera_iViewControl);
}

public int Native_Camera_GetStartTime(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	return hCameras.Get(iThis, Camera_fStartTime);
}

public int Native_Camera_SetStartTime(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1);
	float fStartTime = GetNativeCell(2);
	hCameras.Set(iThis, fStartTime, Camera_fStartTime);
}

public int Native_Camera_Instance(Handle hPlugin, int iArgC) {
	if (hCameras == null) {
		hCameras = new ArrayList(Camera_Size);
	}
	
	static any iEmptyCamera[Camera_Size] =  { 0, ... };
	iEmptyCamera[Camera_iEntity] = INVALID_ENT_REFERENCE;
	iEmptyCamera[Camera_iViewControl] = INVALID_ENT_REFERENCE;

	for (int i=0; i<hCameras.Length; i++) {
		if (hCameras.Get(i, Camera_bGCFlag)) {
			hCameras.SetArray(i, iEmptyCamera);

			return i;
		}
	}
	
	hCameras.PushArray(iEmptyCamera);
	
	return hCameras.Length-1;
}

public int Native_Camera_Destroy(Handle hPlugin, int iArgC) {
	if (hCameras != null) {
		FSCamera iCamera = GetNativeCell(1);

		hCameras.Set(view_as<int>(iCamera), 1, Camera_bGCFlag);
	}
}
