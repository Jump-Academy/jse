#if defined _JSE_CORE_included
	#endinput
#endif
#define _JSE_CORE_included

public SharedPlugin __pl_jse_core = 
{
	name = "jse_core",
	file = "jse_core.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};


#if !defined REQUIRE_PLUGIN
public void __pl_jse_core_SetNTVOptional()
{
	MarkNativeAsOptional("GetBlockEquip");
	MarkNativeAsOptional("GetBlockRegen");
	MarkNativeAsOptional("GetRegen");
	MarkNativeAsOptional("SetBlockEquip");
	MarkNativeAsOptional("SetBlockRegen");
	MarkNativeAsOptional("SetRegen");
	MarkNativeAsOptional("ClearControlPointCapture");
	MarkNativeAsOptional("ClearScore");
}
#endif

native bool GetBlockEquip(int iClient);
native bool GetBlockRegen(int iClient);
native bool GetRegen(int iClient);
native void SetBlockEquip(int iClient, bool bEnabled);
native void SetBlockRegen(int iClient, bool bEnabled);
native void SetRegen(int iClient, bool bEnabled);
native void ClearControlPointCapture(int iClient);
native void ClearScore(int iClient);

forward int OnCapPointCapture(int iClient, int iCapPointEntity, int iCapPointIndex, const char[] sCapPointName);

// Capture options
#define CAP_ABORT			(0)
#define CAP_SND_BROADCAST	(1<<0)
#define CAP_SND_CHEER		(1<<1)
#define CAP_EVENT			(1<<2)
#define CAP_NORMAL			(CAP_SND_BROADCAST | CAP_SND_CHEER | CAP_EVENT)
