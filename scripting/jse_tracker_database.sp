Database g_hDatabase;

// Database callbacks

public void DB_Callback_Connect(Handle hOwner, Handle hHandle, char[] sError, any aData) {
	if (hHandle == null) {
		LogError("Cannot connect to database: %s", sError);
		
		CreateTimer(30.0, Timer_Reconnect);
		return;
	}
	
	g_hDatabase = view_as<Database>(hHandle);
	g_hDatabase.SetCharset("utf8mb4");

	DB_CreateTables();
	DB_AddMap();
}

public void DB_Callback_CreateTable(Database hDatabase, DBResultSet hResultSet, char[] sError, any aData) {
	if (hResultSet == null) {
		SetFailState("Database error while creating table: %s", sError);
		return;
	}
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

		iCourse.iNumber = hResultSet.FetchInt(1);

		char sCourseName[128];
		hResultSet.FetchString(2, sCourseName, sizeof(sCourseName));

		iCourse.SetName(sCourseName);

		hDatabase.Format(sQuery, sizeof(sQuery), "SELECT `id`, `identifier`, `x`, `y`, `z` FROM `jse_map_controlpoints` WHERE `course_id`=%d", iCourseID);
		hTxn.AddQuery(sQuery, iCourse);

		hDatabase.Format(sQuery, sizeof(sQuery), "SELECT `id`, `jump`, `identifier`, `x`, `y`, `z` FROM `jse_map_jumps` WHERE `course_id`=%d", iCourseID);
		hTxn.AddQuery(sQuery, iCourse);

		g_hCourses.Push(iCourse);
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

		char sIdentifier[128];
		float fOrigin[3];

		if (hResults[i].IsFieldNull(1)) {
			fOrigin[0] = float(hResultSet.FetchInt(2));
			fOrigin[1] = float(hResultSet.FetchInt(3));
			fOrigin[2] = float(hResultSet.FetchInt(4));

			iControlPoint.SetOrigin(fOrigin);
		} else {
			hResultSet.FetchString(1, sIdentifier, sizeof(sIdentifier));
			iControlPoint.SetIdentifier(sIdentifier);

			int iEntity = Entity_FindByName(sIdentifier, "team_control_point");
			if (iEntity != INVALID_ENT_REFERENCE) {
				Entity_GetAbsOrigin(iEntity, fOrigin);
				fOrigin[2] += 10.0; // In case buried in ground
				iControlPoint.SetOrigin(fOrigin);
			}
		}
	}

	for (int i=1; i<iNumQueries; i+=2) {
		Course iCourse = view_as<Course>(aQueryData[i]);
		char sCourseName[128];
		iCourse.GetName(sCourseName, sizeof(sCourseName));

		ArrayList hJumps = iCourse.hJumps;
		DBResultSet hResultSet = hResults[i];

		char sIdentifier[128];
		float fOrigin[3];

		while (hResultSet.FetchRow()) {
			Jump iJump = Jump.Instance();
			hJumps.Push(iJump);

			iJump.iID = hResultSet.FetchInt(0);
			iJump.iNumber = hResultSet.FetchInt(1);

			if (hResults[i].IsFieldNull(2)) {
				fOrigin[0] = float(hResultSet.FetchInt(3));
				fOrigin[1] = float(hResultSet.FetchInt(4));
				fOrigin[2] = float(hResultSet.FetchInt(5));

				iJump.SetOrigin(fOrigin);
			} else {
				hResultSet.FetchString(2, sIdentifier, sizeof(sIdentifier));
				iJump.SetIdentifier(sIdentifier);

				int iEntity = Entity_FindByName(sIdentifier, "info_*");
				if (iEntity != INVALID_ENT_REFERENCE) {
					Entity_GetAbsOrigin(iEntity, fOrigin);
					fOrigin[2] += 10.0; // In case buried in ground
					iJump.SetOrigin(fOrigin);
				}
			}
		}
	}

	g_bLoaded = true;

	Call_StartForward(g_hTrackerLoadedForward);
	Call_PushCell(g_hCourses);
	Call_Finish();
}

public void DB_Callback_LoadMapInfo_Txn_Failure(Database hDatabase, any aData, int iNumQueries, const char[] sError, int iFailIndex, any[] aQueryData) {
	Course iCourse = view_as<Course>(aQueryData[iFailIndex]);
	LogError("Database error while loading info for course %d: %s", iCourse.iNumber, sError);
}

// Database helpers

void DB_Connect() {
	SQL_TConnect(DB_Callback_Connect, "jse");
}

void DB_CreateTables() {
	g_hDatabase.Query(DB_Callback_CreateTable, \
		"CREATE TABLE IF NOT EXISTS `jse_maps`("
	...		"`id` INT AUTO_INCREMENT,"
	...		"`filename` VARCHAR(256),"
	...		"`lastupdate` DATETIME DEFAULT NULL,"
	...		"PRIMARY KEY(`id`),"
	... 	"UNIQUE(`filename`)"
	... ") ENGINE=INNODB");

	g_hDatabase.Query(DB_Callback_CreateTable, \
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

	g_hDatabase.Query(DB_Callback_CreateTable, \
		"CREATE TABLE IF NOT EXISTS `jse_map_jumps`("
	...		"`id` INT AUTO_INCREMENT,"
	...		"`map_id` INT NOT NULL,"
	...		"`course_id` INT NOT NULL,"
	...		"`jump` INT NOT NULL,"
	...		"`identifier` VARCHAR(128),"
	...		"`x` FLOAT,"
	...		"`y` FLOAT,"
	...		"`z` FLOAT,"
	...		"PRIMARY KEY(`id`),"
	... 	"UNIQUE(`map_id`, `course_id`, `jump`),"
	...		"CONSTRAINT `fk_jump_map` FOREIGN KEY(`map_id`)"
	...		"REFERENCES `jse_maps`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,"
	...		"CONSTRAINT `fk_jump_course` FOREIGN KEY(`course_id`)"
	...		"REFERENCES `jse_map_courses`(`id`) ON DELETE CASCADE ON UPDATE CASCADE"
	... ") ENGINE=INNODB");

	g_hDatabase.Query(DB_Callback_CreateTable, \
		"CREATE TABLE IF NOT EXISTS `jse_map_controlpoints`("
	...		"`id` INT AUTO_INCREMENT,"
	...		"`map_id` INT NOT NULL,"
	...		"`course_id` INT NOT NULL,"
	...		"`identifier` VARCHAR(128),"
	...		"`x` INT,"
	...		"`y` INT,"
	...		"`z` INT,"
	...		"PRIMARY KEY(`id`),"
	... 	"UNIQUE(`map_id`, `course_id`),"
	...		"CONSTRAINT `fk_controlpoint_map` FOREIGN KEY(`map_id`)"
	...		"REFERENCES `jse_maps`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,"
	...		"CONSTRAINT `fk_controlpoint_course` FOREIGN KEY(`course_id`)"
	...		"REFERENCES `jse_map_courses`(`id`) ON DELETE CASCADE ON UPDATE CASCADE"
	... ") ENGINE=INNODB");
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

	g_hDatabase.Query(DB_Callback_AddMap, sQuery);
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

void DB_AddJump(Transaction hTxn, int iCourse, int iJump, char[] sIdentifier, int iX, int iY, int iZ) {
	char sQuery[1024];

	if (sIdentifier[0]) {
		g_hDatabase.Format(sQuery, sizeof(sQuery), \
			"INSERT IGNORE INTO `jse_map_jumps`(`map_id`, `course_id`, `jump`, `identifier`)"
		...	"SELECT %d, `id`, %d, '%s' FROM `jse_map_courses` WHERE `course`=%d", g_iMapID, iJump, sIdentifier, iCourse);
	} else {
		g_hDatabase.Format(sQuery, sizeof(sQuery), \
			"INSERT IGNORE INTO `jse_map_jumps`(`map_id`, `course_id`, `jump`, `x`, `y`, `z`)"
		...	"SELECT %d, `id`, %d, %d, %d, %d FROM `jse_map_courses` WHERE `course`=%d", g_iMapID, iJump, iX, iY, iZ, iCourse);
	}

	hTxn.AddQuery(sQuery, iCourse);
}

void DB_AddControlPoint(Transaction hTxn, int iCourse, char[] sIdentifier, int iX, int iY, int iZ) {
	char sQuery[1024];

	if (sIdentifier[0]) {
		g_hDatabase.Format(sQuery, sizeof(sQuery), \
			"INSERT IGNORE INTO `jse_map_controlpoints`(`map_id`, `course_id`, `identifier`)"
		...	"SELECT %d, `id`, '%s' FROM `jse_map_courses` WHERE `course`=%d", g_iMapID, sIdentifier, iCourse);
	} else {
		g_hDatabase.Format(sQuery, sizeof(sQuery), \
			"INSERT IGNORE INTO `jse_map_controlpoints`(`map_id`, `course_id`, `x`, `y`, `z`)"
		...	"SELECT %d, `id`, %d, %d, %d FROM `jse_map_courses` WHERE `course`=%d", g_iMapID, iX, iY, iZ, iCourse);
	}

	hTxn.AddQuery(sQuery, iCourse);
}

void DB_ExecuteAddMapInfoTX(Transaction hTxn) {
	char sQuery[1024];
	g_hDatabase.Format(sQuery, sizeof(sQuery), "UPDATE `jse_maps` SET `lastupdate`=UTC_TIMESTAMP WHERE `id`=%d", g_iMapID);
	hTxn.AddQuery(sQuery);
	g_hDatabase.Execute(hTxn, DB_Callback_AddMapInfo_Txn_Success, DB_Callback_AddMapInfo_Txn_Failure);
}

void DB_LoadMapData() {
	char sQuery[1024];
	g_hDatabase.Format(sQuery, sizeof(sQuery), "SELECT `id`, `course`, `name` FROM `jse_map_courses` WHERE `map_id`=%d", g_iMapID);
	g_hDatabase.Query(DB_Callback_LoadMapData, sQuery);
}

void DB_LookupMapID() {
	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

	char sQuery[1024];
	g_hDatabase.Format(sQuery, sizeof(sQuery), "SELECT `id`, `lastupdate` FROM `jse_maps` WHERE `filename`='%s'", sMapName);
	g_hDatabase.Query(DB_Callback_LookupMapID, sQuery);
}

// Timers

public Action Timer_Reconnect(Handle hTimer) {
	DB_Connect();
	
	return Plugin_Handled;
}
