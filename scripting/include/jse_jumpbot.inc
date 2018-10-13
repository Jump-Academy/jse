/*
**
*/
#if defined _JSE_JUMPBOT_included
 #endinput
#endif
#define _JSE_JUMPBOT_included

#include <sourcemod>

public SharedPlugin __pl_jse_jumpbot = 
{
	name = "jse_jumpbot",
	file = "jse_jumpbot.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};


#if !defined REQUIRE_PLUGIN
public void __pl_jse_jumpbot_SetNTVOptional()
{
	MarkNativeAsOptional("JSE_JB_Shutdown");
}
#endif

native void JSE_JB_Shutdown();
