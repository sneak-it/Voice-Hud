//
//Credits to Franc1sco for original SVoice plugin.
//

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <voiceannounce_ex>

#pragma newdecls required

//Bit Macros
#define SetBit(%1,%2)      (%1[%2>>5] |= (1<<(%2 & 31)))
#define ClearBit(%1,%2)    (%1[%2>>5] &= ~(1<<(%2 & 31)))
#define CheckBit(%1,%2)    (%1[%2>>5] & (1<<(%2 & 31)))

//Global Handles & Variables
Handle g_hHudCookie;
Handle g_tHudTimer;
Handle speakTimer[MAXPLAYERS + 1];
Handle g_hHudSync;
char g_sMessage[1024];
bool noneSpeaking;
bool disableHud;
int g_iEnabled[(MAXPLAYERS >> 5) + 1];
int g_iSpeaking[(MAXPLAYERS >> 5) + 1];
int g_iSpeakingPre[(MAXPLAYERS >> 5) + 1];

ArrayList g_alClients;

#define PLUGIN_NAME 	"Voice Hud"
#define PLUGIN_VERSION	 "1.0"

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = "Agent Wesker",
	description = "Hud to track players mic usage. Credits to Franc1sco for original SVoice plugin.",
	version = PLUGIN_VERSION,
	url = "http://steam-gamers.net/"
};

public void OnPluginStart() 
{
	CreateConVar("sm_voicehud_version", PLUGIN_VERSION, "", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	RegAdminCmd("sm_voicehud", cmdEnableHud, ADMFLAG_GENERIC);
	
	if (g_alClients == null)
		g_alClients = new ArrayList(1, 0);
	
	if (g_hHudSync == null)
		g_hHudSync = CreateHudSynchronizer();
		
	if (g_tHudTimer == null)
		g_tHudTimer = CreateTimer(0.1, Timer_Hud, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	
	if (g_hHudCookie == null)
		g_hHudCookie = RegClientCookie("voicehud_toggle", "Voice Hud Toggle Pref", CookieAccess_Protected);
	
	noneSpeaking = true;
	disableHud = true;
	
	//Late load cookies
	for (int j = 1; j <= MaxClients; j++)
	{
		if (AreClientCookiesCached(j))
		{
			OnClientCookiesCached(j);
		}
	}
}

public void OnMapEnd()
{
	if (g_tHudTimer != null)
	{
		g_tHudTimer = null;
	}
}

public void OnMapStart()
{	
	if (g_tHudTimer == null)
		g_tHudTimer = CreateTimer(0.1, Timer_Hud, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		
	g_sMessage = "";
	checkSpeakers(true);
	checkHudUsers(true);
}

public Action Timer_Hud(Handle timer)
{
	if (!noneSpeaking && !disableHud)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (CheckBit(g_iEnabled, i))
			{
				if (IsClientInGame(i))
				{
					SetHudTextParams(0.08, 0.4, 1.0, 47, 206, 58, 255, 0, 0.0, 0.0, 0.0);
					ShowSyncHudText(i, g_hHudSync, "%s", g_sMessage);
				}
			}
		}
	}
	return Plugin_Continue;
}

public void OnClientCookiesCached(int client)
{
	if (IsClientInGame(client))
	{
		char sCookieValue[1];
		GetClientCookie(client, g_hHudCookie, sCookieValue, sizeof(sCookieValue));
		if (sCookieValue[0])
		{
			if (CheckCommandAccess(client, "sm_voicehud", ADMFLAG_GENERIC, false))
			{
				//Has perm & saved cookie
				SetBit(g_iEnabled, client);
				disableHud = false;
				CreateTimer(15.0, ClientHudNotice, client);
			} else
			{
				//No longer has admin
				SetClientCookie(client, g_hHudCookie, "");
			}			
		}
	}
}

public Action ClientHudNotice(Handle timer, int client)
{
	if (IsClientInGame(client) && CheckBit(g_iEnabled, client))
	{
		PrintToChat(client, "[Voice Hud] The Voice Hud is currently enabled, type !svoice to disable.");
	}
}

public void OnClientPostAdminCheck(int client)
{
	if (speakTimer[client] != null)
	{
		KillTimer(speakTimer[client]);
		speakTimer[client] = null;
		ClearBit(g_iSpeaking, client);
		checkSpeakers();
	}
}
public void OnClientDisconnect(int client)
{
	if (CheckBit(g_iEnabled, client))
	{
		ClearBit(g_iEnabled, client);
		checkHudUsers();
	}
}

public void OnClientSpeakingEx(int client)
{
	//Someone is talking now	
	if (!CheckBit(g_iSpeakingPre, client))
	{
		//If user is an admin, get out of here
		if (GetUserAdmin(client) != INVALID_ADMIN_ID)
		{
			return;
		}
		noneSpeaking = false;
		if (speakTimer[client] != null)
		{
			KillTimer(speakTimer[client]);
			speakTimer[client] = null;
		}
		
		//If the new speaker is already in the array, don't show him twice
		int sClientIndex = g_alClients.FindValue(client);
		if (sClientIndex > -1)
		{
			g_alClients.Erase(sClientIndex);
		}
		
		//Push the new speaker to the top of the array
		g_alClients.Push(client);
		char steamID[32];
		if (!GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID)))
			steamID = "Not Authorized";
		int userID = GetClientUserId(client);
		if (!disableHud)
		{
			for (int j = 1; j <= MaxClients; j++)
			{
				if (CheckBit(g_iEnabled, j))
				{
					if (IsClientInGame(j))
					{
						PrintToConsole(j, "[Voice Hud] %N started speaking, User ID: %i Steam ID: %s", client, userID, steamID);
					}
				}
			}
		}
		
		//Keep the array the size of the Hud (5 total)
		if (g_alClients.Length > 4)
		{
			g_alClients.Erase(0);
		}
		
		//Reset the display
		char sName[20];
		g_sMessage = "";
		for (int i = g_alClients.Length - 1; i >= 0; i--)
		{
			int thisClient = g_alClients.Get(i);
			if (IsClientInGame(thisClient))
			{
				//Line break is \n
				//Format is Name (trimmed), Client #
				Format(sName, sizeof(sName), "%N", thisClient); //Get the Clients IGN and trim it to 20 characters
				userID = GetClientUserId(thisClient);
				if (!GetClientAuthId(thisClient, AuthId_Steam2, steamID, sizeof(steamID)))
					steamID = "Not Authorized";
				Format(g_sMessage, sizeof(g_sMessage), "%s#%i | %s | %s\n", g_sMessage, userID, sName, steamID); //Concat the previous msg, user ID, current name, and newline
			} else
			{
				g_alClients.Erase(i);
			}
		}
		
		SetBit(g_iSpeaking, client);
		SetBit(g_iSpeakingPre, client);
	}
}

public void OnClientSpeakingEnd(int client)
{
	ClearBit(g_iSpeakingPre, client);
	if (speakTimer[client] != null)
	{
		KillTimer(speakTimer[client]);
		speakTimer[client] = null;
	}
	//After finished speaking, keep the Hud up for 15 seconds
	speakTimer[client] = CreateTimer(15.0, stoppedTimer, client);
}

public Action stoppedTimer(Handle timer, any client)
{
	//Remove this clients timer & bit
	speakTimer[client] = null;
	ClearBit(g_iSpeaking, client);
	//Check to see if others are still speaking
	checkSpeakers();
}

stock static void checkSpeakers(bool clear = false)
{
	noneSpeaking = true;
	for (int i = 0; i < sizeof(g_iSpeaking); i++)
	{
		if (g_iSpeaking[i] || g_iSpeakingPre[i])
		{
			if (clear)
			{
				g_iSpeaking[i] = 0;
				g_iSpeakingPre[i] = 0;
			} else 
			{
				noneSpeaking = false;
			}
		}
	}
}
stock static void checkHudUsers(bool clear = false)
{
	disableHud = true;
	for (int i = 0; i < sizeof(g_iEnabled); i++)
	{
		if (g_iEnabled[i])
		{
			if (clear)
			{
				g_iEnabled[i] = 0;
			} else
			{
				disableHud = false;
			}
		}
	}
}

public Action cmdEnableHud(int client, any args)
{
	if (CheckBit(g_iEnabled, client))
	{
		ClearBit(g_iEnabled, client);
		checkHudUsers();
		PrintToChat(client, "[Voice Hud] Disabled the Hud");
		SetClientCookie(client, g_hHudCookie, "");
	} else
	{
		SetBit(g_iEnabled, client);
		disableHud = false;
		PrintToChat(client, "[Voice Hud] Enabled the Hud");
		SetClientCookie(client, g_hHudCookie, "1");
	}
	
	return Plugin_Handled;
}