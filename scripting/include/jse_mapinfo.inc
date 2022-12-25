#if defined _JSE_MAPINFO_included
	#endinput
#endif
#define _JSE_MAPINFO_included

public SharedPlugin __pl_jse_mapinfo = 
{
	name = "jse_mapinfo",
	file = "jse_mapinfo.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_jse_mapinfo_SetNTVOptional()
{
	MarkNativeAsOptional("MapInfo_CurrentMap");
	MarkNativeAsOptional("MapInfo_LookupAll");
	MarkNativeAsOptional("MapInfo_LookupAll");
}
#endif

#include <tf2>
#include <ripext>

native void MapInfo_CurrentMap(MapInfoResponse fnCallback, any aData);
native void MapInfo_Lookup(MapInfoResponse fnCallback, any aData, bool bExtendedTiers, bool bExactMatch=false, const char[] sSearchTerm=NULL_STRING, const char[] sAuthorAuthID=NULL_STRING, const char[] sAuthorName=NULL_STRING, TFClassType iClassType=TFClass_Unknown, int iIntendedTier=0, int iTierS=0, int iTierD=0);
native void MapInfo_LookupAll(MapInfoResponse fnCallback, any aData, bool bExtendedTiers, bool bExactMatch=false, const char[] sSearchTerms=NULL_STRING, const char[] sSplit, const char[] sAuthorAuthID=NULL_STRING, const char[] sAuthorName=NULL_STRING, TFClassType iClassType=TFClass_Unknown, int iIntendedTier=0, int iTierS=0, int iTierD=0);

typedef MapInfoResponse = function void (any aData, JSONArray hMapInfoList);
