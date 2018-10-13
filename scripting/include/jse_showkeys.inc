#if defined _JSE_SHOWKEYS_included
	#endinput
#endif
#define _JSE_SHOWKEYS_included

public SharedPlugin __pl_jse_showkeys = 
{
	name = "jse_showkeys",
	file = "jse_showkeys.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};


#if !defined REQUIRE_PLUGIN
public void __pl_jse_showkeys_SetNTVOptional()
{
	MarkNativeAsOptional("ForceShowKeys");
	MarkNativeAsOptional("ResetShowKeys");
}
#endif

native void ForceShowKeys(int iClient, int iTarget);
native void ResetShowKeys(int iClient);
