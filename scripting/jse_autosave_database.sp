// Database callbacks

public void DB_Callback_CreateTable(Database hDatabase, DBResultSet hResultSet, char[] sError, any aData) {
	if (hResultSet == null) {
		SetFailState("Database error while creating table: %s", sError);
		return;
	}

	// Late load
	for (int i=1; i<=MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i)) {
			DB_LoadAutosaves(i);
		}
	}

	g_iLastBackupTime = GetTime();
}

public void DB_Callback_LoadAutosaves(Database hDatabase, DBResultSet hResultSet, char[] sError, any aData) {
	int iClient = GetClientFromSerial(aData);
	if (!iClient) {
		return;
	}

	if (hResultSet == null) {
		LogError("Database error while loading autosaves for player %N: %s", iClient, sError);
		return;
	}

	while (hResultSet.FetchRow()) {
		int iTeam = hResultSet.FetchInt(0);
		int iClass = hResultSet.FetchInt(1);

		// Sanity check
		if (iTeam != view_as<int>(TFTeam_Red) && iTeam != view_as<int>(TFTeam_Blue) || iClass <= 0 || iClass > 9) {
			continue;
		}

		int iCourseNumber = hResultSet.FetchInt(2);
		int iJumpNumber = hResultSet.FetchInt(3);

		bool bControlPoint = hResultSet.FetchInt(4) > 0;
		int iTimestamp = hResultSet.FetchInt(5);

		Checkpoint eCheckpoint;
		eCheckpoint.Init(iCourseNumber, iJumpNumber, bControlPoint, view_as<TFTeam>(iTeam), view_as<TFClassType>(iClass));
		eCheckpoint.iArrivalTime = iTimestamp;

		ArrayList hAutosave = g_hAutosave[iClient][iTeam-view_as<int>(TFTeam_Red)][iClass-1];
		if (!hAutosave) {
			hAutosave = new ArrayList(sizeof(Checkpoint));
			g_hAutosave[iClient][iTeam-view_as<int>(TFTeam_Red)][iClass-1] = hAutosave;
		}

		hAutosave.PushArray(eCheckpoint);
	}
}

public void DB_Callback_BackupAutosaves_Txn_Success(Database hDatabase, any aData, int iNumQueries, DBResultSet[] hResults, any[] aQueryData) {
	if (aData) {
		g_iLastBackupTime = aData;
	}
}

public void DB_Callback_BackupAutosaves_Txn_Failure(Database hDatabase, any aData, int iNumQueries, const char[] sError, int iFailIndex, any[] aQueryData) {
	int iClient;
	if (iFailIndex == -1 || !(iClient = GetClientFromSerial(aQueryData[iFailIndex]))) {
		LogError("Database error while backing up autosaves: %s", sError);
	} else {
		LogError("Database error while backing up autosaves for %N: %s", iClient, sError);
	}
}

public void DB_Callback_DeleteAutosave(Database hDatabase, DBResultSet hResultSet, char[] sError, any aData) {
	int iClient = GetClientFromSerial(aData);
	if (!iClient) {
		return;
	}

	if (hResultSet == null) {
		LogError("Database error while deleting autosave for player %N: %s", iClient, sError);
	}
}

// Database helpers

void DB_CreateTables(Database hDatabase) {
	if (!hDatabase) {
		return;
	}

	hDatabase.Query(DB_Callback_CreateTable, \
		"CREATE TABLE IF NOT EXISTS `jse_autosaves`("
	...		"`id` INT AUTO_INCREMENT,"
	...		"`auth` BIGINT NOT NULL,"
	...		"`map_id` INT NOT NULL,"
	...		"`team` INT NOT NULL,"
	...		"`class` INT NOT NULL,"
	...		"`course_id` INT NOT NULL,"
	...		"`jump_id` INT NULL,"
	...		"`controlpoint_id` INT NULL,"
	...		"`timestamp` DATETIME ON UPDATE CURRENT_TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,"
	...		"PRIMARY KEY(`id`),"
	...		"INDEX (`timestamp`),"
	... 	"UNIQUE(`auth`, `map_id`, `team`, `class`, `course_id`),"
	...		"CONSTRAINT `fk_autosave_map` FOREIGN KEY(`map_id`)"
	...		"REFERENCES `jse_maps`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,"
	...		"CONSTRAINT `fk_autosave_course` FOREIGN KEY(`course_id`)"
	...		"REFERENCES `jse_map_courses`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,"
	...		"CONSTRAINT `fk_autosave_jump` FOREIGN KEY(`jump_id`)"
	...		"REFERENCES `jse_map_jumps`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,"
	...		"CONSTRAINT `fk_autosave_controlpoint` FOREIGN KEY(`controlpoint_id`)"
	...		"REFERENCES `jse_map_controlpoints`(`id`) ON DELETE CASCADE ON UPDATE CASCADE"
	... ") ENGINE=INNODB", 0, DBPrio_High);
}

void DB_LoadAutosaves(int iClient) {
	if (!IsTrackerLoaded()) {
		return;
	}

	Database hDatabase = GetTrackerDatabase();
	if (!hDatabase) {
		return;
	}

	char sAuthID[64];
	if (!GetClientAuthId(iClient, AuthId_SteamID64, sAuthID, sizeof(sAuthID))) {
		LogError("Failed to load autosaves due to bad auth ID: %L", iClient);
		return;
	}

	char sQuery[1024];
	hDatabase.Format(sQuery, sizeof(sQuery), \
		"SELECT `team`, `class`, `mc`.`course`, `mj`.`jump`, `controlpoint_id`, UNIX_TIMESTAMP(`timestamp`)"
	...	"FROM `jse_autosaves` AS `a`"
	...	"LEFT JOIN `jse_map_courses` AS `mc` ON `a`.`course_id`=`mc`.`id`"
	...	"LEFT JOIN `jse_map_jumps` AS `mj` ON `a`.`jump_id`=`mj`.`id`"
	...	"WHERE `a`.`map_id`=%d AND `auth`=%s",
		GetTrackerMapID(), sAuthID);

	hDatabase.Query(DB_Callback_LoadAutosaves, sQuery, GetClientSerial(iClient));
}

void DB_BackupAutosaves(int iClient=0) {
	if (!IsTrackerLoaded()) {
		return;
	}

	Database hDatabase = GetTrackerDatabase();
	if (!hDatabase) {
		return;
	}

	Transaction hTxn = new Transaction();
	int iTotalQueries = 0;

	if (iClient) {
		iTotalQueries = DB_BackupAutosaves_Client(hDatabase, hTxn, iClient);
	} else {
		for (int i=1; i<=MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i)) {
				iTotalQueries += DB_BackupAutosaves_Client(hDatabase, hTxn, i);
			}
		}
	}

	if (iTotalQueries) {
		hDatabase.Execute(hTxn, DB_Callback_BackupAutosaves_Txn_Success, DB_Callback_BackupAutosaves_Txn_Failure, iClient ? 0 : GetTime(), DBPrio_Low);
	} else {
		delete hTxn;
	}
}

int DB_BackupAutosaves_Client(Database hDatabase, Transaction hTxn, int iClient) {
	char sAuthID[64];
	if (!GetClientAuthId(iClient, AuthId_SteamID64, sAuthID, sizeof(sAuthID))) {
		LogError("Failed to back up autosaves due to bad auth ID: %L", iClient);
		return 0;
	}

	Checkpoint eCheckpoint;

	char sQuery[1024];
	int iTotalQueries = 0;

	for (int i=0; i<sizeof(g_hAutosave[]); i++) {
		for (int j=0; j<sizeof(g_hAutosave[][]); j++) {
			ArrayList hCheckpoint = g_hAutosave[iClient][i][j];
			if (!hCheckpoint) {
				hCheckpoint = new ArrayList(sizeof(Checkpoint));
				g_hAutosave[iClient][i][j] = hCheckpoint;
			}

			for (int k=0; k<hCheckpoint.Length; k++) {
				hCheckpoint.GetArray(k, eCheckpoint);

				if (eCheckpoint.iArrivalTime <= g_iLastBackupTime) {
					continue;
				}

				Course mCourse = ResolveCourseNumber(eCheckpoint.GetCourseNumber());

				if (eCheckpoint.IsControlPoint()) {
					ControlPoint mControlPoint = mCourse.mControlPoint;

					hDatabase.Format(sQuery, sizeof(sQuery), \
						"INSERT INTO `jse_autosaves`(`auth`, `map_id`, `team`, `class`, `course_id`, `controlpoint_id`)"
					...	"VALUES (%s, %d, %d, %d, %d, %d)"
					...	"ON DUPLICATE KEY UPDATE"
					...		"`course_id`=VALUES(`course_id`),"
					...		"`jump_id`=NULL,"
					...		"`controlpoint_id`=VALUES(`controlpoint_id`)",
					sAuthID, GetTrackerMapID(), view_as<int>(TFTeam_Red)+i, j+1, mCourse.iID, mControlPoint.iID);
				} else {
					Jump mJump = ResolveJumpNumber(mCourse, eCheckpoint.GetJumpNumber());

					hDatabase.Format(sQuery, sizeof(sQuery), \
						"INSERT INTO `jse_autosaves`(`auth`, `map_id`, `team`, `class`, `course_id`, `jump_id`)"
					...	"VALUES (%s, %d, %d, %d, %d, %d)"
					...	"ON DUPLICATE KEY UPDATE"
					...		"`course_id`=VALUES(`course_id`),"
					...		"`jump_id`=VALUES(`jump_id`),"
					...		"`controlpoint_id`=NULL",
					sAuthID, GetTrackerMapID(), view_as<int>(TFTeam_Red)+i, j+1, mCourse.iID, mJump.iID);
				}

				hTxn.AddQuery(sQuery, GetClientSerial(iClient));
				iTotalQueries++;
			}
		}
	}

	return iTotalQueries;
}

void DB_DeleteAutosave(int iClient, int iCourseNumber, int iJumpNumber, bool bControlPoint, TFTeam iTeam, TFClassType iClass) {
	if (!IsTrackerLoaded()) {
		return;
	}

	Database hDatabase = GetTrackerDatabase();
	if (!hDatabase) {
		return;
	}

	char sAuthID[64];
	if (!GetClientAuthId(iClient, AuthId_SteamID64, sAuthID, sizeof(sAuthID))) {
		LogError("Failed to load autosaves due to bad auth ID: %L", iClient);
		return;
	}

	Course mCourse = ResolveCourseNumber(iCourseNumber);

	char sQuery[1024];

	if (bControlPoint) {
		ControlPoint mControlPoint = mCourse.mControlPoint;

		hDatabase.Format(sQuery, sizeof(sQuery), \
			"DELETE FROM `jse_autosaves`"
		...	"WHERE `auth`=%s AND `map_id`=%d AND `team`=%d AND `class`=%d AND `course_id`=%d AND `controlpoint_id`=%d",
			sAuthID, GetTrackerMapID(), iTeam, iClass, mCourse.iID, mControlPoint.iID);
	} else {
		Jump mJump = ResolveJumpNumber(mCourse, iJumpNumber);

		hDatabase.Format(sQuery, sizeof(sQuery), \
			"DELETE FROM `jse_autosaves`"
		...	"WHERE `auth`=%s AND `map_id`=%d AND `team`=%d AND `class`=%d AND `course_id`=%d AND `jump_id`=%d",
			sAuthID, GetTrackerMapID(), iTeam, iClass, mCourse.iID, mJump.iID);
	}

	hDatabase.Query(DB_Callback_DeleteAutosave, sQuery, GetClientSerial(iClient));
}
