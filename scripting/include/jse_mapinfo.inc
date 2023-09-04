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
	MarkNativeAsOptional("MapInfo_Lookup");
	MarkNativeAsOptional("MapInfo_LookupAll");
}
#endif

#include <tf2>
#include <ripext>

/**
 * Looks up information for the current map
 *
 * @param fnCallback		Callback.
 * @param aData				Data value to pass to the callback.
 */
native void MapInfo_CurrentMap(MapInfoResponse fnCallback, any aData);

/**
 * Looks up information for a map
 *
 * @param fnCallback		Callback.
 * @param aData				Data value to pass to the callback.
 * @param bExtendedTiers	Use extended tiers beyond T6, otherwise clamp lookups to T6.
 * @param bExactMatch		Use exact matching for the file name search term
 * @param sSearchTerm		File name to search for.
 * @param sAuthorAuthID		Map author SteamID64
 * @param sAuthorName		Map author name (partial or full)
 * @param iClassType		Map intended class
 * @param iIntendedTier		Map tier for intended class
 * @param iTierS			Map tier for soldier (regardless of intended class)
 * @param iTierD			Map tier for demoman (regardless of intended class)
 * @param bLayout			Include map layout details
 */
native void MapInfo_Lookup(MapInfoResponse fnCallback, any aData, bool bExtendedTiers, bool bExactMatch=false, const char[] sSearchTerm=NULL_STRING, const char[] sAuthorAuthID=NULL_STRING, const char[] sAuthorName=NULL_STRING, TFClassType iClassType=TFClass_Unknown, int iIntendedTier=0, int iTierS=0, int iTierD=0, bool bLayout=false);

/**
 * Looks up information for multiple maps
 * Caution:
 *		The maximum length for the entire URL per API call is 8k, which includes the filter
 *		parameters and concatenation of provided search terms.  If the inputted number of 
 *		maps is large but fewer results returned than expected despite map results returning
 *		when called individually, try reducing the number of maps per call in case the query
 *		string has been truncated.  Each lookup supports up to around 500 maps.
 *
 * @param fnCallback		Callback.
 * @param aData				Data value to pass to the callback.
 * @param bExtendedTiers	Use extended tiers beyond T6, otherwise clamp lookups to T6.
 * @param bExactMatch		Use exact matching for the file name search terms
 * @param sSearchTerms		File names to search for delimited a separator
 * @param sSplit			Separator used between file name search terms
 * @param sAuthorAuthID		Map author SteamID64
 * @param sAuthorName		Map author name (partial or full)
 * @param iClassType		Map intended class
 * @param iIntendedTier		Map tier for intended class
 * @param iTierS			Map tier for soldier (regardless of intended class)
 * @param iTierD			Map tier for demoman (regardless of intended class)
 * @param bLayout			Include map layout details
 */
native void MapInfo_LookupAll(MapInfoResponse fnCallback, any aData, bool bExtendedTiers, bool bExactMatch=false, const char[] sSearchTerms=NULL_STRING, const char[] sSplit, const char[] sAuthorAuthID=NULL_STRING, const char[] sAuthorName=NULL_STRING, TFClassType iClassType=TFClass_Unknown, int iIntendedTier=0, int iTierS=0, int iTierD=0, bool bLayout=false);

/**
 * Callback for receiving MapInfo query results
 *
 * @param aData				Data passed in original lookup call.
 * @param hMapInfoList		JSON list of maps and their corresponding info, or null on failure.
 * @param sError			Error string if there were an error.
 */
typedef MapInfoResponse = function void (any aData, JSONArray hMapInfoList, const char[] sError);
