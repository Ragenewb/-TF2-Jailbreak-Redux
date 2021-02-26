enum struct TextNodeParam
{	// Hud Text Parameters
	float fCoord_X;
	float fCoord_Y;
	float fHoldTime;
	int iRed;
	int iBlue;
	int iGreen;
	int iAlpha;
	int iEffect;
	float fFXTime;
	float fFadeIn;
	float fFadeOut;
	Handle hHud;

	void Display(const char[] text)
	{
		SetHudTextParams(this.fCoord_X, this.fCoord_Y, this.fHoldTime, this.iRed, this.iGreen, this.iBlue, this.iAlpha, this.iEffect, this.fFXTime, this.fFadeIn, this.fFadeOut);

		for (int i = MaxClients; i; --i)
			if (IsClientInGame(i))
				ShowSyncHudText(i, this.hHud, text);
	}
}

enum struct TargetFilter
{	// Custom target filters allocated by config
	float vecLoc[3];
	float flDist;
	bool bML;
	char strDescriptN[64];
	char strDescriptA[64];
	char strName[32];	// If you have a filter > 32 chars then you got some serious problems
}

enum struct JailRole
{
	int iColor[4];
	float flOffset;
	char strParticle[64];
	char strAttachment[64];

	void Reset()
	{
		this.iColor[0] = this.iColor[1] = this.iColor[2] = this.iColor[3] = 255;
		this.flOffset = 0.0;
		this.strParticle[0] = '\0';
		this.strAttachment[0] = '\0';
	}

	void Create(KeyValues kv, const char[] role)
	{
		this.Reset();
		if (!kv.JumpToKey(role))
			return;

		kv.GetColor4("Color", this.iColor);
		kv.GetString("Particle", this.strParticle, 64);
		this.flOffset = kv.GetFloat("Offset", 0.0);
		kv.GetString("Attachment", this.strAttachment, 64);
		kv.GoBack();
	}
}

char
	strBackgroundSong[PLATFORM_MAX_PATH],	// Background song
	strCellNames[32],						// Names of Cells
	strCellOpener[32],						// Cell button
	strFFButton[32],						// FF button
	strConfig[CFG_LENGTH][256]				// Path to config files
;

// KeyValues name for config
char strKVConfig[CFG_LENGTH][64] = {
	"TF2Jail_LastRequests",
	"TF2Jail_MapConfig",
	"TF2Jail_RoleRenders",
	"TF2Jail_Nodes",
	"WardenMenu"
};

int
	iHalo,									// Particle
	iLaserBeam,								// Particle
	iHalo2									// Particle
;

float
	vecOld[MAX_TF_PLAYERS][3],				// Freeday beam vector
	vecFreedayPosition[3], 					// Freeday map position
	vecWardayBlu[3], 						// Blue warday map position
	vecWardayRed[3]							// Red warday map position
;

bool
	bLate,									// Late-loaded plugin
#if defined _SteamWorks_Included
	g_bSteam,								// SteamWorks enabled
#endif
#if defined _sourcebans_included || defined _sourcebanspp_included
//	g_bSB,									// SourceBans enabled
#endif
#if defined _voiceannounce_ex_included
//	g_bVA,									// VoiceAnnounce_Ex enabled
#endif
#if defined __tf_ontakedamage_included
	g_bTFOTD,								// TFOnTakeDamage enabled
#endif
	g_bTF2Attribs,							// TF2Attributes enabled
	g_bSC									// SourceComms enabled
;

TextNodeParam
	EnumTNPS[4]								// HUD elements
;

JailRole
	g_WardenRole,							// Warden role
	g_FreedayRole,							// Freeday role
	g_RebelRole,							// Rebel role
	g_FreekillerRole						// Freekiller role
;

// If adding new cvars put them above Version in the enum in TF2Jail_Redux.sp
ConVar
	cvarTF2Jail[Version + 1],
	bEnabled,
	hEngineConVars[2]						// 0 -> mp_friendlyfire; 1 -> tf_avoidteammates_pushaway
;

Handle
	AimHud
;

Cookie
	MusicCookie
;

StringMap
	hJailFields[MAX_TF_PLAYERS]				// Get/Set
;

methodmap JailFighter < JBPlayer
{
	public JailFighter( const int ind )
	{
		return view_as< JailFighter >(ind);
	}

	public static JailFighter OfUserId( const int userid )
	{
		return view_as< JailFighter >(GetClientOfUserId(userid));
	}

	public static JailFighter Of( const any thing )
	{
		return view_as< JailFighter >(thing);
	}

	property StringMap hMap
	{
		public get()				{ return hJailFields[view_as< int >(this)]; }
	}

	property bool bNoMusic
	{
		public get()
		{
			if (!AreClientCookiesCached(this.index))
				return false;

			char strMusic[4];
			MusicCookie.Get(this.index, strMusic, sizeof(strMusic));
			return !!StringToInt(strMusic);
		}
		public set( const bool i )
		{
			if (!AreClientCookiesCached(this.index))
				return;

			char strMusic[4];
			IntToString(i, strMusic, sizeof(strMusic));
			MusicCookie.Set(this.index, strMusic);
		}
	}

	/**
	 *	Creates and spawns a weapon to a player.
	 *
	 *	@param name			Entity name of the weapon, example: "tf_weapon_bat".
	 *	@param index		The index of the desired weapon.
	 *	@param level		The level of the weapon.
	 *	@param qual			The weapon quality of the item.
	 *	@param att			The nested attribute string, example: "2 ; 2.0" - increases weapon damage by 100% aka 2x..
	 *
	 *	@return				Entity index of the newly created weapon.
	*/
	public int SpawnWeapon( char[] name, int index, int level, int qual, char[] att )
	{
		Handle hWeapon = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
		if (hWeapon == null)
			return -1;

		TF2Items_SetClassname(hWeapon, name);
		TF2Items_SetItemIndex(hWeapon, index);
		TF2Items_SetLevel(hWeapon, level);
		TF2Items_SetQuality(hWeapon, qual);
		char atts[32][32];
		int count = ExplodeString(att, " ; ", atts, 32, 32);
		count &= ~1;
		if (count > 0) 
		{
			TF2Items_SetNumAttributes(hWeapon, count/2);
			int i2 = 0;
			for (int i = 0 ; i < count ; i += 2) 
			{
				TF2Items_SetAttribute(hWeapon, i2, StringToInt(atts[i]), StringToFloat(atts[i+1]));
				i2++;
			}
		}
		else TF2Items_SetNumAttributes(hWeapon, 0);

		int entity = TF2Items_GiveNamedItem(this.index, hWeapon);
		delete hWeapon;
		EquipPlayerWeapon(this.index, entity);
		return entity;
	}

	/**
	 *	Retrieve an item definition index of a player's weaponslot.
	 *
	 *	@param slot 		Slot to grab the item index from.
	 *
	 *	@return 			Index of the valid, equipped weapon.
	*/
	public int GetWeaponSlotIndex( const int slot )
	{
		int weapon = GetPlayerWeaponSlot(this.index, slot);
		return GetItemIndex(weapon);
	}
	/**
	 *	Set the alpha magnitude a player's weapons.
	 *
	 *	@param alpha 		Number from 0 to 255 to set on the weapon.
	 *
	 *	@noreturn
	*/
	public void SetWepInvis( const int alpha )
	{
		int transparent = alpha;
		int entity;
		for (int i = 0; i < 5; i++) 
		{
			entity = GetPlayerWeaponSlot(this.index, i); 
			if (IsValidEntity(entity))
			{
				if (transparent > 255)
					transparent = 255;
				if (transparent < 0)
					transparent = 0;
				SetEntityRenderMode(entity, RENDER_TRANSCOLOR); 
				SetEntityRenderColor(entity, 150, 150, 150, transparent); 
			}
		}
	}
	/**
	 *	Create an overlay on a client.
	 *
	 *	@param strOverlay 	Overlay to use.
	 *
	 *	@noreturn
	*/
	public void SetOverlay( const char[] strOverlay )
	{
		int iFlags = GetCommandFlags("r_screenoverlay") & (~FCVAR_CHEAT);
		SetCommandFlags("r_screenoverlay", iFlags);
		ClientCommand(this.index, "r_screenoverlay \"%s\"", strOverlay);
	}
	/**
	 *	Teleport a player to the appropriate spawn location.
	 *
	 *	@param team 		Team spawn to teleport the client to.
	 *
	 *	@noreturn
	*/
	public void TeleToSpawn( int team = 0 )
	{
		int iEnt = -1;
		float vPos[3], vAng[3];
		ArrayList hArray = new ArrayList();
		while ((iEnt = FindEntityByClassname(iEnt, "info_player_teamspawn")) != -1)
		{
			if (GetEntProp(iEnt, Prop_Data, "m_bDisabled"))
				continue;

			if (team <= 1)
				hArray.Push(iEnt);
			else if (GetEntProp(iEnt, Prop_Send, "m_iTeamNum") == team)
				hArray.Push(iEnt);
		}
		iEnt = hArray.Get(GetRandomInt(0, hArray.Length-1));
		delete hArray;

		GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", vPos);
		GetEntPropVector(iEnt, Prop_Send, "m_angRotation", vAng);
		TeleportEntity(this.index, vPos, vAng, NULL_VECTOR);
	}
	/**
	 *	Spawn a small healthpack at the client's origin.
	 *
	 *	@param ownerteam 	Team to give the healthpack.
	 *
	 *	@noreturn
	*/
	public void SpawnSmallHealthPack( int ownerteam = 0 )
	{
		if (!IsPlayerAlive(this.index))
			return;

		int healthpack = CreateEntityByName("item_healthkit_small");
		if (IsValidEntity(healthpack))
		{
			float pos[3]; GetClientAbsOrigin(this.index, pos);
			pos[2] += 20.0;
			DispatchKeyValue(healthpack, "OnPlayerTouch", "!self,Kill,,0,-1");  //for safety, though it normally doesn't respawn
			DispatchSpawn(healthpack);
			SetEntProp(healthpack, Prop_Send, "m_iTeamNum", ownerteam, 4);
			SetEntityMoveType(healthpack, MOVETYPE_VPHYSICS);
			float vel[3];
			vel[0] = GetRandomFloat(-10.0, 10.0), vel[1] = GetRandomFloat(-10.0, 10.0), vel[2] = 50.0;
			TeleportEntity(healthpack, pos, NULL_VECTOR, vel);
		}
	}
	/**
	 *	Silently switch a player's team.
	 *
	 *	@param team 		Team to switch to.
	 *	@param spawn 		Determine whether or not to respawn the client.
	 *
	 *	@noreturn
	*/
	public void ForceTeamChange( const int team, bool spawn = true )
	{
		int client = this.index;
		if (TF2_GetPlayerClass(client) > TFClass_Unknown) 
		{
			SetEntProp(client, Prop_Send, "m_lifeState", 2);
			ChangeClientTeam(client, team);
			SetEntProp(client, Prop_Send, "m_lifeState", 0);
			if (spawn)
				TF2_RespawnPlayer(client);
		}
	}
	/**
	 *	Mute a client through the plugin.
	 *	@note 				Players that are deemed as admins will never be muted.
	 *
	 *	@noreturn
	*/
	public void MutePlayer()
	{
		if (this.bIsMuted || this.bIsAdmin || this.bIsWarden || AlreadyMuted(this.index))
			return;

		SetClientListeningFlags(this.index, VOICE_MUTED);
		this.bIsMuted = true;
	}
	/**
	 *	Unmute a player through the plugin.
	 *
	 *	@noreturn
	*/
	public void UnmutePlayer()
	{
		if (!this.bIsMuted || AlreadyMuted(this.index))
			return;

		SetClientListeningFlags(this.index, VOICE_NORMAL);
		this.bIsMuted = false;
	}
	/**
	 *	Initialize a player as a freeday.
	 *	@note 				Does not teleport them to the freeday location.
	 *
	 *	@noreturn
	*/
	public void GiveFreeday()
	{
		if (GetClientTeam(this.index) != RED || !IsPlayerAlive(this.index))
			this.ForceTeamChange(RED);

		int flags = GetEntityFlags(this.index) | FL_NOTARGET;
		SetEntityFlags(this.index, flags);

		this.bIsQueuedFreeday = false;
		this.bIsFreeday = true;

		if (cvarTF2Jail[RendererParticles].BoolValue && g_FreedayRole.strParticle[0] != '\0')
		{
			if (this.iFreedayParticle && IsValidEntity(this.iFreedayParticle))
				RemoveEntity(this.iFreedayParticle);

			this.iFreedayParticle = AttachParticle(this.index, g_FreedayRole.strParticle, _, g_FreedayRole.flOffset, _, g_FreedayRole.strAttachment);
//			if (cvarTF2Jail[HideParticles].BoolValue)
//				SDKHook(EntRefToEntIndex(this.iFreedayParticle), SDKHook_SetTransmit, OnParticleTransmit);
		}

		if (cvarTF2Jail[RendererColor].BoolValue)
			SetEntityRenderColor(this.index, g_FreedayRole.iColor[0], g_FreedayRole.iColor[1], g_FreedayRole.iColor[2], g_FreedayRole.iColor[3]);

		Call_OnFreedayGiven(this);
	}
	/**
	 *	Terminate a player as a freeday.
	 *
	 *	@noreturn
	*/
	public void RemoveFreeday()
	{
		int client = this.index;
		int flags = GetEntityFlags(client) & ~FL_NOTARGET;
		SetEntityFlags(client, flags);
		this.bIsFreeday = false;

		if (this.iFreedayParticle && IsValidEntity(this.iFreedayParticle))
			RemoveEntity(this.iFreedayParticle);

		this.iFreedayParticle = -1;

		if (cvarTF2Jail[RendererColor].BoolValue)
			SetEntityRenderColor(this.index);

		Call_OnFreedayRemoved(this);
	}
	/**
	 *	Remove all player weapons that are not their melee.
	 *
	 *	@noreturn
	*/
	public void StripToMelee()
	{
		int client = this.index;
		TF2_RemoveWeaponSlot(client, 0);
		TF2_RemoveWeaponSlot(client, 1);
		TF2_RemoveWeaponSlot(client, 3);
		TF2_RemoveWeaponSlot(client, 4);
		TF2_RemoveWeaponSlot(client, 5);
		//TF2_SwitchToSlot(client, TFWeaponSlot_Melee);

		char sClassName[64];
		int wep = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
		if (wep > MaxClients && IsValidEdict(wep) && GetEdictClassname(wep, sClassName, sizeof(sClassName)))
			SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", wep);
	}
	/**
	 *	Strip a player of all of their ammo.
	 *
	 *	@noreturn
	*/
	public void EmptyWeaponSlots()
	{
		int client = this.index;
		if (!IsClientValid(client))
			return;

		int weapon;
		// Thx Mr. Panica
		int length = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
		for (int i = 0; i < length; ++i)
		{
			weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
			if (weapon != -1)
			{
				if (GetEntProp(weapon, Prop_Data, "m_iClip1") != -1)
					SetEntProp(weapon, Prop_Send, "m_iClip1", 0);

				if (GetEntProp(weapon, Prop_Data, "m_iClip2") != -1)
					SetEntProp(weapon, Prop_Send, "m_iClip2", 0);

				SetWeaponAmmo(weapon, 0);
			}
		}

		SetEntProp(client, Prop_Send, "m_iAmmo", 0, 4, 3);

		int wep = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
		if (wep != -1)
			SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", wep);
	}
	/**	Props to VoIDed
	 *	Sets the custom model of this player.
	 *
	 *	@param model		The model to set on this player.
	*/
	public void SetCustomModel( const char[] model )
	{
		SetVariantString(model);
		AcceptEntityInput(this.index, "SetCustomModel");
	}
	/**
	 *	Initialize a player as the warden.
	 *	@note 				This automatically gives the player the warden menu
	 *
	 *	@return 			True on success, false otherwise.
	*/
	public bool WardenSet()
	{
		if (JBGameMode_GetProp("bWardenExists"))
			return false;

		if (JBGameMode_GetProp("bIsWardenLocked"))
			return false;

		if (GetClientTeam(this.index) != BLU)
			return false;

		if (Call_OnWardenGet(this) != Plugin_Continue)
			return false;

		this.bIsWarden = true;	
		this.UnmutePlayer();

		char strWarden[64];
		int client = this.index;
		FormatEx(strWarden, sizeof(strWarden), "%t", "New Warden Center", client);
		if (EnumTNPS[2].hHud != null)
			EnumTNPS[2].Display(strWarden);
		CPrintToChatAll("%t %t.", "Plugin Tag", "New Warden", client);

		float annottime = cvarTF2Jail[WardenAnnotation].FloatValue;
		if (annottime != 0.0)
		{
			Event event = CreateEvent("show_annotation");
			if (event)
			{
				int annot = CreateEntityByName("training_annotation");

				DispatchKeyValueFloat(annot, "lifetime", annottime);
				float origin[3]; GetClientAbsOrigin(client, origin);
				DispatchKeyValueVector(annot, "origin", origin);
				DispatchSpawn(annot);
				event.SetInt("index", view_as< int >(GetEntityAddress(annot)));
				SetPawnTimer(RemoveEnt, annottime, EntIndexToEntRef(annot));		// It's lifetime should kill it but w/e

				event.SetInt("follow_entindex", client);
				event.SetFloat("lifetime", annottime);

				FormatEx(strWarden, sizeof(strWarden), "%t", "Warden");
				event.SetString("text", strWarden);

				int bits, i;
				for (i = MaxClients; i; --i)
					if (IsClientInGame(i) && i != client)
						bits |= (1 << i);

				event.SetInt("visibilityBitfield", bits);
				event.Fire();
			}
		}

		if (cvarTF2Jail[RendererParticles].BoolValue && g_WardenRole.strParticle[0] != '\0')
		{
			if (this.iWardenParticle && IsValidEntity(this.iWardenParticle))
				RemoveEntity(this.iWardenParticle);

			this.iWardenParticle = AttachParticle(this.index, g_WardenRole.strParticle, _, g_WardenRole.flOffset, _, g_WardenRole.strAttachment);
//			if (cvarTF2Jail[HideParticles].BoolValue)
//				SDKHook(EntRefToEntIndex(this.iWardenParticle), SDKHook_SetTransmit, OnParticleTransmit);
		}

		if (cvarTF2Jail[RendererColor].BoolValue)
			SetEntityRenderColor(this.index, g_WardenRole.iColor[0], g_WardenRole.iColor[1], g_WardenRole.iColor[2], g_WardenRole.iColor[3]);

		ManageWarden(this);
		Call_OnWardenGetPost(this);
		return true;
	}
	/**
	 *	Terminate a player as the warden.
	 *
	 *	@return 			True on success, false otherwise.
	*/
	public bool WardenUnset()
	{
		if (!IsClientValid(this.index))
			return false;

		if (!this.bIsWarden)
			return false;

		if (EnumTNPS[2].hHud != null)
			for (int i = MaxClients; i; --i)
				if (IsClientInGame(i))
					ClearSyncHud(i, EnumTNPS[2].hHud);

		this.bIsWarden = false;
		this.bLasering = false;
		this.SetCustomModel("");
		JBGameMode_SetProp("iWarden", 0);
		JBGameMode_SetProp("bWardenExists", false);

		if (JBGameMode_GetProp("iRoundState") == StateRunning)
		{
			float time = cvarTF2Jail[WardenTimer].FloatValue;
			if (time != 0.0)
				SetPawnTimer(DisableWarden, time, JBGameMode_GetProp("iRoundCount"));
		}

		if (this.iWardenParticle && IsValidEntity(this.iWardenParticle))
			RemoveEntity(this.iWardenParticle);

		this.iWardenParticle = -1;

		if (cvarTF2Jail[RendererColor].BoolValue)
			SetEntityRenderColor(this.index);

		LastRequest lr = JBGameMode_GetCurrentLR();
		if (lr != null && lr.KillWeapons_Warden())
			TF2_RemoveCondition(this.index, TFCond_RestrictToMelee);	// This'll do, removed when warden is lost

		Call_OnWardenRemoved(this);
		return true;
	}
	/**
	 *	Remove all weapons, disguises, and wearables from a client.
	 *
	 *	@noreturn
	*/
	public void PreEquip( bool weps = true )
	{
		int client = this.index;
		TF2_RemovePlayerDisguise(client);
		int wearable;

		for (int i = TF2_GetNumWearables(client)-1; i >= 0; --i)
		{
			wearable = TF2_GetWearable(client, i);
			if (wearable != -1)
				TF2_RemoveWearable(client, wearable);
		}

		if (weps)
			TF2_RemoveAllWeapons(client);
	}
	/**
	 *	Teleport a player either to a freeday or warday location.
	 *	@note 				If gamemode teleport properties are not true, player will not be teleported.
	 *
	 *	@param location 	Location to teleport the client.
	 *
	 *	@return 			True if the player was teleported, false otherwise
	*/
	public bool TeleportToPosition( const int location )
	{
		switch (location)
		{
			case 1:if (JBGameMode_GetProp("bFreedayTeleportSet")) { TeleportEntity(this.index, vecFreedayPosition, NULL_VECTOR, NULL_VECTOR); return true; }
			case 2:if (JBGameMode_GetProp("bWardayTeleportSetRed")) { TeleportEntity(this.index, vecWardayRed, NULL_VECTOR, NULL_VECTOR); return true; }
			case 3:if (JBGameMode_GetProp("bWardayTeleportSetBlue")) { TeleportEntity(this.index, vecWardayBlu, NULL_VECTOR, NULL_VECTOR); return true; }
		}
		return false;
	}
	/**
	 *	List the last request menu to the player.
	 *
	 *	@noreturn
	*/
	public void ListLRS()
	{
		if (IsVoteInProgress())
			return;

		Menu menu = new Menu(LRMenuHandler, MENU_ACTIONS_DEFAULT|MenuAction_Display);
		AddLRsToMenu(this, menu);
		menu.Display(this.index, 0);

		Call_OnLRGiven(this);
		int time = cvarTF2Jail[LRTimer].IntValue;
		if (time/* && JBGameMode_GetProp("iTimeLeft") > time*/)
			JBGameMode_SetProp("iTimeLeft", time);
	}
	/**
	 *	Give a player the warden menu.
	 *
	 *	@noreturn
	*/
	public void WardenMenu()
	{
		if (IsVoteInProgress())
			return;

		view_as< Menu >(JBGameMode_GetProp("hWardenMenu")).Display(this.index, 0);		// Absolutely disgusting
	}
	/**
	 *	Allow a player to climb walls upon hitting them.
	 *
	 *	@param weapon 		Weapon the client is using to attack.
	 *	@param upwardvel	Velocity to send the client (in hammer units).
	 *	@param health 		Health to take from the client.
	 *	@param attackdelay 	Length in seconds to delay the player in attacking again.
	 *
	 *	@noreturn
	*/
	public void ClimbWall( const int weapon, const float upwardvel, const float health, const bool attackdelay )
	// Credit to Mecha the Slag
	{
		if (GetClientHealth(this.index) <= health) 	// Have to baby players so they don't accidentally kill themselves trying to escape
			return;

		int client = this.index;
		char classname[64];
		float vecClientEyePos[3];
		float vecClientEyeAng[3];
		GetClientEyePosition(client, vecClientEyePos);   // Get the position of the player's eyes
		GetClientEyeAngles(client, vecClientEyeAng);	   // Get the angle the player is looking

		// Check for colliding entities
		TR_TraceRayFilter(vecClientEyePos, vecClientEyeAng, MASK_PLAYERSOLID, RayType_Infinite, TraceRayDontHitSelf, client);

		if (!TR_DidHit())
			return;

		int TRIndex = TR_GetEntityIndex();
		GetEdictClassname(TRIndex, classname, sizeof(classname));
		if (!StrEqual(classname, "worldspawn"))
			return;

		float fNormal[3];
		TR_GetPlaneNormal(null, fNormal);
		GetVectorAngles(fNormal, fNormal);

		if (fNormal[0] >= 30.0 && fNormal[0] <= 330.0)
			return;
		if (fNormal[0] <= -30.0)
			return;

		float pos[3]; TR_GetEndPosition(pos);
		float distance = GetVectorDistance(vecClientEyePos, pos);

		if (distance >= 100.0)
			return;

		float fVelocity[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVelocity);
		fVelocity[2] = upwardvel;

		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fVelocity);
		if (health != 0.0)
			SDKHooks_TakeDamage(client, client, client, health, DMG_CLUB, 0);

		if (attackdelay)
			SetPawnTimer(NoAttacking, 0.1, EntIndexToEntRef(weapon));
	}
	/**
	 *	Have player attempt to vote to fire the current Warden.
	 *
	 *	@noreturn
	*/
	public void AttemptFireWarden()
	{
		int votes = JBGameMode_GetProp("iVotes");
		int total = JBGameMode_GetProp("iVotesNeeded");
		if (this.bVoted)
		{
			CPrintToChat(this.index, "%t %t", "Plugin Tag", "Fire Warden Already Voted", votes, total);
			return;
		}

		this.bVoted = true;
		++votes;
		JBGameMode_SetProp("iVotes", votes);
		CPrintToChatAll("%t %t", "Plugin Tag", "Fire Warden Requested", this.index, votes, total);

		if (votes >= total)
			JBGameMode_FireWarden();
	}
	/**
	 *	Mark a player as a rebel.
	 *
	 *	@noreturn
	*/
	public void MarkRebel()
	{
		if (!IsPlayerAlive(this.index) || GetClientTeam(this.index) != RED)
			return;

		if (this.bIsRebel)
		{
			float time = cvarTF2Jail[RebelTime].FloatValue;
			if (time != 0.0)
			{
				Handle h = this.hRebelTimer;
				KillTimerSafe(h);	// What the fuck
				this.hRebelTimer = CreateTimer(time, Timer_ClearRebel, this.userid, TIMER_FLAG_NO_MAPCHANGE);
			}
			return;
		}

		if (!cvarTF2Jail[Rebellers].BoolValue)
			return;

		if (JBGameMode_GetProp("bIgnoreRebels"))
			return;

		if (Call_OnRebelGiven(this) != Plugin_Continue)
			return;

		this.bIsRebel = true;
		if (cvarTF2Jail[RendererParticles].BoolValue && g_RebelRole.strParticle[0] != '\0')
		{
			if (this.iRebelParticle && IsValidEntity(this.iRebelParticle))
				RemoveEntity(this.iRebelParticle);

			this.iRebelParticle = AttachParticle(this.index, g_RebelRole.strParticle, _, g_RebelRole.flOffset, _, g_RebelRole.strAttachment);
//			if (cvarTF2Jail[HideParticles].BoolValue)
//				SDKHook(EntRefToEntIndex(this.iRebelParticle), SDKHook_SetTransmit, OnParticleTransmit);
		}

		if (cvarTF2Jail[RendererColor].BoolValue)
			SetEntityRenderColor(this.index, g_RebelRole.iColor[0], g_RebelRole.iColor[1], g_RebelRole.iColor[2], g_RebelRole.iColor[3]);

		CPrintToChatAll("%t %t", "Plugin Tag", "Prisoner Has Rebelled", this.index);

		float time = cvarTF2Jail[RebelTime].FloatValue;
		if (time != 0.0)
		{
			this.hRebelTimer = CreateTimer(time, Timer_ClearRebel, this.userid, TIMER_FLAG_NO_MAPCHANGE);
			CPrintToChat(this.index, "%t %t", "Plugin Tag", "Rebel Timer Start", RoundFloat(time));
		}
		Call_OnRebelGivenPost(this);
	}
	/**
	 *	Clear a player's rebel status.
	 *
	 *	@noreturn
	*/
	public void ClearRebel()
	{
		if (!this.bIsRebel)
			return;

		this.bIsRebel = false;
		if (this.iRebelParticle && IsValidEntity(this.iRebelParticle))
			RemoveEntity(this.iRebelParticle);

		this.iRebelParticle = -1;

		if (cvarTF2Jail[RendererColor].BoolValue)
			SetEntityRenderColor(this.index);

		// What the fuck
		Handle h = this.hRebelTimer;
		KillTimerSafe(h);
		this.hRebelTimer = null;

		CPrintToChat(this.index, "%t %t", "Plugin Tag", "Rebel Timer Remove");
		Call_OnRebelRemoved(this);
	}

	public void InviteToGuards(const JailFighter other)
	{
		CPrintToChatAll("%t %t", "Plugin Tag", "Warden Invite Player", this.index, other.index);
		Menu menu = new Menu(InviteReceiveMenu);
		menu.SetTitle("%t", "Menu Title Invited");
		char s[32];

		FormatEx(s, sizeof(s), "%t", "Join");
		menu.AddItem("0", s);
		FormatEx(s, sizeof(s), "%t", "Don't Join");
		menu.AddItem("1", s);

		menu.Display(other.index, 15);
	}

	public bool ResetFreekillerTimer()
	{
		if (this.bIsFreekiller)
		{
			float time = cvarTF2Jail[FreeKillTimer].FloatValue;
			if (time != 0.0)
			{
				Handle h = this.hFreekillTimer;
				KillTimerSafe(h);
				this.hFreekillTimer = CreateTimer(time, Timer_ClearFreekiller, this.userid, TIMER_FLAG_NO_MAPCHANGE);
			}
			return true;
		}
		return false;
	}

	public void MarkFreekiller()
	{
		if (this.ResetFreekillerTimer())
			return;

		if (Call_OnMarkedFreekiller(this) != Plugin_Continue)
			return;

		int messagetype = cvarTF2Jail[FreeKillMessage].IntValue;
		bool silent = cvarTF2Jail[FreeKillSilent].BoolValue;
		char msg[512];

		if (!silent)
			CPrintToChatAll("%t %t", "Plugin Tag", "Marked as Freekiller", this.index);
		else
		{
			for (int i = MaxClients; i; --i)
			{
				if (!IsClientInGame(i) || i == this.index)
					continue;

				if (!JailFighter(i).bIsAdmin)
					continue;

				CPrintToChat(i, "%t %t", "Plugin Tag", "Marked as Freekiller", this.index);
			}
		}

		if (messagetype)
		{
			char ip[32]; GetClientIP(this.index, ip, sizeof(ip));
			char steam[32]; GetClientAuthId(this.index, AuthId_Steam2, steam, sizeof(steam));
			FormatEx(msg, sizeof(msg), 
					"{burlywood}********************\n"
//				...	"%t\n"
				...	"UID: #%d\n"
				...	"Steam: %s\n"
				... "IP: %s\n"
				... "********************",
//				"Freekiller Admin Message", this.index, 
				this.userid, steam, ip);

			for (int i = MaxClients; i; --i)
			{
				if (!IsClientInGame(i) || i == this.index)
					continue;

				if (!JailFighter(i).bIsAdmin)
					continue;

				if (messagetype & (1 << 0))		// Chat
					CPrintToChat(i, msg);
				if (messagetype & (1 << 1))		// Console
				{
					CRemoveTags(msg, sizeof(msg));
					PrintToConsole(i, msg);
				}
			}
		}

		this.bIsFreekiller = true;
		if (!silent && cvarTF2Jail[RendererParticles].BoolValue && g_FreekillerRole.strParticle[0] != '\0')
		{
			if (this.iFreekillerParticle && IsValidEntity(this.iFreekillerParticle))
				RemoveEntity(this.iFreekillerParticle);

			this.iFreekillerParticle = AttachParticle(this.index, g_FreekillerRole.strParticle, _, g_FreekillerRole.flOffset, _, g_FreekillerRole.strAttachment);
		}

		if (!silent && cvarTF2Jail[RendererColor].BoolValue)
			SetEntityRenderColor(this.index, g_FreekillerRole.iColor[0], g_FreekillerRole.iColor[1], g_FreekillerRole.iColor[2], g_FreekillerRole.iColor[3]);

		cvarTF2Jail[FreeKillCommand].GetString(msg, sizeof(msg));
		if (msg[0] != '\0')
		{
			char s[12]; FormatEx(s, sizeof(s), "#%d", this.userid);
			ReplaceString(msg, sizeof(msg), "{PLAYER}", s);
			ServerCommand("%s", msg);
		}

		// Pretty sure a majority of plugins kick/ban in the next frame but just in case
		if (IsClientValid(this.index))
		{
			float time = cvarTF2Jail[FreeKillTimer].FloatValue;
			if (time != 0.0)
			{
				this.hFreekillTimer = CreateTimer(time, Timer_ClearFreekiller, this.userid, TIMER_FLAG_NO_MAPCHANGE);
				if (!silent)
					CPrintToChat(this.index, "%t %t", "Plugin Tag", "Freekiller Timer Start", RoundFloat(time));
			}

			Call_OnMarkedFreekillerPost(this);
		}
	}

	public void ClearFreekiller()
	{
		if (!this.bIsFreekiller)
			return;

		this.bIsFreekiller = false;
		if (this.iFreekillerParticle && IsValidEntity(this.iFreekillerParticle))
			RemoveEntity(this.iFreekillerParticle);

		this.iFreekillerParticle = -1;

		if (cvarTF2Jail[RendererColor].BoolValue)
			SetEntityRenderColor(this.index);

		Handle h = this.hFreekillTimer;
		KillTimerSafe(h);
		this.hFreekillTimer = null;

		if (!cvarTF2Jail[FreeKillSilent].BoolValue)
			CPrintToChat(this.index, "%t %t", "Plugin Tag", "Freekiller Timer Remove");
		this.flKillingSpree = 0.0;
		Call_OnFreekillerStatusRemoved(this);
	}
};
