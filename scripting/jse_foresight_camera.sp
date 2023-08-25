static ArrayList m_hFSCameras = null;
const FSCamera NULL_CAMERA = view_as<FSCamera>(0);

enum struct _FSCamera {
	int iClient;
	int iEntityRef;
	int iViewControlRef;
	float fStartTime;
	bool bGCFlag;
}

methodmap FSCamera {
	property int iClient {
		public get() {
			return m_hFSCameras.Get(view_as<int>(this)-1, _FSCamera::iClient);
		}

		public set(int iClient) {
			m_hFSCameras.Set(view_as<int>(this)-1, iClient, _FSCamera::iClient);
		}
	}

	property int iEntity {
		public get() {
			return EntRefToEntIndex(m_hFSCameras.Get(view_as<int>(this)-1, _FSCamera::iEntityRef));
		}

		public set(int iEntity) {
			int iEntRef = IsValidEntity(iEntity) ? EntIndexToEntRef(iEntity) : INVALID_ENT_REFERENCE;
			m_hFSCameras.Set(view_as<int>(this)-1, iEntRef, _FSCamera::iEntityRef);
		}
	}

	property int iViewControl {
		public get() {
			return EntRefToEntIndex(m_hFSCameras.Get(view_as<int>(this)-1, _FSCamera::iViewControlRef));
		}

		public set(int iViewControl) {
			int iViewControlRef = IsValidEntity(iViewControl) ? EntIndexToEntRef(iViewControl) : INVALID_ENT_REFERENCE;
			m_hFSCameras.Set(view_as<int>(this)-1, iViewControlRef, _FSCamera::iViewControlRef);
		}
	}

	property float fStartTime {
		public get() {
			return m_hFSCameras.Get(view_as<int>(this)-1, _FSCamera::fStartTime);
		}

		public set(float fStartTime) {
			m_hFSCameras.Set(view_as<int>(this)-1, fStartTime, _FSCamera::fStartTime);
		}
	}

	public static FSCamera Instance() {
		if (m_hFSCameras == null) {
			m_hFSCameras = new ArrayList(sizeof(_FSCamera));
		}
		
		_FSCamera eFSCamera;
		eFSCamera.iEntityRef = INVALID_ENT_REFERENCE;
		eFSCamera.iViewControlRef = INVALID_ENT_REFERENCE;

		for (int i=0; i<m_hFSCameras.Length; i++) {
			if (m_hFSCameras.Get(i, _FSCamera::bGCFlag)) {
				m_hFSCameras.SetArray(i, eFSCamera);

				return view_as<FSCamera>(i+1);
			}
		}
		
		return view_as<FSCamera>(m_hFSCameras.PushArray(eFSCamera)+1);
	}

	public static void Destroy(FSCamera &mCamera) {
		if (m_hFSCameras != null) {
			m_hFSCameras.Set(view_as<int>(mCamera)-1, 1, _FSCamera::bGCFlag);
		}

		mCamera = NULL_CAMERA;
	}
}
