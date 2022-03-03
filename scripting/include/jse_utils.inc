#include <tf2>
#include <tf2_stocks>

/**
 * Gets the item definition index of a TF2 item entity
 *
 * @param iEntity		Item entity index
 */
stock int GetItemDefIndex(int iEntity) {
	return GetEntProp(iEntity, Prop_Send, "m_iItemDefinitionIndex");
}

/**
 * Gets the equivalent base weapon item definition indices for the client's currently equipped primary,
 * secondary, and melee loadout slots, or -1 if the item is unavailable or has no impact on jump mechanics
 *
 * @param iClient		Client index.
 * @param iWeapon1		Item definition index for the primary weapon.
 * @param iWeapon2		Item definition index for the secondary weapon.
 * @param iWeapon3		Item definition index for the melee weapon.
 */
stock void GetWeaponsNormalized(int iClient, int &iWeapon1, int &iWeapon2, int &iWeapon3) {
	TFClassType iClass = TF2_GetPlayerClass(iClient);

	iWeapon1 = GetPlayerWeaponSlot(iClient, TFWeaponSlot_Primary);
	iWeapon2 = GetPlayerWeaponSlot(iClient, TFWeaponSlot_Secondary);
	iWeapon3 = GetPlayerWeaponSlot(iClient, TFWeaponSlot_Melee);

	if (iWeapon1 != -1) {
		iWeapon1 = GetItemDefIndex(iWeapon1);

		switch (iClass) {
			case TFClass_Scout: {
				switch (iWeapon1) {
					case 45, 448: {
						//   45: Force-A-Nature
						//  448: The Soda Popper
					}
					default: {
						//   13: Scattergun
						iWeapon1 = 13;
					}
				}
			}
			case TFClass_Soldier: {
				switch (iWeapon1) {
					case 513, 730, 1104: {
						//  513: The Original
						//  730: The Beggar's Bazooka
						// 1104: The Air Strike
					}
					default: {
						//   18: Rocket Launcher
						iWeapon1 = 18;
					}
				}
			}
			case TFClass_DemoMan: {
				switch (iWeapon1) {
					case 405, 608: {
						//  405: Ali Baba's Wee Booties
						//  608: The Bootlegger
						iWeapon1 = 405;
					}
					case 308, 996, 1101, 1151: {
						//  308: The Loch-n-Load
						//  996: The Loose Cannon
						// 1101: The B.A.S.E. Jumper
						// 1151: The Iron Bomber
					}
					default: {
						//   19: Grenade Launcher
						iWeapon1 = 19;
					}
				}
			}
			default: {
				// Irrelevant
				iWeapon1 = -1;
			}
		}
	}

	if (iWeapon2 != -1) {
		iWeapon2 = GetItemDefIndex(iWeapon2);
		switch (iClass) {
			case TFClass_Scout: {
				switch (iWeapon2) {
					case 449: {
						//  449: The Winger
					}
					default:  {
						//   23: Scout's Pistol
						iWeapon2 = 23;
					}
				}
			}
			case TFClass_Soldier: {
				switch (iWeapon2) {
					case 133, 415, 444, 1101, 1153: {
						//  133: Gunboats
						//  415: The Reserve Shooter
						//  444: The Mantreads
						// 1101: The B.A.S.E. Jumper
						// 1153: Panic Attack

					}
					default: {
						//   10:  Soldier's Shotgun
						iWeapon2 = 10;
					}
				}
			}
			case TFClass_DemoMan: {
				switch (iWeapon2) {
					case 131, 1144: {
						//  131: The Chargin' Targe
						// 1144: Festive Targe
						iWeapon2 = 131;
					}
					case 130, 406, 1099, 1150: {
						//  130: The Scottish Resistance
						//  406: The Splendid Screen
						// 1099: The Tide Turner
						// 1150: The Quickiebomb Launcher
					}
					default: {
						//   20: Stickybomb Launcher
						iWeapon2 = 20;
					}
				}
			}
			case TFClass_Medic: {
				//  411: The Quick-Fix
				iWeapon2 = 411;
			}
			case TFClass_Pyro: {
				switch (iWeapon2) {
					case 39, 1081: {
						//   39: The Flare Gun
						// 1081: Festive Flare Gun
						iWeapon2 = 39;
					}
					case 351, 415, 595, 740, 1153, 1179, 1180: {
						//  351: The Detonator
						//  415: The Reserve Shooter
						//  595: The Manmelter
						//  740: The Scorch Shot
						// 1153: Panic Attack
						// 1179: Thermal Thruster
						// 1180: Gas Passer
					}
					default: {
						//   12: Pyro's Shotgun
						iWeapon2 = 12;
					}
				}
			}
			case TFClass_Engineer: {
				//  140: The Wrangler
				iWeapon2 = 140;
			}
			default: {
				// Irrelevant
				iWeapon2 = -1;
			}
		}
	}

	if (iWeapon3 != -1) {
		iWeapon3 = GetItemDefIndex(iWeapon3);

		switch (iClass) {
			case TFClass_Scout: {
				switch (iWeapon3) {
					case 325, 452: {
						//  325: The Boston Basher
						//  452: Three-Rune Blade
						iWeapon3 = 325;
					}
					case 450: {
						//  450: The Atomizer
					}
					default: {
						//    0: Bat
						iWeapon3 = 0;
					}
				}
			}
			case TFClass_DemoMan: {
				switch (iWeapon3) {
					case 307: {
						//  307: Ullapool Caber
					}
					default: {
						//    1: Bottle
						iWeapon3 = 1;
					}
				}
			}
			case TFClass_Pyro: {
				switch (iWeapon3) {
					case 214: {
						//  214: The Powerjack
					}
					default: {
						//    2: Axe
						iWeapon3 = 2;
					}
				}
			}
			default: {
				// Irrelevant
				iWeapon3 = -1;
			}
		}
	}
}
