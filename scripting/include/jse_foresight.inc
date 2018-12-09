#if defined _JSE_FORESIGHT_included
 #endinput
#endif
#define _JSE_FORESIGHT_included

#include <sourcemod>

public SharedPlugin __pl_jse_foresight = 
{
	name = "jse_foresight",
	file = "jse_foresight.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};


#if !defined REQUIRE_PLUGIN
public void __pl_jse_foresight_SetNTVOptional()
{
	MarkNativeAsOptional("FSCamera.Client.get");
	MarkNativeAsOptional("FSCamera.Client.set");
	MarkNativeAsOptional("FSCamera.Entity.get");
	MarkNativeAsOptional("FSCamera.Entity.set");
	MarkNativeAsOptional("FSCamera.ViewControl.get");
	MarkNativeAsOptional("FSCamera.ViewControl.set");
	MarkNativeAsOptional("FSCamera.StartTime.get");
	MarkNativeAsOptional("FSCamera.StartTime.set");
	MarkNativeAsOptional("FSCamera.Instance");
	MarkNativeAsOptional("FSCamera.Destroy");
}
#endif

methodmap FSCamera {
	property int Client {
		public native get();
		public native set(int iClient);
	}

	property int Entity {
		public native get();
		public native set(int iEntity);
	}

	property int ViewControl {
		public native get();
		public native set(int iViewControl);
	}

	property float StartTime {
		public native get();
		public native set(float fStartTime);
	}

	public static native FSCamera Instance();
	public static native void Destroy(FSCamera iCamera);
}
