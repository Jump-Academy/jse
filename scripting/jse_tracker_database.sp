Database g_hDatabase;

// Database callbacks

public void DB_Callback_Connect(Database hDatabase, char[] sError, any aData) {
	if (hDatabase == null) {
		LogError("Cannot connect to database: %s", sError);

		CreateTimer(30.0, Timer_Reconnect);
		return;
	}

	g_hDatabase = hDatabase;
	g_hDatabase.SetCharset("utf8mb4");

	DB_CreateTables();

	Call_StartForward(g_hTrackerDBConnectedForward);
	Call_PushCell(g_hDatabase);
	Call_Finish();
}

public void DB_Callback_CreateTable_Txn_Success(Database hDatabase, any aData, int iNumQueries, DBResultSet[] hResults, any[] aQueryData) {
	DB_AddMap();
}

public void DB_Callback_CreateTable_Txn_Failure(Database hDatabase, any aData, int iNumQueries, const char[] sError, int iFailIndex, any[] aQueryData) {
	SetFailState("Database error while creating tables: %s", sError);
}

public void DB_Callback_AddMap(Database hDatabase, DBResultSet hResultSet, char[] sError, any aData) {
	if (hResultSet == null) {
		LogError("Database error while adding map: %s", sError);
		return;
	}

	if (hResultSet.InsertId) {
		g_iMapID = hResultSet.InsertId;
		FetchMapData();
	} else {
		DB_LookupMapID();
	}
}

public void DB_Callback_LoadMapData(Database hDatabase, DBResultSet hResultSet, char[] sError, any aData) {
	if (hResultSet == null) {
		LogError("Database error while looking up map data: %s", sError);
		return;
	}

	if (!hResultSet.RowCount) {
		char sMapName[32];
		GetCurrentMap(sMapName, sizeof(sMapName));

		LogMessage("Found no courses for map %s", sMapName);
		return;
	}

	Transaction hTxn = new Transaction();

	char sQuery[1024];

	while (hResultSet.FetchRow()) {
		Course iCourse = Course.Instance();

		int iCourseID = hResultSet.FetchInt(0);
		iCourse.iID = iCourseID;

		int iCourseNumber = hResultSet.FetchInt(1);
		iCourse.iNumber = iCourseNumber;

		char sCourseName[128];
		hResultSet.FetchString(2, sCourseName, sizeof(sCourseName));

		iCourse.SetName(sCourseName);

		hDatabase.Format(sQuery, sizeof(sQuery), "SELECT `id`, `identifier`, `x`, `y`, `z`, `a` FROM `jse_map_controlpoints` WHERE `course_id`=%d", iCourseID);
		hTxn.AddQuery(sQuery, iCourse);

		hDatabase.Format(sQuery, sizeof(sQuery), "SELECT `id`, `jump`, `identifier`, `x`, `y`, `z`, `a` FROM `jse_map_jumps` WHERE `course_id`=%d", iCourseID);
		hTxn.AddQuery(sQuery, iCourse);

		g_hCourses.Push(iCourse);

		if (iCourseNumber <= 0) {
			g_iBonusCourses++;
		} else {
			g_iNormalCourses++;
		}
	}

	g_hDatabase.Execute(hTxn, DB_Callback_LoadMapInfo_Txn_Success, DB_Callback_LoadMapInfo_Txn_Failure);
}

public void DB_Callback_LookupMapID(Database hDatabase, DBResultSet hResultSet, char[] sError, any aData) {
	if (hResultSet == null) {
		LogError("Database error while looking up map ID: %s", sError);
		return;
	}

	if (!hResultSet.FetchRow()) {
		LogError("Failed to find map ID: %s", sError);
		g_iMapID = -1;
		return;
	}

	g_iMapID = hResultSet.FetchInt(0);

	if (hResultSet.IsFieldNull(1)) {
		FetchMapData();
	} else {
		DB_LoadMapData();
	}
}

public void DB_Callback_AddMapInfo_Txn_Success(Database hDatabase, any aData, int iNumQueries, DBResultSet[] hResults, any[] aQueryData) {
	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

	LogMessage("Added new map info from repository for %s", sMapName);
	DB_LoadMapData();
}

public void DB_Callback_AddMapInfo_Txn_Failure(Database hDatabase, any aData, int iNumQueries, const char[] sError, int iFailIndex, any[] aQueryData) {
	LogError("Database error while adding info for course %d: %s", aQueryData[iFailIndex], sError);
}

public void DB_Callback_LoadMapInfo_Txn_Success(Database hDatabase, any aData, int iNumQueries, DBResultSet[] hResults, any[] aQueryData) {
	char sIdentifier[128];
	float fOrigin[3];
	float fAngles[3];

	for (int i=0; i<iNumQueries; i+=2) {
		DBResultSet hResultSet = hResults[i];

		if (!hResultSet.FetchRow()) {
			continue;
		}

		Course iCourse = view_as<Course>(aQueryData[i]);
		char sCourseName[128];
		iCourse.GetName(sCourseName, sizeof(sCourseName));

		ControlPoint iControlPoint = ControlPoint.Instance();
		iControlPoint.iID = hResultSet.FetchInt(0);

		iCourse.iControlPoint = iControlPoint;

		if (hResults[i].IsFieldNull(1)) {
			fOrigin[0] = float(hResultSet.FetchInt(2));
			fOrigin[1] = float(hResultSet.FetchInt(3));
			fOrigin[2] = float(hResultSet.FetchInt(4));

			iControlPoint.SetOrigin(fOrigin);
			iControlPoint.fAngle = float(hResultSet.FetchInt(5));
		} else {
			hResultSet.FetchString(1, sIdentifier, sizeof(sIdentifier));
			iControlPoint.SetIdentifier(sIdentifier);

			int iEntity = Entity_FindByName(sIdentifier, "team_control_point");
			if (iEntity != INVALID_ENT_REFERENCE) {
				Entity_GetAbsOrigin(iEntity, fOrigin);
				Entity_GetAbsAngles(iEntity, fAngles);
				fOrigin[2] += 10.0; // In case buried in ground
				iControlPoint.SetOrigin(fOrigin);
				iControlPoint.fAngle = fAngles[1];
			}
		}
	}

	for (int i=1; i<iNumQueries; i+=2) {
		Course iCourse = view_as<Course>(aQueryData[i]);
		char sCourseName[128];
		iCourse.GetName(sCourseName, sizeof(sCourseName));

		ArrayList hJumps = iCourse.hJumps;
		DBResultSet hResultSet = hResults[i];

		while (hResultSet.FetchRow()) {
			Jump iJump = Jump.Instance();
			hJumps.Push(iJump);

			iJump.iID = hResultSet.FetchInt(0);
			iJump.iNumber = hResultSet.FetchInt(1);

			if (hResults[i].IsFieldNull(2)) {
				fOrigin[0] = hResultSet.FetchFloat(3);
				fOrigin[1] = hResultSet.FetchFloat(4);
				fOrigin[2] = hResultSet.FetchFloat(5);

				iJump.SetOrigin(fOrigin);
				iJump.fAngle = hResultSet.FetchFloat(6);
			} else {
				hResultSet.FetchString(2, sIdentifier, sizeof(sIdentifier));
				iJump.SetIdentifier(sIdentifier);

				int iEntity = Entity_FindByName(sIdentifier, "info_*");
				if (iEntity != INVALID_ENT_REFERENCE) {
					Entity_GetAbsOrigin(iEntity, fOrigin);
					Entity_GetAbsAngles(iEntity, fAngles);
					fOrigin[2] += 10.0; // In case buried in ground
					iJump.SetOrigin(fOrigin);
					iJump.fAngle = fAngles[1];
				}
			}
		}
	}

	g_bLoaded = true;

	SetupCheckpointCache();

	Call_StartForward(g_hTrackerLoadedForward);
	Call_PushCell(g_hCourses);
	Call_Finish();

	if (g_bPersist) {
		// Late load
		for (int i=1; i<=MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i)) {
				DB_LoadProgress(i);
			}
		}
	}
}

public void DB_Callback_LoadMapInfo_Txn_Failure(Database hDatabase, any aData, int iNumQueries, const char[] sError, int iFailIndex, any[] aQueryData) {
	Course iCourse = view_as<Course>(aQueryData[iFailIndex]);
	LogError("Database error while loading info for course %d: %s", iCourse.iNumber, sError);
}

public void DB_Callback_BackupProgress_Txn_Success(Database hDatabase, any aData, int iNumQueries, DBResultSet[] hResults, any[] aQueryData) {
	for (int i=0; i<iNumQueries; i++) {
		int iClient = GetClientFromSerial(aQueryData[i]);
		if (iClient) {
			g_iLastBackupTime[iClient] = aData;
		}
	}
}

public void DB_Callback_BackupProgress_Txn_Failure(Database hDatabase, any aData, int iNumQueries, const char[] sError, int iFailIndex, any[] aQueryData) {
	int iClient;
	if (iFailIndex == -1 || !(iClient = GetClientFromSerial(aQueryData[iFailIndex]))) {
		LogError("Database error while backing up progress: %s", sError);
	} else {
		LogError("Database error while backing up progress for %N: %s", iClient, sError);
	}
}

public void DB_Callback_GetProgress(Database hDatabase, DBResultSet hResultSet, char[] sError, any aData) {
	char sMapName[32];

	DataPack hDataPack = view_as<DataPack>(aData);
	hDataPack.Reset();

	int iClient = GetClientFromSerial(hDataPack.ReadCell());
	ArrayList hResult = hDataPack.ReadCell();
	hDataPack.ReadString(sMapName, sizeof(sMapName));
	Function pCallback = hDataPack.ReadFunction(); // ProgressLookup
	aData = hDataPack.ReadCell();

	delete hDataPack;

	if (!iClient) {
		return;
	}

	if (hResultSet == null) {
		LogError("Database error while getting progress for player %N: %s", iClient, sError);
		return;
	}

	StringMap hCourseNames = new StringMap();
	StringMap hCourseLengths = new StringMap();

	Checkpoint eCheckpoint;

	while (hResultSet.FetchRow()) {
		int iTeam = hResultSet.FetchInt(0);
		int iClass = hResultSet.FetchInt(1);

		int iCourseNumber = hResultSet.FetchInt(2);

		char sCourseName[128];
		hResultSet.FetchString(3, sCourseName, sizeof(sCourseName));

		int iJumpNumber = hResultSet.FetchInt(4);
		int iTotalJumps = hResultSet.FetchInt(5);

		bool bControlPoint = hResultSet.FetchInt(6) > 0;
		int iTimestamp = hResultSet.FetchInt(7);

		eCheckpoint.Init(iCourseNumber, iJumpNumber, bControlPoint, view_as<TFTeam>(iTeam), view_as<TFClassType>(iClass));
		eCheckpoint.iUnlockTime = iTimestamp;

		hResult.PushArray(eCheckpoint);

		char sKey[8];
		IntToString(iCourseNumber, sKey, sizeof(sKey));

		hCourseNames.SetString(sKey, sCourseName);
		hCourseLengths.SetValue(sKey, iTotalJumps);
	}

	Call_StartFunction(null, pCallback);
	Call_PushCell(iClient);
	Call_PushCell(hResult);
	Call_PushCell(hResultSet.RowCount);
	Call_PushString(sMapName);
	Call_PushCell(hCourseNames);
	Call_PushCell(hCourseLengths);
	Call_PushCell(aData);
	Call_Finish();

	delete hCourseNames;
	delete hCourseLengths;
}

public void DB_Callback_LoadProgress(Database hDatabase, DBResultSet hResultSet, char[] sError, any aData) {
	int iClient = GetClientFromSerial(aData);
	if (!iClient) {
		return;
	}

	if (hResultSet == null) {
		LogError("Database error while loading progress for player %N: %s", iClient, sError);
		return;
	}

	ArrayList hProgress = g_hProgress[iClient];
	Checkpoint eCheckpoint;

	while (hResultSet.FetchRow()) {
		int iTeam = hResultSet.FetchInt(0);
		int iClass = hResultSet.FetchInt(1);

		int iCourseNumber = hResultSet.FetchInt(2);
		int iJumpNumber = hResultSet.FetchInt(3);

		bool bControlPoint = hResultSet.FetchInt(4) > 0;
		int iTimestamp = hResultSet.FetchInt(5);

		eCheckpoint.Init(iCourseNumber, iJumpNumber, bControlPoint, view_as<TFTeam>(iTeam), view_as<TFClassType>(iClass));
		eCheckpoint.iUnlockTime = iTimestamp;

		hProgress.PushArray(eCheckpoint);
	}

	//SortADTArray(hProgress, Sort_Ascending, Sort_Integer);

	g_iLastBackupTime[iClient] = GetTime();

	Call_StartForward(g_hProgressLoadedForward);
	Call_PushCell(iClient);
	Call_Finish();
}

public void DB_Callback_DeleteProgress_Txn_Success(Database hDatabase, any aData, int iNumQueries, DBResultSet[] hResults, any[] aQueryData) {
}

public void DB_Callback_DeleteProgress_Txn_Failure(Database hDatabase, any aData, int iNumQueries, const char[] sError, int iFailIndex, any[] aQueryData) {
	int iClient;
	if (iFailIndex == -1 || !(iClient = GetClientFromSerial(aQueryData[iFailIndex]))) {
		LogError("Database error while deleting progress: %s", sError);
	} else {
		LogError("Database error while deleting progress for %N: %s", iClient, sError);
	}
}

// Database helpers

void DB_Connect() {
	Database.Connect(DB_Callback_Connect, "jse");
}

void DB_CreateTables() {
	Transaction hTxn = new Transaction();

	hTxn.AddQuery( \
		"CREATE TABLE IF NOT EXISTS `jse_maps`("
	...		"`id` INT AUTO_INCREMENT,"
	...		"`filename` VARCHAR(256),"
	...		"`lastupdate` DATETIME DEFAULT NULL,"
	...		"PRIMARY KEY(`id`),"
	... 	"UNIQUE(`filename`)"
	... ") ENGINE=INNODB");

	hTxn.AddQuery( \
		"CREATE TABLE IF NOT EXISTS `jse_map_courses`("
	...		"`id` INT AUTO_INCREMENT,"
	...		"`map_id` INT NOT NULL,"
	...		"`course` INT NOT NULL,"
	...		"`name` VARCHAR(128),"
	...		"PRIMARY KEY(`id`),"
	... 	"UNIQUE(`map_id`, `course`),"
	...		"CONSTRAINT `fk_course_map` FOREIGN KEY(`map_id`)"
	...		"REFERENCES `jse_maps`(`id`) ON DELETE CASCADE ON UPDATE CASCADE"
	... ") ENGINE=INNODB");

	hTxn.AddQuery( \
		"CREATE TABLE IF NOT EXISTS `jse_map_jumps`("
	...		"`id` INT AUTO_INCREMENT,"
	...		"`map_id` INT NOT NULL,"
	...		"`course_id` INT NOT NULL,"
	...		"`jump` INT NOT NULL,"
	...		"`identifier` VARCHAR(128),"
	...		"`x` INT,"
	...		"`y` INT,"
	...		"`z` INT,"
	...		"`a` INT,"
	...		"PRIMARY KEY(`id`),"
	... 	"UNIQUE(`map_id`, `course_id`, `jump`),"
	...		"CONSTRAINT `fk_jump_map` FOREIGN KEY(`map_id`)"
	...		"REFERENCES `jse_maps`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,"
	...		"CONSTRAINT `fk_jump_course` FOREIGN KEY(`course_id`)"
	...		"REFERENCES `jse_map_courses`(`id`) ON DELETE CASCADE ON UPDATE CASCADE"
	... ") ENGINE=INNODB");

	hTxn.AddQuery( \
		"CREATE TABLE IF NOT EXISTS `jse_map_controlpoints`("
	...		"`id` INT AUTO_INCREMENT,"
	...		"`map_id` INT NOT NULL,"
	...		"`course_id` INT NOT NULL,"
	...		"`identifier` VARCHAR(128),"
	...		"`x` INT,"
	...		"`y` INT,"
	...		"`z` INT,"
	...		"`a` INT,"
	...		"PRIMARY KEY(`id`),"
	... 	"UNIQUE(`map_id`, `course_id`),"
	...		"CONSTRAINT `fk_controlpoint_map` FOREIGN KEY(`map_id`)"
	...		"REFERENCES `jse_maps`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,"
	...		"CONSTRAINT `fk_controlpoint_course` FOREIGN KEY(`course_id`)"
	...		"REFERENCES `jse_map_courses`(`id`) ON DELETE CASCADE ON UPDATE CASCADE"
	... ") ENGINE=INNODB");

	hTxn.AddQuery( \
		"CREATE TABLE IF NOT EXISTS `jse_progress_jumps`("
	...		"`id` INT AUTO_INCREMENT,"
	...		"`auth` BIGINT NOT NULL,"
	...		"`map_id` INT NOT NULL,"
	...		"`team` INT NOT NULL,"
	...		"`class` INT NOT NULL,"
	...		"`course_id` INT NOT NULL,"
	...		"`jump_id` INT NOT NULL,"
	...		"`timestamp` DATETIME ON UPDATE CURRENT_TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,"
	...		"PRIMARY KEY(`id`),"
	...		"INDEX (`timestamp`),"
	... 	"UNIQUE(`auth`, `map_id`, `team`, `class`, `course_id`, `jump_id`),"
	...		"CONSTRAINT `fk_progress_jump_map` FOREIGN KEY(`map_id`)"
	...		"REFERENCES `jse_maps`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,"
	...		"CONSTRAINT `fk_progress_jump_course` FOREIGN KEY(`course_id`)"
	...		"REFERENCES `jse_map_courses`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,"
	...		"CONSTRAINT `fk_progress_jump_jump` FOREIGN KEY(`jump_id`)"
	...		"REFERENCES `jse_map_jumps`(`id`) ON DELETE CASCADE ON UPDATE CASCADE"
	... ") ENGINE=INNODB");

	hTxn.AddQuery( \
		"CREATE TABLE IF NOT EXISTS `jse_progress_controlpoints`("
	...		"`id` INT AUTO_INCREMENT,"
	...		"`auth` BIGINT NOT NULL,"
	...		"`map_id` INT NOT NULL,"
	...		"`team` INT NOT NULL,"
	...		"`class` INT NOT NULL,"
	...		"`course_id` INT NOT NULL,"
	...		"`controlpoint_id` INT NOT NULL,"
	...		"`timestamp` DATETIME ON UPDATE CURRENT_TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,"
	...		"PRIMARY KEY(`id`),"
	...		"INDEX (`timestamp`),"
	... 	"UNIQUE(`auth`, `map_id`, `team`, `class`, `course_id`, `controlpoint_id`),"
	...		"CONSTRAINT `fk_progress_controlpoint_map` FOREIGN KEY(`map_id`)"
	...		"REFERENCES `jse_maps`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,"
	...		"CONSTRAINT `fk_progress_controlpoint_course` FOREIGN KEY(`course_id`)"
	...		"REFERENCES `jse_map_courses`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,"
	...		"CONSTRAINT `fk_progress_controlpoint_controlpoint` FOREIGN KEY(`controlpoint_id`)"
	...		"REFERENCES `jse_map_controlpoints`(`id`) ON DELETE CASCADE ON UPDATE CASCADE"
	... ") ENGINE=INNODB");

	g_hDatabase.Execute(hTxn, DB_Callback_CreateTable_Txn_Success, DB_Callback_CreateTable_Txn_Failure, 0, DBPrio_High);
}

void DB_AddMap() {
	if (g_hDatabase == null) {
		return;
	}

	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

	char sQuery[1024];
	g_hDatabase.Format(sQuery, sizeof(sQuery), \
		"INSERT IGNORE INTO `jse_maps`(`filename`)"
	...	"VALUES ('%s')", sMapName);

	g_hDatabase.Query(DB_Callback_AddMap, sQuery, 0, DBPrio_High);
}

void DB_AddCourse(Transaction hTxn, int iCourse, char[] sName) {
	char sQuery[1024];

	if (sName[0]) {
		g_hDatabase.Format(sQuery, sizeof(sQuery), \
			"INSERT IGNORE INTO `jse_map_courses`(`map_id`, `course`, `name`)"
		...	"VALUES (%d, %d, '%s')", g_iMapID, iCourse, sName);
	} else {
		g_hDatabase.Format(sQuery, sizeof(sQuery), \
			"INSERT IGNORE INTO `jse_map_courses`(`map_id`, `course`)"
		...	"VALUES (%d, %d)", g_iMapID, iCourse);
	}

	hTxn.AddQuery(sQuery, iCourse);
}

void DB_AddJump(Transaction hTxn, int iCourse, int iJump, char[] sIdentifier, int iX, int iY, int iZ, int iA) {
	char sQuery[1024];

	if (sIdentifier[0]) {
		g_hDatabase.Format(sQuery, sizeof(sQuery), \
			"INSERT IGNORE INTO `jse_map_jumps`(`map_id`, `course_id`, `jump`, `identifier`)"
		...	"SELECT %d, `id`, %d, '%s' FROM `jse_map_courses` WHERE `map_id`=%d AND `course`=%d", g_iMapID, iJump, sIdentifier, g_iMapID, iCourse);
	} else {
		g_hDatabase.Format(sQuery, sizeof(sQuery), \
			"INSERT IGNORE INTO `jse_map_jumps`(`map_id`, `course_id`, `jump`, `x`, `y`, `z`, `a`)"
		...	"SELECT %d, `id`, %d, %d, %d, %d, %d FROM `jse_map_courses` WHERE `map_id`=%d AND `course`=%d", g_iMapID, iJump, iX, iY, iZ, iA, g_iMapID, iCourse);
	}

	hTxn.AddQuery(sQuery, iCourse);
}

void DB_AddControlPoint(Transaction hTxn, int iCourse, char[] sIdentifier, int iX, int iY, int iZ, int iA) {
	char sQuery[1024];

	if (sIdentifier[0]) {
		g_hDatabase.Format(sQuery, sizeof(sQuery), \
			"INSERT IGNORE INTO `jse_map_controlpoints`(`map_id`, `course_id`, `identifier`)"
		...	"SELECT %d, `id`, '%s' FROM `jse_map_courses` WHERE `map_id`=%d AND `course`=%d", g_iMapID, sIdentifier, g_iMapID, iCourse);
	} else {
		g_hDatabase.Format(sQuery, sizeof(sQuery), \
			"INSERT IGNORE INTO `jse_map_controlpoints`(`map_id`, `course_id`, `x`, `y`, `z`, `a`)"
		...	"SELECT %d, `id`, %d, %d, %d, %d FROM `jse_map_courses` WHERE `map_id`=%d AND `course`=%d", g_iMapID, iX, iY, iZ, iA, g_iMapID, iCourse);
	}

	hTxn.AddQuery(sQuery, iCourse);
}

void DB_ExecuteAddMapInfoTX(Transaction hTxn) {
	char sQuery[1024];
	g_hDatabase.Format(sQuery, sizeof(sQuery), "UPDATE `jse_maps` SET `lastupdate`=UTC_TIMESTAMP WHERE `id`=%d", g_iMapID);
	hTxn.AddQuery(sQuery);
	g_hDatabase.Execute(hTxn, DB_Callback_AddMapInfo_Txn_Success, DB_Callback_AddMapInfo_Txn_Failure, 0, DBPrio_High);
}

void DB_LoadMapData() {
	char sQuery[1024];
	g_hDatabase.Format(sQuery, sizeof(sQuery), "SELECT `id`, `course`, `name` FROM `jse_map_courses` WHERE `map_id`=%d", g_iMapID);
	g_hDatabase.Query(DB_Callback_LoadMapData, sQuery, 0, DBPrio_High);
}

void DB_LookupMapID() {
	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

	char sQuery[1024];
	g_hDatabase.Format(sQuery, sizeof(sQuery), "SELECT `id`, `lastupdate` FROM `jse_maps` WHERE `filename`='%s'", sMapName);
	g_hDatabase.Query(DB_Callback_LookupMapID, sQuery, 0, DBPrio_High);
}

// void DB_GetProgress(int iClient, ArrayList hResult, TFTeam iTeam, TFClassType iClass, char[] sMapName, ProgressLookup pCallback, any aData) {
void DB_GetProgress(int iClient, ArrayList hResult, TFTeam iTeam, TFClassType iClass, char[] sMapName, Function pCallback, any aData) {
	char sAuthID[64];
	if (!GetClientAuthId(iClient, AuthId_SteamID64, sAuthID, sizeof(sAuthID))) {
		LogError("Failed to get progress due to bad auth ID: %L", iClient);
		return;
	}

	char sQueryMapID[256];

	if (sMapName[0]) {
		if (sMapName[0] != '*') {
			g_hDatabase.Format(sQueryMapID, sizeof(sQueryMapID), "`p`.`map_id`=(SELECT `id` FROM `jse_maps` WHERE `filename`='%s')", sMapName);
		}
	} else {
		FormatEx(sQueryMapID, sizeof(sQueryMapID), "`p`.`map_id`=%d", g_iMapID);
	}

	char sQueryTeam[32];
	if (iTeam) {
		FormatEx(sQueryTeam, sizeof(sQueryTeam), "AND `p`.`team`=%d", iTeam);
	}

	char sQueryClass[32];
	if (iClass) {
		FormatEx(sQueryClass, sizeof(sQueryClass), "AND `p`.`class`=%d", iClass);
	}

	char sQuery[1024];
	FormatEx(sQuery, sizeof(sQuery), \
		"SELECT `team`, `class`, `course`, `mc`.`name` AS `course_name`, `jump`, (SELECT COUNT(*) FROM `jse_map_jumps` WHERE `course_id`=`mc`.`id`) AS `total_jumps`, `controlpoint_id`, `timestamp`"
	...	"FROM"
	...	"("
	...	"	SELECT `map_id`, `team`, `class`, `course_id`, NULL AS `jump_id`, `controlpoint_id`, `timestamp` FROM `jse_progress_controlpoints`"
	...	"	WHERE `auth`=%s"
	...	"	UNION ALL"
	...	"	SELECT `map_id`, `team`, `class`, `course_id`, `jump_id`, NULL AS `controlpoint_id`, `timestamp` FROM `jse_progress_jumps`"
	...	"	WHERE `auth`=%s"
	...	") `p`"
	...	"LEFT JOIN `jse_map_courses` AS `mc` ON `p`.`course_id`=`mc`.`id`"
	...	"LEFT JOIN `jse_map_jumps` AS `mj` ON `p`.`jump_id`=`mj`.`id`"
	... "WHERE %s %s %s",
		sAuthID, sAuthID, sQueryMapID, sQueryTeam, sQueryClass);

	DataPack hDataPack = new DataPack();
	hDataPack.WriteCell(GetClientSerial(iClient));
	hDataPack.WriteCell(hResult);

	if (sMapName[0]) {
		hDataPack.WriteString(sMapName);
	} else {
		char sCurrentMapName[32];
		GetCurrentMap(sCurrentMapName, sizeof(sCurrentMapName));

		hDataPack.WriteString(sCurrentMapName);
	}

	hDataPack.WriteFunction(pCallback);
	hDataPack.WriteCell(aData);

	g_hDatabase.Query(DB_Callback_GetProgress, sQuery, hDataPack);
}

void DB_LoadProgress(int iClient) {
	if (!g_bPersist) {
		return;
	}

	char sAuthID[64];
	if (!GetClientAuthId(iClient, AuthId_SteamID64, sAuthID, sizeof(sAuthID))) {
		LogError("Failed to load progress due to bad auth ID: %L", iClient);
		return;
	}

	Call_StartForward(g_hProgressLoadForward);
	Call_PushCell(iClient);

	Action iReturn;
	if (Call_Finish(iReturn) == SP_ERROR_NONE && iReturn != Plugin_Continue) {
		return;
	}

	char sQuery[1024];
	g_hDatabase.Format(sQuery, sizeof(sQuery), \
		"SELECT `team`, `class`, `course`, `jump`, `controlpoint_id`, `timestamp`"
	...	"FROM"
	...	"("
	...	"	SELECT `team`, `class`, `course_id`, NULL AS `jump_id`, `controlpoint_id`, `timestamp` FROM `jse_progress_controlpoints`"
	...	"	WHERE `auth`=%s AND `map_id`=%d"
	...	"	UNION ALL"
	...	"	SELECT `team`, `class`, `course_id`, `jump_id`, NULL AS `controlpoint_id`, `timestamp` FROM `jse_progress_jumps`"
	...	"	WHERE `auth`=%s AND `map_id`=%d"
	...	") `p`"
	...	"LEFT JOIN `jse_map_courses` AS `mc` ON `p`.`course_id`=`mc`.`id`"
	...	"LEFT JOIN `jse_map_jumps` AS `mj` ON `p`.`jump_id`=`mj`.`id`",
		sAuthID, g_iMapID, sAuthID, g_iMapID);

	g_hDatabase.Query(DB_Callback_LoadProgress, sQuery, GetClientSerial(iClient));
}

void DB_BackupProgress(int iClient=0) {
	if (!g_bPersist || iClient && IsFakeClient(iClient)) {
		return;
	}

	Transaction hTxn = new Transaction();
	int iTotalQueries = 0;

	if (iClient) {
		iTotalQueries = DB_BackupProgress_Client(hTxn, iClient);
	} else {
		for (int i=1; i<=MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i)) {
				iTotalQueries += DB_BackupProgress_Client(hTxn, i);
			}
		}
	}

	if (iTotalQueries) {
		g_hDatabase.Execute(hTxn, DB_Callback_BackupProgress_Txn_Success, DB_Callback_BackupProgress_Txn_Failure, GetTime(), DBPrio_Low);
	} else {
		delete hTxn;
	}
}

int DB_BackupProgress_Client(Transaction hTxn, int iClient) {
	char sAuthID[64];
	if (!GetClientAuthId(iClient, AuthId_SteamID64, sAuthID, sizeof(sAuthID))) {
		LogError("Failed to back up progress due to bad auth ID: %L", iClient);
		return 0;
	}

	ArrayList hProgress = g_hProgress[iClient];
	int iLastBackupTime = g_iLastBackupTime[iClient];

	Checkpoint eCheckpoint;

	char sQuery[1024];
	int iTotalQueries = 0;

	for (int i=0; i<hProgress.Length; i++) {
		hProgress.GetArray(i, eCheckpoint);

		if (eCheckpoint.iUnlockTime <= iLastBackupTime) {
			continue;
		}

		Course iCourse = ResolveCourseNumber(eCheckpoint.GetCourseNumber());

		if (eCheckpoint.IsControlPoint()) {
			ControlPoint iControlPoint = iCourse.iControlPoint;

			g_hDatabase.Format(sQuery, sizeof(sQuery), \
				"INSERT IGNORE INTO `jse_progress_controlpoints`(`auth`, `map_id`, `team`, `class`, `course_id`, `controlpoint_id`)"
			...	"VALUES (%s, %d, %d, %d, %d, %d)",
			sAuthID, GetTrackerMapID(), eCheckpoint.GetTeam(), eCheckpoint.GetClass(), iCourse.iID, iControlPoint.iID);
		} else {
			Jump iJump = ResolveJumpNumber(iCourse, eCheckpoint.GetJumpNumber());

			g_hDatabase.Format(sQuery, sizeof(sQuery), \
				"INSERT IGNORE INTO `jse_progress_jumps`(`auth`, `map_id`, `team`, `class`, `course_id`, `jump_id`)"
			...	"VALUES (%s, %d, %d, %d, %d, %d)",
			sAuthID, GetTrackerMapID(), eCheckpoint.GetTeam(), eCheckpoint.GetClass(), iCourse.iID, iJump.iID);
		}

		hTxn.AddQuery(sQuery, GetClientSerial(iClient));
		iTotalQueries++;
	}

	return iTotalQueries;
}

void DB_DeleteProgress(int iClient, TFTeam iTeam, TFClassType iClass, char[] sMapName) {
	char sAuthID[64];
	if (!GetClientAuthId(iClient, AuthId_SteamID64, sAuthID, sizeof(sAuthID))) {
		LogError("Failed to delete progress due to bad auth ID: %L", iClient);
		return;
	}

	char sQuery[1024];

	Transaction hTxn = new Transaction();

	char sQueryMapID[256];

	if (sMapName[0]) {
		if (sMapName[0] != '*') {
			g_hDatabase.Format(sQueryMapID, sizeof(sQueryMapID), "AND `map_id`=(SELECT `id` FROM `jse_maps` WHERE `filename`='%s')", sMapName);
		}
	} else {
		FormatEx(sQueryMapID, sizeof(sQueryMapID), "AND `map_id`=%d", g_iMapID);
	}

	char sQueryTeam[32];
	if (iTeam) {
		FormatEx(sQueryTeam, sizeof(sQueryTeam), "AND `team`=%d", iTeam);
	}

	char sQueryClass[32];
	if (iClass) {
		FormatEx(sQueryClass, sizeof(sQueryClass), "AND `class`=%d", iClass);
	}

	FormatEx(sQuery, sizeof(sQuery), \
		"DELETE FROM `jse_progress_jumps` WHERE `auth`=%s %s %s %s",
		sAuthID, sQueryMapID, sQueryTeam, sQueryClass);

	hTxn.AddQuery(sQuery, GetClientSerial(iClient));

	FormatEx(sQuery, sizeof(sQuery), \
		"DELETE FROM `jse_progress_controlpoints` WHERE `auth`=%s %s %s %s",
		sAuthID, sQueryMapID, sQueryTeam, sQueryClass);

	hTxn.AddQuery(sQuery, GetClientSerial(iClient));

	g_hDatabase.Execute(hTxn, DB_Callback_DeleteProgress_Txn_Success, DB_Callback_DeleteProgress_Txn_Failure);
}

// Timers

public Action Timer_Reconnect(Handle hTimer) {
	DB_Connect();

	return Plugin_Handled;
}
