#if defined _JSE_TRACKER_included
 #endinput
#endif
#define _JSE_TRACKER_included

#include <tf2>

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
	MarkNativeAsOptional("Jump.ID.get");
	MarkNativeAsOptional("Jump.ID.set");
	MarkNativeAsOptional("Jump.Number.get");
	MarkNativeAsOptional("Jump.Number.set");
	MarkNativeAsOptional("Jump.GetOrigin");
	MarkNativeAsOptional("Jump.SetOrigin");
	MarkNativeAsOptional("Jump.GetIdentifier");
	MarkNativeAsOptional("Jump.SetIdentifier");
	MarkNativeAsOptional("Jump.Instance");
	MarkNativeAsOptional("Jump.Destroy");

	MarkNativeAsOptional("ControlPoint.ID.get");
	MarkNativeAsOptional("ControlPoint.ID.set");
	MarkNativeAsOptional("ControlPoint.GetOrigin");
	MarkNativeAsOptional("ControlPoint.SetOrigin");
	MarkNativeAsOptional("ControlPoint.GetIdentifier");
	MarkNativeAsOptional("ControlPoint.SetIdentifier");
	MarkNativeAsOptional("ControlPoint.Instance");
	MarkNativeAsOptional("ControlPoint.Destroy");

	MarkNativeAsOptional("Course.ID.get");
	MarkNativeAsOptional("Course.ID.set");
	MarkNativeAsOptional("Course.Number.get");
	MarkNativeAsOptional("Course.Number.set");
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

enum struct Checkpoint {
	TFTeam iTeam;
	TFClassType iClass;
	Course iCourse;
	Jump iJump;
	ControlPoint iControlPoint;
	int iTimestamp;
}

const Course NULL_COURSE = view_as<Course>(0);
const Jump NULL_JUMP = view_as<Jump>(0);
const ControlPoint NULL_CONTROLPOINT = view_as<ControlPoint>(0);

forward void OnTrackerLoaded(ArrayList hCourses);

forward void OnCheckpointReached(int iClient, Course iCourse, Jump iJump, ControlPoint iControlPoint);

native bool IsTrackerLoaded();
native Database GetTrackerDatabase();
native int GetTrackerMapID();
native ArrayList GetTrackerCourses();

native bool GetPlayerNearestCheckpoint(int iClient, Course &iCourse, Jump &iJump, ControlPoint &iControlPoint, int &iTimestamp=0);
native bool GetPlayerNewestCheckpoint(int iClient, Course &iCourse, Jump &iJump, ControlPoint &iControlPoint, int &iTimestamp=0, TFTeam iTeam=TFTeam_Unassigned, TFClassType iClass=TFClass_Unknown);
native bool GetPlayerLastCheckpoint(int iClient, Course &iCourse, Jump &iJump, ControlPoint &iControlPoint, int &iTimestamp=0, TFTeam &iTeam, TFClassType &iClass);

native ArrayList GetPlayerProgress(int iClient);
native void ResetPlayerProgress(int iClient);
