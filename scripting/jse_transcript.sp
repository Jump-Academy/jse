#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "AI"
#define PLUGIN_VERSION "0.1.0"

#include <sourcemod>

#include <jse_tracker>

public Plugin myinfo = {
	name = "Jump Server Essentials - Transcript",
	author = PLUGIN_AUTHOR,
	description = "JSE course progression logging module",
	version = PLUGIN_VERSION,
	url = "https://jumpacademy.tf"
};

public void OnPluginStart() {
	if (IsTrackerLoaded()) {
		DB_CreateTables();
	}
}

public void OnCoursesLoaded(ArrayList hCourses) {
	DB_CreateTables();
}

public void OnCheckpointReached(int iClient, Course iCourse, Jump iJump, ControlPoint iControlPoint) {
	DB_LogProgress(iClient, iCourse, iJump, iControlPoint);
}

// Database callbacks

public void DB_Callback_CreateTable(Database hDatabase, DBResultSet hResultSet, char[] sError, any aData) {
	if (hResultSet == null) {
		SetFailState("Database error while creating table: %s", sError);
		return;
	}
}

public void DB_Callback_LogProgress(Database hDatabase, DBResultSet hResultSet, char[] sError, any aData) {
	if (hResultSet == null) {
		SetFailState("Database error while logging progress for player %N: %s", aData, sError);
		return;
	}
}

// Database helpers

void DB_CreateTables() {
	Database hDatabase = GetTrackerDatabase();

	hDatabase.Query(DB_Callback_CreateTable, \
		"CREATE TABLE IF NOT EXISTS `jse_transcript`("
	...		"`id` INT AUTO_INCREMENT,"
	...		"`auth` BIGINT,"
	...		"`map_id` INT NOT NULL,"
	...		"`course_id` INT NOT NULL,"
	...		"`jump_id` INT,"
	...		"`controlpoint_id` INT,"
	...		"`timestamp` DATETIME,"
	...		"PRIMARY KEY(`id`),"
	... 	"UNIQUE(`auth`, `map_id`, `course_id`, `jump_id`, `controlpoint_id`),"
	...		"CONSTRAINT `fk_transcript_map` FOREIGN KEY(`map_id`)"
	...		"REFERENCES `jse_maps`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,"
	...		"CONSTRAINT `fk_transcript_course` FOREIGN KEY(`course_id`)"
	...		"REFERENCES `jse_map_courses`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,"
	...		"CONSTRAINT `fk_transcript_jump` FOREIGN KEY(`jump_id`)"
	...		"REFERENCES `jse_map_jumps`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,"
	...		"CONSTRAINT `fk_transcript_controlpoint` FOREIGN KEY(`controlpoint_id`)"
	...		"REFERENCES `jse_map_controlpoints`(`id`) ON DELETE CASCADE ON UPDATE CASCADE"
	... ") ENGINE=INNODB");
}

void DB_LogProgress(int iClient, Course iCourse, Jump iJump, ControlPoint iControlPoint) {
	Database hDatabase = GetTrackerDatabase();

	char sAuthID[64];
	GetClientAuthId(iClient, AuthId_SteamID64, sAuthID, sizeof(sAuthID));

	char sQuery[1024];
	if (iJump) {
		hDatabase.Format(sQuery, sizeof(sQuery), \
			"INSERT IGNORE INTO `jse_transcript`(`auth`, `map_id`, `course_id`, `jump_id`, `timestamp`)"
		...	"VALUES (%s, %d, %d, %d, UTC_TIMESTAMP)", sAuthID, GetTrackerMapID(), iCourse.iID, iJump.iID);
		hDatabase.Query(DB_Callback_LogProgress, sQuery, iClient);
	} else if (iControlPoint) {
		hDatabase.Format(sQuery, sizeof(sQuery), \
			"INSERT IGNORE INTO `jse_transcript`(`auth`, `map_id`, `course_id`, `controlpoint_id`, `timestamp`)"
		...	"VALUES (%s, %d, %d, %d, UTC_TIMESTAMP)", sAuthID, GetTrackerMapID(), iCourse.iID, iControlPoint.iID);
		hDatabase.Query(DB_Callback_LogProgress, sQuery, iClient);
	}
}
