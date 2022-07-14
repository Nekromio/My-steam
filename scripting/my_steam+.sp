#pragma semicolon 1

#pragma dynamic 131072 

#include <SteamWorks>
#include <morecolors>

#pragma newdecls required

Menu
	hMenu;

bool
	bEnable;
	
int
	iSteamStstus[MAXPLAYERS+1][5],
	iSteam[MAXPLAYERS+1];

char
	sFile[PLATFORM_MAX_PATH],
	sApiKey[PLATFORM_MAX_PATH];

public Plugin myinfo =
{
	name = "My steam/Мой стим",
	author = "by Nek.'a 2x2 | ggwp.site ",
	description = "Подробноя инф. о игроках",
	version = "1.0",
	url = "https://ggwp.site/"
}

public void OnPluginStart() 
{
	ConVar cvar;
	cvar = CreateConVar("sm_mysteam_enable", "1", "Включить/Выключить плагин", _, true, 0.0, true, 1.0);
	cvar.AddChangeHook(CVarChanged_Enable);
	bEnable = cvar.BoolValue;
	
	cvar = CreateConVar("sm_mysteam_key", "ключ api key", "Ваш личный ключ api key подробнее тут(https://steamcommunity.com/dev/apikey)");
	GetConVarString(cvar, sApiKey, sizeof(sApiKey));
	HookConVarChange(cvar, OnConVarChanges_ApiKey);
	
	HookEvent("player_activate", Event_Activate, EventHookMode_Pre);
	
	BuildPath(Path_SM, sFile, sizeof(sFile), "logs/my_steam.log");
	
	RegConsoleCmd("sm_st", CmdMySteam);
	//RegConsoleCmd("sm_test", CmdMySteam2);
	RegAdminCmd("sm_stall", CmdMySteamAll, ADMFLAG_ROOT, "Вывод списком Steam ID всех игроков");
	
	RegConsoleCmd("sm_stm", CmdMySteamMenu);
	
	AutoExecConfig(true, "my_steam");
	
	for(int i = 1; i <= MaxClients; i++) if(IsClientInGame(i) && !IsFakeClient(i)) CheckClient(i);
}

public void CVarChanged_Enable(ConVar cvar, const char[] oldValue, const char[] newValue)
{
	bEnable	= cvar.BoolValue;
}

public void OnConVarChanges_ApiKey(ConVar cvar, const char[] oldValue, const char[] newValue)
{
	GetConVarString(cvar, sApiKey, sizeof(sApiKey));
}

void CheckClient(int client)
{
	if(!bEnable)
		return;
		
	if(IsFakeClient(client) || !IsClientInGame(client))
		return;

	char sSteam[32];
	GetClientAuthId(client, AuthId_SteamID64, sSteam, sizeof(sSteam));
	SteamWorksConnectToApi(client, sSteam);
}

public Action Event_Activate(Handle hEvent, const char[] name, bool dontBroadcast)
{
	if(!bEnable)
		return;
		
	int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	if(IsFakeClient(client) || !IsClientInGame(client))
		return;
	
	char sSteam[32];
	GetClientAuthId(client, AuthId_SteamID64, sSteam, sizeof(sSteam));
	SteamWorksConnectToApi(client, sSteam);
}

public void OnClientConnected(int client)
{
	iSteamStstus[client] = {0, 0, 0, 0, 0};
	iSteam[client] = 0;
}

//Проверяем профиль стима
void SteamWorksConnectToApi(int client, const char[] steamID)
{
	DataPack hPack = new DataPack();
	hPack.WriteCell(client);
	hPack.WriteString(steamID);

	char url[128];
	Format(url, sizeof(url), "https://api.steampowered.com/ISteamUser/GetPlayerBans/v1/?key=%s&steamids=%s", sApiKey, steamID);

	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);
	SteamWorks_SetHTTPCallbacks(hRequest, OnSteamWorksHTTPComplete);
	SteamWorks_SetHTTPRequestContextValue(hRequest, hPack);
	SteamWorks_SendHTTPRequest(hRequest);
}

//Процес коннекта
public int OnSteamWorksHTTPComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, DataPack hPack)
{
	if (bRequestSuccessful && eStatusCode == k_EHTTPStatusCode200OK)
		SteamWorks_GetHTTPResponseBodyCallback(hRequest, OnSteamWorksHTTPBodyCallback, hPack);
	else
		if (bRequestSuccessful)
			LogError("HTTP error: %d (using SteamWorks)", eStatusCode);
		else LogError("SteamWorks error", LANG_SERVER);
}

//Сама проверка после подключения к сайту
public int OnSteamWorksHTTPBodyCallback(const char[] sData, DataPack hPack)
{
	hPack.Reset();
	int client = hPack.ReadCell();

	UpdateClientStatus(client, sData);

	delete hPack;
}

/**
 * Update the client data based on the response data.
 *
 * @param client   The client index
 * @param response The response from the server
 */
void UpdateClientStatus(int client, const char[] response)
{
	iSteamStstus[client] = {0, 0, 0, 0, 0};

	char responseData[1024];
	strcopy(responseData, sizeof(responseData), response);

	ReplaceString(responseData, sizeof(responseData), " ", "");
	ReplaceString(responseData, sizeof(responseData), "\t", "");
	ReplaceString(responseData, sizeof(responseData), "\n", "");
	ReplaceString(responseData, sizeof(responseData), "\r", "");
	ReplaceString(responseData, sizeof(responseData), "\"", "");
	ReplaceString(responseData, sizeof(responseData), "{players:[{", "");
	ReplaceString(responseData, sizeof(responseData), "}]}", "");
	
	if(StrEqual(response, "{\"players\":[]}"))
		iSteam[client] = 1;		//Клиент является пиратом
	else
		iSteam[client] = 2;		//Клиент является стим игроком
	
	char parts[16][512];
	int count = ExplodeString(responseData, ",", parts, sizeof(parts), sizeof(parts[]));
	char kv[2][64];

	for (int i = 0; i < count; i++)
	{
		if (ExplodeString(parts[i], ":", kv, sizeof(kv), sizeof(kv[])) < 2)
		{
			continue;
		}

		if (StrEqual(kv[0], "NumberOfVACBans"))		//Есть ли у игрока вак бан
		{
			iSteamStstus[client][0] = StringToInt(kv[1]);
		}
		else if (StrEqual(kv[0], "DaysSinceLastBan"))		//Сколько прошло днеё с последней блокировки?
		{
			iSteamStstus[client][1] = StringToInt(kv[1]);
		}
		else if (StrEqual(kv[0], "NumberOfGameBans"))	//Количество запретов
		{
			iSteamStstus[client][2] = StringToInt(kv[1]);
		}
		else if (StrEqual(kv[0], "CommunityBanned"))	//Баны сообществ
		{
			iSteamStstus[client][3] = StrEqual(kv[1], "true", false) ? 1 : 0;
		}
		else if (StrEqual(kv[0], "EconomyBan"))		//Экономический запрет
		{
			if (StrEqual(kv[1], "probation", false))	//Испытательный срок
			{
				iSteamStstus[client][4] = 1;
			}
			else if (StrEqual(kv[1], "banned", false))		//Запрещен
			{
				iSteamStstus[client][4] = 2;
			}
		}
	}
}

public Action CmdMySteamMenu(int client, any args)
{
	if(!bEnable)
		return Plugin_Continue;
		
	if(!client)
		return Plugin_Continue;
	
	hMenu = new Menu(MenuCreate);
	char szTitle[128] = "Список игроков";
	hMenu.GetTitle(szTitle, sizeof(szTitle));
	for(int i = 1; i <= MaxClients; i++) if(IsClientInGame(i) && !IsFakeClient(i))
	{
		char sName[MAX_NAME_LENGTH];
		GetClientName(i, sName, sizeof(sName));
		hMenu.AddItem(sName, sName);
	}
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	return Plugin_Changed;
}

public int MenuCreate(Menu hMenuLocal, MenuAction action, int client, int iItem)
{
	if(action == MenuAction_Select)
	{
		int iClientInfo;
		// Получаем только название и описание
		char szInfo[128], szTitle[128];
		hMenu.GetItem(iItem, szInfo, sizeof(szInfo), _, szTitle, sizeof(szTitle));
		for(int i = 1; i <= MaxClients; i++) if(IsClientInGame(i) && !IsFakeClient(i))
		{
			char sName[MAX_NAME_LENGTH];
			GetClientName(i, sName, sizeof(sName));
			if(!strcmp(sName, szInfo))
			{
				iClientInfo = i;
			}
		}
		
		char sSteam[3][32];
		GetClientAuthId(iClientInfo, AuthId_Steam2, sSteam[0], sizeof(sSteam[]));
		GetClientAuthId(iClientInfo, AuthId_Steam3, sSteam[1], sizeof(sSteam[]));
		GetClientAuthId(iClientInfo, AuthId_SteamID64, sSteam[2], sizeof(sSteam[]));
		
		char url[128];
		Format(url, sizeof(url), "https://steamcommunity.com/profiles/%s/", sSteam[2]);
		ShowMOTDPanel(client, "Меню с подсказкой", url, MOTDPANEL_TYPE_URL);
		PrintToChat(client, "Был выбран игрок [%N]\n-> Steam2 = [%s]\n-> Steam3 = %s\n-> Steam64 = [%s]", iClientInfo, sSteam[0], sSteam[1], sSteam[2]);
	}
	else if(action == MenuAction_End)
	{
		//hMenuLocal.Close();
		delete hMenu;
	}
}

public Action CmdMySteam(int client, any args)
{
	if(!bEnable)
		return Plugin_Continue;
		
	if(!client)
		return Plugin_Continue;
		
	int iAll = 1;
	InfoPlayers(client, iAll);

	return Plugin_Changed;
}

void InfoPlayers(int client, int iAll)
{
	char sSteam[3][32];
	GetClientAuthId(client, AuthId_Steam2, sSteam[0], sizeof(sSteam[]));
	GetClientAuthId(client, AuthId_Steam3, sSteam[1], sizeof(sSteam[]));
	GetClientAuthId(client, AuthId_SteamID64, sSteam[2], sizeof(sSteam[]));
	
	SteamWorksConnectToApi(client, sSteam[2]);
	
	if(iAll < 2)
	{
		CPrintToChat(client, "▼====Ваш Стим====▼");
		CPrintToChat(client, "Ник [%N]", client);
		CPrintToChat(client, "Steam2 = %s", sSteam[0]);
		CPrintToChat(client, "Steam3 = %s", sSteam[1]);
		CPrintToChat(client, "Steam = %s", sSteam[2]);
		if(iSteam[client] == 2)
		{
			CPrintToChat(client, "Игрок \x07ff0000[\x0733cc33Steam\x07ff0000]", sSteam[2]);
			if(!iSteamStstus[client][0])
				CPrintToChat(client, "VAC Бан - [не обнаружен]", iSteamStstus[client][0]);
			else
				CPrintToChat(client, "VAC Бан - [обнаружен] | Дней от блокировки [%d]", iSteamStstus[client][1]);
		}
		else if(iSteam[client] == 1)
			CPrintToChat(client, "Игрок \x07FF0000\x0733cc33[\x07ff0000No-Steam\x0733cc33]", sSteam[2]);
		else if(iSteam[client] == 0)
			CPrintToChat(client, "Игрок ещё не прошёл проверку Steam", sSteam[2]);
		CPrintToChat(client, "▲====Ваш Стим====▲");
	}
	
	if(iAll < 2)
		return;
	
	PrintToConsole(0, "▼==== Информация ====▼");
	PrintToConsole(0, "Ник [%N]", client);
	PrintToConsole(0, "Steam2 = %s", sSteam[0]);
	PrintToConsole(0, "Steam3 = %s", sSteam[1]);
	PrintToConsole(0, "Steam = %s", sSteam[2]);
	if(iSteam[client] == 2)
	{
		PrintToConsole(0, "Игрок [Steam]", sSteam[2]);
		if(!iSteamStstus[0][0])
			PrintToConsole(0, "VAC Бан - [не обнаружен]", iSteamStstus[client][0]);
		else
			PrintToConsole(0, "VAC Бан - [обнаружен] | Дней от блокировки [%d]", iSteamStstus[client][1]);
	}
	else if(iSteam[client] == 1)
		PrintToConsole(0, "Игрок [No-Steam]", sSteam[2]);
	else if(iSteam[client] == 0)
		PrintToConsole(0, "Игрок ещё не прошёл проверку Steam", sSteam[2]);
	PrintToConsole(0, "▲==== Информация ====▲");
	

	LogToFile(sFile, " ", client);
	LogToFile(sFile, "▼==== Информация ====▼");
	LogToFile(sFile, "Ник [%N]", client);
	LogToFile(sFile, "Steam2 = %s", sSteam[0]);
	LogToFile(sFile, "Steam3 = %s", sSteam[1]);
	LogToFile(sFile, "Steam = %s", sSteam[2]);
	if(iSteam[client] == 2)
	{
		LogToFile(sFile, "Игрок [Steam]");
		if(!iSteamStstus[0][0])
			LogToFile(sFile, "VAC Бан - [не обнаружен]", iSteamStstus[client][0]);
		else
			LogToFile(sFile, "VAC Бан - [обнаружен] | Дней от блокировки [%d]", iSteamStstus[client][1]);
	}
	else if(iSteam[client] == 1)
		LogToFile(sFile, "Игрок [No-Steam]");
	else if(iSteam[client] == 0)
		LogToFile(sFile, "Игрок ещё не прошёл проверку Steam", iSteam[client]);
	LogToFile(sFile, "▲==== Информация ====▲");
	LogToFile(sFile, " ", client);
}

public Action CmdMySteamAll(int client, any args)
{
	if(!bEnable)
		return Plugin_Continue;
		
	for(int i = 1, iAll = 2; i <= MaxClients; i++) if(IsClientInGame(i) && !IsFakeClient(i))
		InfoPlayers(i, iAll);

	return Plugin_Changed;
}

