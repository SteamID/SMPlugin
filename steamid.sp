/**
SteamID.eu plugin
Sourcecode provided as part of the sourcemod licence
Provided by an anonymous contributor and updated by Martin.
My First plugin in a language i dont know, but it appears to work, Please be gentle	

1.0.6 / 11/02/2018 - beta release
**/	
#pragma semicolon 1
#include <sourcemod>
#undef REQUIRE_EXTENSIONS
#include <SteamWorks>
#define VERSION "1.0.6" 

public Plugin:myinfo = 
{
  name = "SteamID",
  author = "SteamID.eu",
  description = "Gives players the ability to use the SteamID.eu API in game & auto kick bad users",
  version = VERSION,
  url = "https://steamid.eu"
};


enum APIError: {
	AE_Unknown = 0, 					// An unrecognized error.
	AE_NotFound, 						// The profile isn't in the SteamID.eu database.
	AE_TooLong, 						// The submitted Steam64ID is too long.
	AE_BadKey, 							// The API key is not recognized.
	AE_OverLimit, 						// The API key has reached its limit for this end point.
	AE_NullID, 							// The submitted Steam64ID is blank.
	AE_NullKey 							// The submitted API key is blank.
	//AE_BadVanity, 					// The submitted vanity URL was not found.
	//AE_NoResults 						// The submitted vanity URL was found but there are no results.
}

enum PlayerState: {
	PlayerState_None = 0, 				// The default state when a player connects.
	PlayerState_Valid, 					// At least some valid information has been returned for this player.
	PlayerState_NotFound 				// This player is not in the SteamID.eu database yet.
}

// An enum array "hack" is the best way to store all this data.
enum PlayerInfo {
	PlayerState:PlayerInfo_State, 		// The player's info state.
	PlayerInfo_Games, 					// Amount of games the player owns.
	PlayerInfo_VACBans, 				// Amount of VAC bans the player has.
	PlayerInfo_GameBans, 				// Amount of game bans the player has.
	PlayerInfo_PreviousNames, 			// Amount of previous names the player has had.
	PlayerInfo_SteamIDRating, 			// The player's SteamID.eu rating.
	PlayerInfo_PreviousFriends, 		// Amount of previous friends the player has had.
	Float:PlayerInfo_GenerationTime, 	// Amount of time taken to complete the request.
	bool:PlayerInfo_SIDAvailable, 		// If there is any SteamID.eu data available.
	bool:PlayerInfo_TradeBan, 			// If the player is trade banned or not.
	bool:PlayerInfo_SidBan, 			// If the player is SteamID Banned
	bool:PlayerInfo_Steamrepbanned, 			// If the player is SteamID Banned
	bool:PlayerInfo_CommunityBan, 		// If the player is community banned or not.
	String:PlayerInfo_SteamID[32], 		// The player's SteamID in 32-bit format.
	String:PlayerInfo_Steam3ID[32], 	// The player's Steam3ID.
	String:PlayerInfo_Steam64ID[32] 	// The player's SteamID in 64-bit format.
};

// We're caching connected player's info.
int g_iPlayerInfo[MAXPLAYERS + 1][PlayerInfo];

// Keep track of who they're viewing in the menu.
int g_iViewing[MAXPLAYERS + 1];

// During late-load all connected players need their info fetched.
bool g_bLateLoaded;

// Let's see if SteamWorks is actually available.
bool g_bSteamWorks;

// Let the server owner set their own API key.
ConVar g_cvAPIKey;
char g_sAPIKey[21];

ConVar g_kick_trade_banned;
ConVar g_kick_steamid_banned;
ConVar g_kick_vac_banned;
ConVar g_kick_community_banned;
ConVar g_kick_game_banned;
ConVar g_kick_steamrep_banned;



public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// Store if we're late-loading.
	g_bLateLoaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	/*if (LibraryExists("updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }*/
	

	// common.phrases.txt is required to use FindTarget()
	LoadTranslations("common.phrases");
	LoadTranslations("core.phrases");

	// Register the command with a few aliases.
	RegConsoleCmd("sm_info", SM_DisplayInfo);
	RegConsoleCmd("sm_lookup", SM_DisplayInfo);
	RegConsoleCmd("sm_steamid", SM_DisplayInfo);
	//RegConsoleCmd("sm_manualget", sm_manualget);

	// Create the API key convar and others.
	g_cvAPIKey = CreateConVar("steamid_api_key", "SteamID Api Key Here", "The API key to access SteamID.eu", FCVAR_PROTECTED);
	g_cvAPIKey.AddChangeHook(OnConVarChanged);
	g_cvAPIKey.GetString(g_sAPIKey, sizeof(g_sAPIKey));
	g_kick_trade_banned = CreateConVar("steamid_kick_tradebanned", "1", "Automatically kick trade banned players)");
	g_kick_steamid_banned = CreateConVar("steamid_kick_steamidbanned", "1", "Automatically kick steamid.eu banned players)");
	g_kick_vac_banned = CreateConVar("steamid_kick_vacbanned", "1", "Automatically kick vac banned players)");
	g_kick_community_banned = CreateConVar("steamid_kick_communitybanned", "1", "Automatically kick Community banned players)");
	g_kick_game_banned = CreateConVar("steamid_kick_gamebanned", "1", "Automatically kick game banned players)");
	g_kick_steamrep_banned = CreateConVar("steamid_kick_steamrepbanned", "1", "Automatically kick SteamRep banned players)");
	
	// Check if SteamWorks is loaded.
	g_bSteamWorks = LibraryExists("SteamWorks");
	// Info only needs to be fetched here if we're late-loading & SteamWorks is available.
	if (!g_bSteamWorks || !g_bLateLoaded)
		return;
	g_bLateLoaded = false;

	// Fetch info for in-game non-bot clients.
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i))
			FetchSteamInfo(i);


		
	PrintToServer("SteamID.eu API Plugin enabled");
	PrintToChatAll("\x01 \x06SteamID.eu API Plugin %s Loaded",VERSION);
}

public void OnPluginEnd()
{
	
	PrintToServer("SteamID.eu API Plugin Unloaded");
	PrintToChatAll("\x01 \x07SteamID.eu API Plugin Unloaded");

}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "SteamWorks"))
	{
		g_bSteamWorks = true;

		// If SteamWorks is added late, fetch all client info.
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i) && !IsFakeClient(i))
				FetchSteamInfo(i);
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "SteamWorks"))
		g_bSteamWorks = false;
}


public void OnClientAuthorized(int client, const char[] auth)
{
	// Fetch non-bot connecting client's info if SteamWorks is available.
	if (g_bSteamWorks && !IsFakeClient(client))
		FetchSteamInfo(client);

}


public void OnClientDisconnect(int client)
{
	// Reset ALL player data on client disconnect. (wow this is ugly...)
	g_iPlayerInfo[client][PlayerInfo_State] = PlayerState_None;
	g_iPlayerInfo[client][PlayerInfo_Games] = 0;
	g_iPlayerInfo[client][PlayerInfo_VACBans] = 0;
	g_iPlayerInfo[client][PlayerInfo_GameBans] = 0;
	g_iPlayerInfo[client][PlayerInfo_PreviousNames] = 0;
	g_iPlayerInfo[client][PlayerInfo_SteamIDRating] = 0;
	g_iPlayerInfo[client][PlayerInfo_PreviousFriends] = 0;
	g_iPlayerInfo[client][PlayerInfo_GenerationTime] = 0.0;
	g_iPlayerInfo[client][PlayerInfo_SIDAvailable] = false;
	g_iPlayerInfo[client][PlayerInfo_TradeBan] = false;
	g_iPlayerInfo[client][PlayerInfo_SidBan] = false;
	g_iPlayerInfo[client][PlayerInfo_Steamrepbanned] = false;
	g_iPlayerInfo[client][PlayerInfo_CommunityBan] = false;
	g_iPlayerInfo[client][PlayerInfo_SteamID][0] = '\0';
	g_iPlayerInfo[client][PlayerInfo_Steam3ID][0] = '\0';
	g_iPlayerInfo[client][PlayerInfo_Steam64ID][0] = '\0';

	// They're not viewing anyone anymore.
	g_iViewing[client] = 0;
}

/**
 * Command callbacks.
 */
public Action SM_DisplayInfo(int client, int args)
{
	

	// Don't allow this if SteamWorks isn't present.
	if (!g_bSteamWorks)
	{
		ReplyToCommand(client, "\x04 \x03[SteamID]\x01 \x01 SteamWorks is not available.");
		return Plugin_Handled;
	}
	
	// This can't be used from RCon.
	if (!client)
	{
		ReplyToCommand(client, "\x04 \x03[SteamID]\x01 \x01 This command is in-game only.");
		return Plugin_Handled;
	}

	// A target argument must be specified.
	if (args < 1)
	{
		ReplyToCommand(client, "\x04 \x03[SteamID]\x01 \x01 Usage: <#userid|name>");
		return Plugin_Handled;
	}

	char sArg[MAX_NAME_LENGTH];
	GetCmdArgString(sArg, sizeof(sArg));

	// Try to find a matching target.
	int iTarget = FindTarget(client, sArg, true, false);
	if (iTarget == -1)
		return Plugin_Handled;

	
	// Don't display null information.
	switch (g_iPlayerInfo[client][PlayerInfo_State])
	{
		case PlayerState_None:
		{
		ReplyToCommand(client, "\x04 \x03[SteamID]\x01 \x01  no info retrieved for %N yet.", iTarget);
		return Plugin_Handled;
		}
		case PlayerState_NotFound:
		{
			ReplyToCommand(client, "\x04 \x03[SteamID]\x01 \x01 %N is not in the SteamID.eu database yet.", iTarget);
			return Plugin_Handled;
		}
	}

	// Now we know we have a valid target's information to display.
	OpenMainMenu(client, iTarget);
	return Plugin_Handled;
}

/**
 * SteamWorks callbacks.
 */
public int Callback_RequestCompleted(Handle request, bool failure, bool requestsuccessful, EHTTPStatusCode eStatusCode, int serial)
{
	
	// Who knows if we need to check all 3 of these but why not be safe, right?
	if (failure || !requestsuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		LogError("HTTP request failed. Response: %d", eStatusCode);
		return;
	}

	// The client can disconnect during this async call.
	int client = GetClientFromSerial(serial);
	if (!client)
		return;

	int iLength;
	if (!SteamWorks_GetHTTPResponseBodySize(request, iLength))
		return;

	// Get our response from the body.
	char[] sResponse = new char[iLength];
	if (!SteamWorks_GetHTTPResponseBodyData(request, sResponse, iLength))
		return;


	
	// Turn the retrieved response into KeyValues.
	KeyValues hKeyValues = new KeyValues("steamidresults");
	if (!hKeyValues.ImportFromString(sResponse, "SteamID.eu"))
	{
		LogError("Failed to import KeyValues from response.");
		return;
	}
	

	if (!hKeyValues.GotoFirstSubKey())
	{
		LogError("Failed to jump to first sub-section.");
		return;
	}



	
	
	
	// Loop through all sub-sections. (profile, profile_bans, etc.)
	char sBuffer[64];
	do
	{
		hKeyValues.GetSectionName(sBuffer, sizeof(sBuffer));
		
		
		// Error checking comes first.
		if (StrEqual(sBuffer, "Error"))
		{
		APIError hError = view_as<APIError>(hKeyValues.GetNum("errorid", 0));
		switch (hError)
			{
				case AE_Unknown:
					LogError("API Error: Unknown error.");
				case AE_NotFound:
				{
					// This is a special case as we want to keep checking if the user has been added yet.
					g_iPlayerInfo[client][PlayerInfo_State] = PlayerState_NotFound;
					CreateTimer(60.0, Timer_FetchAgain, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
				}
				case AE_TooLong:
				//	LogError("API Error: ID too long.");
					PrintToChatAll("\x04 \x03[SteamID]\x01 \x02 API Error - Too Long");
				case AE_BadKey:
					//LogError("API Error: Invalid API key.");
					PrintToChatAll("\x04 \x03[SteamID]\x01 \x02 Invalid API Key");
				case AE_OverLimit:
					//	LogError("API Error: API key over limit.");
					PrintToChatAll("\x04 \x03[SteamID]\x01 \x02 Over the API Limit");
				case AE_NullID:
					LogError("API Error: Blank ID submitted.");
					//PrintToChatAll("\x04 \x03[SteamID]\x01 \x01 No ID given");
				case AE_NullKey:
					//	LogError("API Error: Blank API key submitted.");
					PrintToChatAll("\x04 \x03[SteamID]\x01 \x02 No ApiKey given");

			}
		delete hKeyValues;
		return;
		}

		
		// Now we know they have some valid information.
		g_iPlayerInfo[client][PlayerInfo_State] = PlayerState_Valid;

		
		
	
		
		
		// Continue to parse information.
		if (StrEqual(sBuffer, "profile"))
		{

			hKeyValues.GetString("steamid", sBuffer, sizeof(sBuffer), "N/A");
			strcopy(g_iPlayerInfo[client][PlayerInfo_SteamID], 32, sBuffer);

			hKeyValues.GetString("steam3", sBuffer, sizeof(sBuffer), "N/A");
			strcopy(g_iPlayerInfo[client][PlayerInfo_Steam3ID], 32, sBuffer);

			// Using the GetString on just the Steam64ID will clamp it to 2147483647 as it presumes it's an integer. (trim a link instead)
			hKeyValues.GetString("steamidurl", sBuffer, sizeof(sBuffer), "N/A");
			ReplaceString(sBuffer, sizeof(sBuffer), "https://steamid.eu/profile/", "");
			strcopy(g_iPlayerInfo[client][PlayerInfo_Steam64ID], 32, sBuffer);
		}
		else if (StrEqual(sBuffer, "profile_bans"))
		{
			g_iPlayerInfo[client][PlayerInfo_SidBan] = view_as<bool>(hKeyValues.GetNum("steamidbanned", 0));
			g_iPlayerInfo[client][PlayerInfo_VACBans] = hKeyValues.GetNum("vac", 0);
			g_iPlayerInfo[client][PlayerInfo_TradeBan] = view_as<bool>(hKeyValues.GetNum("tradeban", 0));
			g_iPlayerInfo[client][PlayerInfo_CommunityBan] = view_as<bool>(hKeyValues.GetNum("communityban", 0));
			g_iPlayerInfo[client][PlayerInfo_GameBans] = hKeyValues.GetNum("gamebans", 0);
			g_iPlayerInfo[client][PlayerInfo_Steamrepbanned] = view_as<bool>(hKeyValues.GetNum("steamrepbanned", 0));


			// Checks Ban Status AND if the convar is set
			if(g_iPlayerInfo[client][PlayerInfo_TradeBan] == true && g_kick_trade_banned.BoolValue == true)
			{
			//PrintToChatAll("\x01 \x07SteamID.eu Should be kicked for being steamid banned");
			KickClient(client, "You are showing as trade banned on Steamid.eu.");
			}
		
			if(g_iPlayerInfo[client][PlayerInfo_SidBan] == true && g_kick_steamid_banned.BoolValue == true)
			{
			//PrintToChatAll("\x01 \x07SteamID.eu Should be kicked");
			KickClient(client, "You are showing as steamid banned on Steamid.eu.");
			}
				
			if(g_iPlayerInfo[client][PlayerInfo_VACBans] == 1 && g_kick_vac_banned.BoolValue == true)
			{
			//PrintToChatAll("\x01 \x07SteamID.eu Should be kicked Vac Banned");
			KickClient(client, "You are showing as VAC banned on Steamid.eu.");
			}
			
			if(g_iPlayerInfo[client][PlayerInfo_CommunityBan] == true && g_kick_community_banned.BoolValue == true)
			{
			//PrintToChatAll("\x01 \x07SteamID.eu Should be kicked Community Ban");
			KickClient(client, "You are showing as Community banned on Steamid.eu.");
			}
						
			if(g_iPlayerInfo[client][PlayerInfo_GameBans] == 1 && g_kick_game_banned.BoolValue == true)
			{
			//PrintToChatAll("\x01 \x07SteamID.eu Should be kicked Game Bans");
			KickClient(client, "You are showing as having game bans on Steamid.eu.");
			}	
			
			if(g_iPlayerInfo[client][PlayerInfo_Steamrepbanned] == false && g_kick_steamrep_banned.BoolValue == true)
			{
			//PrintToChatAll("\x01 \x07SteamID.eu Should be kicked Game Bans");
			KickClient(client, "You are showing as having a SteamRep ban on Steamid.eu.");
			}
		}
		else if (StrEqual(sBuffer, "request_stats"))
		{
			g_iPlayerInfo[client][PlayerInfo_GenerationTime] = hKeyValues.GetFloat("request_time", 0.0);
		}
		else if (StrEqual(sBuffer, "Steamid_data"))
		{
			// The Steamid_data section has it's own error key.
			hKeyValues.GetString("error", sBuffer, sizeof(sBuffer), "");
			if (sBuffer[0])
			{
				delete hKeyValues;
				return;
			}

			// Now we know more detailed data is available.
			g_iPlayerInfo[client][PlayerInfo_SIDAvailable] = true;

			// Gather other SteamID.eu data.
			g_iPlayerInfo[client][PlayerInfo_Games] = hKeyValues.GetNum("game_count", -1);
			g_iPlayerInfo[client][PlayerInfo_PreviousNames] = hKeyValues.GetNum("name_history_count", -1);
			g_iPlayerInfo[client][PlayerInfo_SteamIDRating] = hKeyValues.GetNum("steamid_rating", -1);
			g_iPlayerInfo[client][PlayerInfo_PreviousFriends] = hKeyValues.GetNum("friend_history_count", -1);
		}
	} while (hKeyValues.GotoNextKey());

		// Cleanup.
	delete hKeyValues;
}

/**
 * Timer callbacks.
 */
public Action Timer_FetchAgain(Handle timer, int serial)
{
	// The client can disconnect during this async call.
	int client = GetClientFromSerial(serial);
	if (!g_bSteamWorks || !client)
		return Plugin_Stop;

	FetchSteamInfo(client);
	return Plugin_Stop;
}

/**
 * ConVar changed callbacks.
 */
public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	strcopy(g_sAPIKey, sizeof(g_sAPIKey), newValue);
}

/**
 * Menu & Panel handlers.
 */
public int MenuHandler_Main(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
	}
	else if(action == MenuAction_Cancel)
	{
		g_iViewing[param1] = 0;
	}
	else if (action == MenuAction_Select)
	{
		char sInfo[2];
		if (!menu.GetItem(param2, sInfo, sizeof(sInfo)))
			return;

		int iTarget = GetClientFromSerial(g_iViewing[param1]);
		if (!iTarget)
		{
			g_iViewing[param1] = 0;
			PrintToChat(param1, "\x04 \x03[SteamID]\x01 \x01 The player has disconnected.");
			return;
		}

		// Sub-menus.
		switch (StringToInt(sInfo))
		{
			case 0:
				OpenSteamPanel(param1, iTarget);
			case 1:
				OpenSIDPanel(param1, iTarget);
			case 2:
				OpenLinksMenu(param1, iTarget);
		}
	}
}

public int MenuHandler_Links(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
	}
	else if (action == MenuAction_Cancel)
	{
		// ExitBack support.
		if (param2 == MenuCancel_ExitBack)
		{
			int iTarget = GetClientFromSerial(g_iViewing[param1]);
			if (!iTarget)
			{
				g_iViewing[param1] = 0;
				PrintToChat(param1, "\x04 \x03[SteamID]\x01 \x01 The player has disconnected.");
				return;
			}
			else
			{
				OpenMainMenu(param1, iTarget);
			}
		}
		else
		{
			g_iViewing[param1] = 0;
		}
	}
	else if (action == MenuAction_Select)
	{
		char sInfo[64];
		if (!menu.GetItem(param2, sInfo, sizeof(sInfo)))
			return;

		int iTarget = GetClientFromSerial(g_iViewing[param1]);
		if (!iTarget)
		{
			g_iViewing[param1] = 0;
			PrintToChat(param1, "\x04 \x03[SteamID]\x01 \x01 The player has disconnected.");
			return;
		}

		// If the target is still connected re-open this menu.
		if (GetEngineVersion() != Engine_CSGO)
			ShowMOTDPanel(param1, "SteamID.eu Plugin", sInfo, MOTDPANEL_TYPE_URL);
		else
			PrintURLToConsole(param1, sInfo);

		// If the target is still connected re-open this menu.
		OpenLinksMenu(param1, iTarget);
	}
}

public int PanelHandler_Back(Menu menu, MenuAction action, int param1, int param2)
{
	/**
	 * Credit to Peace-Maker, code from TWTimer.
	 * The code below allows a panel to mimic a menu.
	 */
	if (action == MenuAction_Cancel)
	{
		g_iViewing[param1] = 0;
	}
	else if (action == MenuAction_Select)
	{
		int iExitPosition = GetMaxPageItems();
		int iBackPosition = (iExitPosition - 2);

		if (param2 == iBackPosition)
		{
			int iTarget = GetClientFromSerial(g_iViewing[param1]);
			if (!iTarget)
			{
				g_iViewing[param1] = 0;
				PrintToChat(param1, "\x04 \x03[SteamID]\x01 \x01 The player has disconnected.");
			}
			else
			{
				OpenMainMenu(param1, iTarget);
			}
		}
		else if (param2 == iExitPosition)
		{
			g_iViewing[param1] = 0;
		}
	}
}

/**
 * Helpers.
 */
void FetchSteamInfo(int client)
{
	char sAuth[32];
	if (!GetClientAuthId(client, AuthId_SteamID64, sAuth, sizeof(sAuth)))
		return;

	// SteamWorks is only in the old syntax, eww.
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, "https://api.steamid.eu/plugin.php");

	
	decl String:server_port[10];
 
	new Handle:cvar_port = FindConVar("hostport");
	GetConVarString(cvar_port, server_port, sizeof(server_port));
	CloseHandle(cvar_port);

	
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "api", g_sAPIKey);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "player", sAuth);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "serverport", server_port);
	

	// The second and third params are for headers received & data received.
		
	SteamWorks_SetHTTPCallbacks(hRequest, Callback_RequestCompleted);
	SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientSerial(client));
	SteamWorks_SendHTTPRequest(hRequest);

	}

void OpenMainMenu(int client, int target)
{

	Menu hMenu = new Menu(MenuHandler_Main);
	new String:nickname[36];
	GetClientName(target,    nickname,    sizeof(nickname));
	hMenu.SetTitle("%N | Powered by SteamID.eu ", target);
	hMenu.AddItem("0", "Steam Info");

	if (g_iPlayerInfo[target][PlayerInfo_SIDAvailable])
		hMenu.AddItem("1", "SteamID.eu Info");
	else
		hMenu.AddItem("1", "SteamID.eu Info", ITEMDRAW_DISABLED);

	// Menu's don't use VFormat... why!
	char sBuffer[64];
	FormatEx(sBuffer, sizeof(sBuffer), "Player Links\n Request time: %.3f", g_iPlayerInfo[target][PlayerInfo_GenerationTime]);
	hMenu.AddItem("2", sBuffer);

	hMenu.Display(client, MENU_TIME_FOREVER);
	g_iViewing[client] = GetClientSerial(target);
}

void OpenSteamPanel(int client, int target)
{

	// Panels don't even support VFormat in the title...
	char sBuffer[MAX_NAME_LENGTH + 32];
	Panel hPanel = new Panel();
	
	new String:nickname[36];
	GetClientName(target,    nickname,    sizeof(nickname));

	FormatEx(sBuffer, sizeof(sBuffer), "%N | Powered by SteamID.eu\n ", target);
	hPanel.SetTitle(sBuffer);
	
	FormatEx(sBuffer, sizeof(sBuffer), "Name: %s", nickname);
	hPanel.DrawText(sBuffer);
	FormatEx(sBuffer, sizeof(sBuffer), "SteamID: %s", g_iPlayerInfo[target][PlayerInfo_SteamID]);
	hPanel.DrawText(sBuffer);
	FormatEx(sBuffer, sizeof(sBuffer), "Steam3ID: %s", g_iPlayerInfo[target][PlayerInfo_Steam3ID]);
	hPanel.DrawText(sBuffer);
	FormatEx(sBuffer, sizeof(sBuffer), "Steam64ID: %s\n ", g_iPlayerInfo[target][PlayerInfo_Steam64ID]);
	hPanel.DrawText(sBuffer);
	PrintToChat(client, "\x04 \x03[SteamID]\x01 \x01 See console for details.");

	PrintToConsole(client, "=====================================================\n");
	PrintToConsole(client, "User information: %s",nickname);
	PrintToConsole(client, "SteamID: %s" , g_iPlayerInfo[target][PlayerInfo_SteamID]);
	PrintToConsole(client, "Steam3ID: %s" , g_iPlayerInfo[target][PlayerInfo_Steam3ID]);
	PrintToConsole(client, "Steam64ID: %s" , g_iPlayerInfo[target][PlayerInfo_Steam64ID]);
	PrintToConsole(client, "URL: https://SteamID.eu/profile/%s" , g_iPlayerInfo[target][PlayerInfo_Steam64ID]);
	PrintToConsole(client, "=====================================================");
	
	
	FormatEx(sBuffer, sizeof(sBuffer), "%d VAC ban%s on record", g_iPlayerInfo[target][PlayerInfo_VACBans], g_iPlayerInfo[target][PlayerInfo_VACBans] == 1 ? "" : "s");
	hPanel.DrawText(sBuffer);
	FormatEx(sBuffer, sizeof(sBuffer), "%d game ban%s on record", g_iPlayerInfo[target][PlayerInfo_GameBans], g_iPlayerInfo[target][PlayerInfo_GameBans] == 1 ? "" : "s");
	hPanel.DrawText(sBuffer);
	FormatEx(sBuffer, sizeof(sBuffer), "[%s] trade status", g_iPlayerInfo[target][PlayerInfo_TradeBan] ? "Banned" : "Clean");
	hPanel.DrawText(sBuffer);
	FormatEx(sBuffer, sizeof(sBuffer), "[%s] community status ", g_iPlayerInfo[target][PlayerInfo_CommunityBan] ? "Banned" : "Clean");
	hPanel.DrawText(sBuffer);
	FormatEx(sBuffer, sizeof(sBuffer), "[%s] SteamID.eu status ", g_iPlayerInfo[target][PlayerInfo_SidBan] ? "Banned" : "Clean");
	hPanel.DrawText(sBuffer);
	FormatEx(sBuffer, sizeof(sBuffer), "[%s] SteamRep.com status\n ", g_iPlayerInfo[target][PlayerInfo_Steamrepbanned] ? "Banned" : "Clean");
	hPanel.DrawText(sBuffer);

	/**
	 * Credit to Peace-Maker, code from TWTimer.
	 * The code below allows a panel to mimic a menu.
	 */
	hPanel.CurrentKey = (GetMaxPageItems(hPanel.Style) - 2);
	FormatEx(sBuffer, sizeof(sBuffer), "%T\n ", "Back", client);
	hPanel.DrawItem(sBuffer);

	hPanel.CurrentKey = GetMaxPageItems(hPanel.Style);
	FormatEx(sBuffer, sizeof(sBuffer), "%T", "Exit", client);
	hPanel.DrawItem(sBuffer);

	// Panels have to be deleted here as well as in the callback.
	hPanel.Send(client, PanelHandler_Back, MENU_TIME_FOREVER);
	delete hPanel;
}

void OpenSIDPanel(int client, int target)
{
	char sBuffer[MAX_NAME_LENGTH + 32];
	Panel hPanel = new Panel();
	new String:nickname[36];
	GetClientName(target,    nickname,    sizeof(nickname));
	FormatEx(sBuffer, sizeof(sBuffer), "%N | Powered by SteamID.eu\n ", target);
	hPanel.SetTitle(sBuffer);
	FormatEx(sBuffer, sizeof(sBuffer), "SteamID.eu rating: %d", g_iPlayerInfo[target][PlayerInfo_SteamIDRating]);
	hPanel.DrawText(sBuffer);
	FormatEx(sBuffer, sizeof(sBuffer), "Previous names: %d", g_iPlayerInfo[target][PlayerInfo_PreviousNames]);
	hPanel.DrawText(sBuffer);
	FormatEx(sBuffer, sizeof(sBuffer), "Previous friends: %d", g_iPlayerInfo[target][PlayerInfo_PreviousFriends]);
	hPanel.DrawText(sBuffer);


	int iBackPosition = (GetMaxPageItems(hPanel.Style) - 2);


	hPanel.CurrentKey = iBackPosition;
	FormatEx(sBuffer, sizeof(sBuffer), "%T", "Back", client);
	hPanel.DrawItem(sBuffer);
	hPanel.DrawText(" ");

	hPanel.CurrentKey = GetMaxPageItems(hPanel.Style);
	FormatEx(sBuffer, sizeof(sBuffer), "%T", "Exit", client);
	hPanel.DrawItem(sBuffer);

	hPanel.Send(client, PanelHandler_Back, MENU_TIME_FOREVER);
	delete hPanel;
}

void OpenLinksMenu(int client, int target)
{

	
	Menu hMenu = new Menu(MenuHandler_Links);
	hMenu.SetTitle("%N | Powered by SteamID.eu\n ", target);

	char sBuffer[64];

	FormatEx(sBuffer, sizeof(sBuffer), "https://steamcommunity.com/profiles/%s", g_iPlayerInfo[target][PlayerInfo_Steam64ID]);
	hMenu.AddItem(sBuffer, "Steam community profile\n ");
	FormatEx(sBuffer, sizeof(sBuffer), "https://steamid.eu/profile/%s", g_iPlayerInfo[target][PlayerInfo_Steam64ID]);
	hMenu.AddItem(sBuffer, "SteamID.eu profile");
	FormatEx(sBuffer, sizeof(sBuffer), "https://steamfriends.us/friend/%s", g_iPlayerInfo[target][PlayerInfo_Steam64ID]);
	hMenu.AddItem(sBuffer, "SteamFriends.us profile");
	FormatEx(sBuffer, sizeof(sBuffer), "https://steamarchive.net/profiles/%s", g_iPlayerInfo[target][PlayerInfo_Steam64ID]);
	hMenu.AddItem(sBuffer, "SteamArchive.net profile");

	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

void PrintURLToConsole(int client, char[] url)
{
	PrintToChat(client, "\x04 \x03[SteamID]\x01 \x01 See console for link.");
	PrintToChat(client, "\x04 \x03[SteamID]\x01 \x01 %s",url);

	// Clear the console a little.
	PrintToConsole(client, "\n\n\n\n\n\n\n\n\n\n");

	// Show the URL with some formatting.
	PrintToConsole(client, "=====================================================\n");
	PrintToConsole(client, "%s\n", url);
	PrintToConsole(client, "=====================================================");
}

