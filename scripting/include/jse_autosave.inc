#if defined _JSE_AUTOSAVE_included
 #endinput
#endif
#define _JSE_AUTOSAVE_included

#include <tf2>
#include <jse_tracker>

public SharedPlugin __pl_jse_autosave =
{
	name = "jse_autosave",
	file = "jse_autosave.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

forward Action OnAutosavePreLoad(int iClient);
forward Action OnAutosaveLoad(int iClient, TFTeam iTeam, TFClassType iClass, int iCourseNumber, int iJumpNumber, bool bControlPoint);
