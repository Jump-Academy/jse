#if defined _JSE_TRACKER_included
 #endinput
#endif
#define _JSE_TRACKER_included

#include <tf2>
#include <tf2_stocks>

public SharedPlugin __pl_jse_tracker = 
{
	name = "jse_tracker",
	file = "jse_tracker.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_jse_tracker_SetNTVOptional()
{
	MarkNativeAsOptional("Jump.iID.get");
	MarkNativeAsOptional("Jump.iID.set");
	MarkNativeAsOptional("Jump.iNumber.get");
	MarkNativeAsOptional("Jump.iNumber.set");
	MarkNativeAsOptional("Jump.GetOrigin");
	MarkNativeAsOptional("Jump.SetOrigin");
	MarkNativeAsOptional("Jump.fAngle.get");
	MarkNativeAsOptional("Jump.fAngle.set");
	MarkNativeAsOptional("Jump.GetIdentifier");
	MarkNativeAsOptional("Jump.SetIdentifier");
	MarkNativeAsOptional("Jump.Instance");
	MarkNativeAsOptional("Jump.Destroy");

	MarkNativeAsOptional("ControlPoint.iID.get");
	MarkNativeAsOptional("ControlPoint.iID.set");
	MarkNativeAsOptional("ControlPoint.GetOrigin");
	MarkNativeAsOptional("ControlPoint.SetOrigin");
	MarkNativeAsOptional("ControlPoint.fAngle.get");
	MarkNativeAsOptional("ControlPoint.fAngle.set");
	MarkNativeAsOptional("ControlPoint.GetIdentifier");
	MarkNativeAsOptional("ControlPoint.SetIdentifier");
	MarkNativeAsOptional("ControlPoint.Instance");
	MarkNativeAsOptional("ControlPoint.Destroy");

	MarkNativeAsOptional("Course.iID.get");
	MarkNativeAsOptional("Course.iID.set");
	MarkNativeAsOptional("Course.iNumber.get");
	MarkNativeAsOptional("Course.iNumber.set");
	MarkNativeAsOptional("Course.Jumps.get");
	MarkNativeAsOptional("Course.ControlPoint.get");
	MarkNativeAsOptional("Course.ControlPoint.set");
	MarkNativeAsOptional("Course.GetName");
	MarkNativeAsOptional("Course.SetName");
	MarkNativeAsOptional("Course.Instance");
	MarkNativeAsOptional("Course.Destroy");

	MarkNativeAsOptional("IsTrackerLoaded");
	MarkNativeAsOptional("GetTrackerDatabase");
	MarkNativeAsOptional("GetTrackerMapID");
	MarkNativeAsOptional("GetTrackerCourses");

	MarkNativeAsOptional("GetPlayerNearestCheckpoint");
	MarkNativeAsOptional("GetPlayerNewestCheckpoint");
	MarkNativeAsOptional("GetPlayerLastCheckpoint");
	
	MarkNativeAsOptional("GetPlayerProgress");
	MarkNativeAsOptional("ResetPlayerProgress");

	MarkNativeAsOptional("ResolveCourseNumber");
	MarkNativeAsOptional("ResolveJumpNumber");

	MarkNativeAsOptional("GetCourseDisplayName");
	MarkNativeAsOptional("GetCheckpointDisplayName");
	MarkNativeAsOptional("GetCourseCheckpointDisplayName");
}
#endif

methodmap Jump {
	property int iID {
		public native get();
		public native set(int iID);
	}

	property int iNumber {
		public native get();
		public native set(int iNumber);
	}

	property float fAngle {
		public native get();
		public native set(float fAngle);
	}

	public native void GetOrigin(float fOrigin[3]);
	public native void SetOrigin(float fOrigin[3]);
	public native void GetIdentifier(char[] sIdentifier, int iLength);
	public native void SetIdentifier(char[] sIdentifier);

	public static native Jump Instance();
	public static native void Destroy(Jump iJump);
}

methodmap ControlPoint {
	property int iID {
		public native get();
		public native set(int iID);
	}

	property float fAngle {
		public native get();
		public native set(float fAngle);
	}

	public native void GetOrigin(float fOrigin[3]);
	public native void SetOrigin(float fOrigin[3]);
	public native void GetIdentifier(char[] sIdentifier, int iLength);
	public native void SetIdentifier(char[] sIdentifier);

	public static native ControlPoint Instance();
	public static native void Destroy(ControlPoint iControlPoint);
}

methodmap Course {
	property int iID {
		public native get();
		public native set(int iID);
	}

	property int iNumber {
		public native get();
		public native set(int iNumber);
	}

	property ArrayList hJumps {
		public native get();
	}

	property ControlPoint iControlPoint {
		public native get();
		public native set(ControlPoint iControlPoint);
	}

	public native void GetName(char[] sName, int iLength);
	public native void SetName(char[] sName);

	public static native Course Instance();
	public static native void Destroy(Course iCourse);
}

/*
	Progress hash 32-bit map

	hi                                   lo
	cccc ccjj jjjj jjtt aaaa ppps ssmm rrrr

	info      * bits  range
    -----------------------
	course    c  6     64
	jump      j  8     256

	team      t  2     4
	class     a  4     16

	primary   p  3     8
	secondary s  3     8
	melee     m  2     4

	reserved  r  4     16
*/

enum struct Checkpoint {
	int iHash;
	int iUnlockTime;
	int iArrivalTime;
	int iLastUpdateTime;

	void Init(int iCourseNumber, int iJumpNumber, bool bControlPoint, TFTeam iTeam, TFClassType iClass, int iPrimary=0, int iSecondary=0, int iMelee=0) {
		iCourseNumber &= 0x3F;
		iJumpNumber = bControlPoint ? 0 : iJumpNumber & 0xFF;
	
		this.iHash = iCourseNumber << 26 | iJumpNumber << 18 | view_as<int>(iTeam) << 16 | view_as<int>(iClass) << 12 | (iPrimary & 0x7) << 9 | (iSecondary & 0x7) << 6 | (iMelee & 0x3) << 4;
	}

	int GetCourseNumber() {
		int iCourseNumber = this.iHash >>> 26;
		if (iCourseNumber > 31) {
			return iCourseNumber-64;
		}

		return iCourseNumber;
	}

	void SetCourseNumber(int iCourseNumber) {
		this.iHash = this.iHash & 0x03FFFFFF | (iCourseNumber & 0x3F) << 26;
	}

	int GetJumpNumber() {
		return this.iHash >>> 18 & 0xFF;
	}

	void SetJumpNumber(int iJumpNumber) {
		this.iHash = this.iHash & 0xFC03FFFF | (iJumpNumber & 0xFF) << 18;
	}

	bool IsControlPoint() {
		return (this.iHash >>> 18 & 0xFF) == 0;
	}

	void SetControlPoint() {
		this.iHash = this.iHash & 0xFC03FFFF;
	}

	TFTeam GetTeam() {
		return view_as<TFTeam>((this.iHash >>> 16) & 0x3);
	}

	void SetTeam(TFTeam iTeam) {
		this.iHash = this.iHash & 0xFFFCFFFF | view_as<int>(iTeam) << 16;
	}

	TFClassType GetClass() {
		return view_as<TFClassType>((this.iHash >>> 12) & 0xF);
	}

	void SetClass(TFClassType iClass) {
		this.iHash = this.iHash & 0xFFFF0FFF | view_as<int>(iClass) << 12;
	}

	int GetLoadout(int iSlot) {
		assert(TFWeaponSlot_Primary <= iSlot && iSlot <= TFWeaponSlot_Melee);

		switch (iSlot) {
			case TFWeaponSlot_Primary: {
				return (this.iHash >>> 9) & 0x7;
			}
			case TFWeaponSlot_Secondary: {
				return (this.iHash >>> 6) & 0x7;
			}
			case TFWeaponSlot_Melee: {
				return (this.iHash >>> 4) & 0x3;
			}
		}

		return 0;
	}

	void SetLoadout(int iSlot, int iItem) {
		assert(TFWeaponSlot_Primary <= iSlot && iSlot <= TFWeaponSlot_Melee);

		switch (iSlot) {
			case TFWeaponSlot_Primary: {
				this.iHash = this.iHash & 0xFFFFF1FF | (iItem & 0x7) << 9;
			}
			case TFWeaponSlot_Secondary: {
				this.iHash = this.iHash & 0xFFFFFE3F | (iItem & 0x7) << 6;
			}
			case TFWeaponSlot_Melee: {
				this.iHash = this.iHash & 0xFFFFFFCF | (iItem & 0x3) << 4;
			}
		}
	}

	void Clear() {
		this.iHash = 0;
		this.iUnlockTime = 0;
		this.iArrivalTime = 0;
		this.iLastUpdateTime = 0;
	}
}

const Course NULL_COURSE = view_as<Course>(0);
const Jump NULL_JUMP = view_as<Jump>(0);
const ControlPoint NULL_CONTROLPOINT = view_as<ControlPoint>(0);

forward void OnTrackerDatabaseConnected(Database hDatabase);
forward void OnTrackerLoaded(ArrayList hCourses);

forward Action OnProgressLoad(int iClient);
forward void OnProgressLoaded(int iClient);
forward void OnCheckpointApproached(int iClient, int iCourseNumber, int iJumpNumber, bool bControlPoint);
forward void OnCheckpointReached(int iClient, int iCourseNumber, int iJumpNumber, bool bControlPoint);
forward void OnNewCheckpointReached(int iClient, int iCourseNumber, int iJumpNumber, bool bControlPoint, bool bUnlock);

native bool IsTrackerLoaded();
native Database GetTrackerDatabase();
native int GetTrackerMapID();
native ArrayList GetTrackerCourses();

native bool GetPlayerNearestCheckpoint(int iClient, int &iCourseNumber, int &iJumpNumber, bool &bControlPoint);
native bool GetPlayerNewestCheckpoint(int iClient, int &iCourseNumber, int &iJumpNumber, bool &bControlPoint, int &iLastUpdateTime=0, TFTeam iTeam=TFTeam_Unassigned, TFClassType iClass=TFClass_Unknown);
native bool GetPlayerLastCheckpoint(int iClient, int &iCourseNumber, int &iJumpNumber, bool &bControlPoint, int &iUnlockTime=0, int &iArrivalTimeTime=0, int &iLastUpdateTime=0, TFTeam &iTeam=TFTeam_Unassigned, TFClassType &iClass=TFClass_Unknown);

native int GetPlayerProgress(int iClient, ArrayList hResult, TFTeam iTeam=TFTeam_Unassigned, TFClassType iClass=TFClass_Unknown, char[] sMapName=NULL_STRING, ProgressLookup pCallback=INVALID_FUNCTION, any aData=0);
native void ResetPlayerProgress(int iClient, TFTeam iTeam=TFTeam_Unassigned, TFClassType iClass=TFClass_Unknown, bool bPersist=false, char[] sMapName=NULL_STRING);

typedef ProgressLookup = function void (int iClient, ArrayList hResult, int iResults, char[] sMapName, StringMap hCourseNames, StringMap hCourseLengths, any aData);

native Course ResolveCourseNumber(int iCourseNumber);
native Jump ResolveJumpNumber(Course iCourse, int iJumpNumber);

native bool GetCourseDisplayName(Course iCourse, char[] sBuffer, int iMaxLen);
native bool GetCheckpointDisplayName(Course iCourse, int iJumpNumber, bool bControlPoint, char[] sBuffer, int iMaxLen);
native void GetCourseCheckpointDisplayName(Course iCourse, int iJumpNumber, bool bControlPoint, char[] sBuffer, int iMaxLen);
