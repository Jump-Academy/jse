#if defined _JSE_SNAPSHOT_included
 #endinput
#endif
#define _JSE_SNAPSHOT_included

#include <tf2>
#include <jse_tracker>

public SharedPlugin __pl_jse_snapshot = 
{
	name = "jse_snapshot",
	file = "jse_snapshot.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

forward Action OnSnapshotPreLoad(int iClient);
forward Action OnSnapshotLoad(int iClient, TFTeam &iTeam, TFClassType &iClass, Course &iCourse, Jump &iJump, ControlPoint &iControlPoint);
