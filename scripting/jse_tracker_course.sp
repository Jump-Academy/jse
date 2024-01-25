public void Course_SetupNatives() {
	CreateNative("Jump.iID.get",					Native_Jump_GetID);
	CreateNative("Jump.iID.set",					Native_Jump_SetID);
	CreateNative("Jump.iNumber.get",				Native_Jump_GetNumber);
	CreateNative("Jump.iNumber.set",				Native_Jump_SetNumber);
	CreateNative("Jump.GetOrigin",					Native_Jump_GetOrigin);
	CreateNative("Jump.SetOrigin",					Native_Jump_SetOrigin);
	CreateNative("Jump.fAngle.get",					Native_Jump_GetAngle);
	CreateNative("Jump.fAngle.set",					Native_Jump_SetAngle);
	CreateNative("Jump.GetIdentifier",				Native_Jump_GetIdentifier);
	CreateNative("Jump.SetIdentifier",				Native_Jump_SetIdentifier);
	CreateNative("Jump.Instance",					Native_Jump_Instance);
	CreateNative("Jump.Destroy",					Native_Jump_Destroy);

	CreateNative("ControlPoint.iID.get",			Native_ControlPoint_GetID);
	CreateNative("ControlPoint.iID.set",			Native_ControlPoint_SetID);
	CreateNative("ControlPoint.GetOrigin",			Native_ControlPoint_GetOrigin);
	CreateNative("ControlPoint.SetOrigin",			Native_ControlPoint_SetOrigin);
	CreateNative("ControlPoint.fAngle.get",			Native_ControlPoint_GetAngle);
	CreateNative("ControlPoint.fAngle.set",			Native_ControlPoint_SetAngle);
	CreateNative("ControlPoint.GetIdentifier",		Native_ControlPoint_GetIdentifier);
	CreateNative("ControlPoint.SetIdentifier",		Native_ControlPoint_SetIdentifier);
	CreateNative("ControlPoint.Instance",			Native_ControlPoint_Instance);
	CreateNative("ControlPoint.Destroy",			Native_ControlPoint_Destroy);

	CreateNative("Course.iID.get",					Native_Course_GetID);
	CreateNative("Course.iID.set",					Native_Course_SetID);
	CreateNative("Course.iNumber.get",				Native_Course_GetNumber);
	CreateNative("Course.iNumber.set",				Native_Course_SetNumber);
	CreateNative("Course.hJumps.get",				Native_Course_GetJumps);
	CreateNative("Course.mControlPoint.get",		Native_Course_GetControlPoint);
	CreateNative("Course.mControlPoint.set",		Native_Course_SetControlPoint);
	CreateNative("Course.GetName",					Native_Course_GetName);
	CreateNative("Course.SetName",					Native_Course_SetName);
	CreateNative("Course.Instance",					Native_Course_Instance);
	CreateNative("Course.Destroy",					Native_Course_Destroy);
}

// class Jump

enum struct _Jump {
	int iID;
	int iNumber;
	float vecOrigin[3];
	float fAngle;
	char sIdentifier[128];
	bool bGCFlag;
}

static ArrayList hJumps = null;

public int Native_Jump_GetID(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	
	return hJumps.Get(iThis, _Jump::iID);
}

public int Native_Jump_SetID(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iID = GetNativeCell(2);
	
	hJumps.Set(iThis, iID, _Jump::iID);

	return 0;
}

public int Native_Jump_GetNumber(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	
	return hJumps.Get(iThis, _Jump::iNumber);
}

public int Native_Jump_SetNumber(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iNumber = GetNativeCell(2);
	
	hJumps.Set(iThis, iNumber, _Jump::iNumber);

	return 0;
}

public int Native_Jump_GetOrigin(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	_Jump eJump;
	hJumps.GetArray(iThis, eJump, sizeof(_Jump));

	SetNativeArray(2, eJump.vecOrigin, sizeof(_Jump::vecOrigin));

	return 0;
}

public int Native_Jump_SetOrigin(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	float vecOrigin[3];
	GetNativeArray(2, vecOrigin, sizeof(vecOrigin));

	_Jump eJump;
	hJumps.GetArray(iThis, eJump, sizeof(_Jump));

	eJump.vecOrigin[0] = vecOrigin[0];
	eJump.vecOrigin[1] = vecOrigin[1];
	eJump.vecOrigin[2] = vecOrigin[2];

	hJumps.SetArray(iThis, eJump);

	return 0;
}

public any Native_Jump_GetAngle(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	
	return hJumps.Get(iThis, _Jump::fAngle);
}

public int Native_Jump_SetAngle(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	float fAngle = GetNativeCell(2);
	
	hJumps.Set(iThis, fAngle, _Jump::fAngle);

	return 0;
}

public int Native_Jump_GetIdentifier(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iLength = GetNativeCell(3);

	if (iLength > sizeof(_Jump::sIdentifier)) {
		iLength = sizeof(_Jump::sIdentifier);
	}

	_Jump eJump;
	hJumps.GetArray(iThis, eJump, sizeof(_Jump));

	SetNativeString(2, eJump.sIdentifier, iLength);

	return 0;
}

public int Native_Jump_SetIdentifier(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_Jump eJump;
	hJumps.GetArray(iThis, eJump, sizeof(_Jump));

	GetNativeString(2, eJump.sIdentifier, sizeof(_Jump::sIdentifier));

	hJumps.SetArray(iThis, eJump);

	return 0;
}

public int Native_Jump_Instance(Handle hPlugin, int iArgC) {
	if (hJumps == null) {
		hJumps = new ArrayList(sizeof(_Jump));
	}

	_Jump eJump;
	
	for (int i=0; i<hJumps.Length; i++) {
		if (hJumps.Get(i, _Jump::bGCFlag)) {
			hJumps.SetArray(i, eJump);

			return i+1;
		}
	}

	return hJumps.PushArray(eJump) + 1;
}

public int Native_Jump_Destroy(Handle hPlugin, int iArgC) {
	if (hJumps != null) {
		int iJump = GetNativeCell(1)-1;

		hJumps.Set(iJump, 1, _Jump::bGCFlag);
	}

	return 0;
}

// class ControlPoint

enum struct _ControlPoint {
	int iID;
	float vecOrigin[3];
	float fAngle;
	char sIdentifier[128];
	bool bGCFlag;
}

static ArrayList hControlPoints = null;

public int Native_ControlPoint_GetID(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	
	return hControlPoints.Get(iThis, _ControlPoint::iID);
}

public int Native_ControlPoint_SetID(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iID = GetNativeCell(2);
	
	hControlPoints.Set(iThis, iID, _ControlPoint::iID);

	return 0;
}

public int Native_ControlPoint_GetOrigin(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	_ControlPoint eControlPoint;
	hControlPoints.GetArray(iThis, eControlPoint, sizeof(_ControlPoint));

	SetNativeArray(2, eControlPoint.vecOrigin, sizeof(_ControlPoint::vecOrigin));

	return 0;
}

public int Native_ControlPoint_SetOrigin(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	float vecOrigin[3];
	GetNativeArray(2, vecOrigin, sizeof(vecOrigin));

	_ControlPoint eControlPoint;
	hControlPoints.GetArray(iThis, eControlPoint, sizeof(_ControlPoint));

	eControlPoint.vecOrigin[0] = vecOrigin[0];
	eControlPoint.vecOrigin[1] = vecOrigin[1];
	eControlPoint.vecOrigin[2] = vecOrigin[2];

	hControlPoints.SetArray(iThis, eControlPoint);

	return 0;
}

public any Native_ControlPoint_GetAngle(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	return hControlPoints.Get(iThis, _ControlPoint::fAngle);
}

public int Native_ControlPoint_SetAngle(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	float fAngle = GetNativeCell(2);

	hControlPoints.Set(iThis, fAngle, _ControlPoint::fAngle);

	return 0;
}

public int Native_ControlPoint_GetIdentifier(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iLength = GetNativeCell(3);

	if (iLength > sizeof(_ControlPoint::sIdentifier)) {
		iLength = sizeof(_ControlPoint::sIdentifier);
	}

	_ControlPoint eControlPoint;
	hControlPoints.GetArray(iThis, eControlPoint, sizeof(_ControlPoint));

	SetNativeString(2, eControlPoint.sIdentifier, iLength);

	return 0;
}

public int Native_ControlPoint_SetIdentifier(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_ControlPoint eControlPoint;
	hControlPoints.GetArray(iThis, eControlPoint, sizeof(_ControlPoint));

	GetNativeString(2, eControlPoint.sIdentifier, sizeof(_ControlPoint::sIdentifier));

	hControlPoints.SetArray(iThis, eControlPoint);

	return 0;
}

public int Native_ControlPoint_Instance(Handle hPlugin, int iArgC) {
	if (hControlPoints == null) {
		hControlPoints = new ArrayList(sizeof(_ControlPoint));
	}

	_ControlPoint eControlPoint;
	
	for (int i=0; i<hControlPoints.Length; i++) {
		if (hControlPoints.Get(i, _ControlPoint::bGCFlag)) {
			hControlPoints.SetArray(i, eControlPoint);

			return i+1;
		}
	}

	hControlPoints.PushArray(eControlPoint);

	return hControlPoints.Length;
}

public int Native_ControlPoint_Destroy(Handle hPlugin, int iArgC) {
	if (hControlPoints != null) {
		int iControlPoint = GetNativeCell(1)-1;

		hControlPoints.Set(iControlPoint, 1, _ControlPoint::bGCFlag);
	}

	return 0;
}

// class Course

enum struct _Course {
	int iID;
	int iNumber;
	ArrayList hJumps;
	ControlPoint mControlPoint;
	char sName[128];
	bool bGCFlag;
}

static ArrayList hCourses = null;

public int Native_Course_GetID(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	
	return hCourses.Get(iThis, _Course::iID);
}

public int Native_Course_SetID(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iID = GetNativeCell(2);
	
	hCourses.Set(iThis, iID, _Course::iID);

	return 0;
}

public int Native_Course_GetNumber(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return hCourses.Get(iThis, _Course::iNumber);
}

public int Native_Course_SetNumber(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iNumber = GetNativeCell(2);
	hCourses.Set(iThis, iNumber, _Course::iNumber);

	return 0;
}

public int Native_Course_GetJumps(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return hCourses.Get(iThis, _Course::hJumps);
}

public int Native_Course_GetControlPoint(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	return hCourses.Get(iThis, _Course::mControlPoint);
}

public int Native_Course_SetControlPoint(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	ControlPoint mControlPoint = GetNativeCell(2);
	hCourses.Set(iThis, mControlPoint, _Course::mControlPoint);

	return 0;
}

public int Native_Course_GetName(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;
	int iLength = GetNativeCell(3);

	if (iLength > sizeof(_Course::sName)) {
		iLength = sizeof(_Course::sName);
	}

	_Course eCourse;
	hCourses.GetArray(iThis, eCourse, sizeof(_Course));

	SetNativeString(2, eCourse.sName, iLength);

	return 0;
}

public int Native_Course_SetName(Handle hPlugin, int iArgC) {
	int iThis = GetNativeCell(1)-1;

	_Course eCourse;
	hCourses.GetArray(iThis, eCourse, sizeof(_Course));

	GetNativeString(2, eCourse.sName, sizeof(_Course::sName));

	hCourses.SetArray(iThis, eCourse);

	return 0;
}

public int Native_Course_Instance(Handle hPlugin, int iArgC) {
	if (hCourses == null) {
		hCourses = new ArrayList(sizeof(_Course));
	}

	_Course eCourse;
	eCourse.hJumps = new ArrayList(sizeof(_Jump));
	eCourse.mControlPoint = NULL_CONTROLPOINT;

	for (int i=0; i<hCourses.Length; i++) {
		if (hCourses.Get(i, _Course::bGCFlag)) {
			hCourses.SetArray(i, eCourse);

			return i+1;
		}
	}

	hCourses.PushArray(eCourse);

	return hCourses.Length;
}

public int Native_Course_Destroy(Handle hPlugin, int iArgC) {
	if (hCourses != null) {
		int iCourse = GetNativeCell(1)-1;

		_Course eCourse;
		hCourses.GetArray(iCourse, eCourse, sizeof(_Course));

		ArrayList hJumpList = view_as<ArrayList>(eCourse.hJumps);
		for (int i=0; i<hJumpList.Length; i++) {
			Jump.Destroy(hJumpList.Get(i));
		}
		delete hJumpList;

		if (eCourse.mControlPoint) {
			ControlPoint.Destroy(eCourse.mControlPoint);
		}

		hCourses.Set(iCourse, 1, _Course::bGCFlag);
	}

	return 0;
}
