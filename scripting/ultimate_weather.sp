/*
Special thanks to:
http://www.custommapmakers.org/skyboxes.php - for skyboxes
https://www.quake3world.com/forum/viewtopic.php?t=9242 - for skyboxes
*/

#include <sourcemod>
#include <sdktools>
#include <vector>

#pragma semicolon				1
#pragma newdecls				required

public Plugin myinfo = 
{
	name = "Ultimate Weather",
	author = "Vasto_Lorde",
	description = "Adds weather to maps (precipitation, fog_controller, skybox)",
	version = "1.0",
	url = "https://go-code.pl/"
};

#define KEYVALUES_MAPS			"addons/sourcemod/configs/cs-plugin.com/customweather/maps.cfg"
#define KEYVALUES_CFG			"addons/sourcemod/configs/cs-plugin.com/customweather/configurations.cfg"
#define KEYVALUES_SKYBOX		"addons/sourcemod/configs/cs-plugin.com/customweather/skyboxes.cfg"

#define MAX_MAPS				256
#define MAX_CONFIG				512
#define MAX_SKYBOXES			128

#define LOG_FILE				"addons/sourcemod/logs/customweather.log"

//Fog
#define MAX_FOG_PROP			7
int g_iMainFogEntity = -1;

//Rain
#define MAX_RAIN_PROP			7
int g_iMainRainEntity = -1;
float g_fRainMinRange[3], g_fRainMaxRange[3], g_fRainOrigin[3];
char g_cRainModel[128];

//All arrays
char g_fAllPropertyNames[MAX_FOG_PROP+MAX_RAIN_PROP][] = 
{
	"Fog: On",
	"Fog: Start",
	"Fog: End",
	"Fog: Density",
	"Fog: Color Red",
	"Fog: Color Green",
	"Fog: Color Blue",
	"Rain: On",
	"Rain: Type",
	"Rain: Density",
	"Rain: Color Red",
	"Rain: Color Green",
	"Rain: Color Blue",
	"Rain: Origin Height"
};

char g_cAllMapsNames[MAX_MAPS][64];
char g_cAllMapsConfig[MAX_MAPS][64];
int g_iAllMapsCfgID[MAX_MAPS];
int g_iAllMapsNumber = 0;

char g_cAllConfigNames[MAX_CONFIG][64];
float g_fAllConfigVariables[MAX_CONFIG][MAX_FOG_PROP+MAX_RAIN_PROP];
char g_cAllConfigSkyboxes[MAX_CONFIG][64];
int g_iAllConfigNumber = 0;

char g_cAllSkyboxesNames[MAX_SKYBOXES][64];
char g_cAllSkyboxesPaths[MAX_SKYBOXES][128];
int g_iAllSkyboxesNumber = 0;

int g_iCurrentConfigurationID = 0;
int g_iMenuCurrentMap = 0;
int g_iMenuCurrentConfig = 0;
int g_iMenuCurrentProperty = 0;
float g_fMenuCurrentChangeAmount = 0.01;
enum
{
	PROP_FOG_ON = 0,
	PROP_FOG_START,
	PROP_FOG_END,
	PROP_FOG_DENSITY,
	PROP_FOG_COLOR_R,
	PROP_FOG_COLOR_G,
	PROP_FOG_COLOR_B,
	PROP_RAIN_ON,
	PROP_RAIN_TYPE,
	PROP_RAIN_DENSITY,
	PROP_RAIN_COLOR_R,
	PROP_RAIN_COLOR_G,
	PROP_RAIN_COLOR_B,
	PROP_RAIN_ORIGIN_HEIGHT
}

//Kv
KeyValues kvMaps;
KeyValues kvConfig;
KeyValues kvSkyboxes;

ConVar cvCurrentSkybox;
char g_cDefaultMapSkybox[64];

//Init
public void OnPluginStart()
{
	RegAdminCmd("sm_weather", MainMenu, ADMFLAG_ROOT);
	RegAdminCmd("sm_name", NewWeatherConfig, ADMFLAG_ROOT);
	
	HookEvent("round_start", RoundStart);
	HookEvent("teamplay_round_start", RoundStart);
	
	cvCurrentSkybox = FindConVar("sv_skyname");
	GetConVarString(cvCurrentSkybox, g_cDefaultMapSkybox, 63);
	CreateTimer(15.0, LoadPlugin);
	
	LoadTranslations("ultimate_weather.phrases");
}

public void OnMapStart()
{
	g_iAllSkyboxesNumber = 0;
	g_iAllConfigNumber = 0;
	g_iAllMapsNumber = 0;
	
	KeyValuesSaveDefault();
	
	KeyValuesToArraysSkyboxes();
	KeyValuesToArraysMaps();
	KeyValuesToArraysConfig();
}

public Action LoadPlugin(Handle hTimer)
{
	LoadThisMapConfiguration();
	
	ConfigurateFog();
	CreateFog();
	
	ConfigurateRain();
	CreateRain();
	
	CreateSkybox();
}

public Action RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	CreateFog();
	CreateRain();
	//CreateSkybox();
}

//Main
public Action MainMenu(int client, int args)
{
	Handle hMenu = CreateMenu(MainMenuHandle);
	char cTempBuffer[128];
	Format(cTempBuffer, 127, "%t", "Main_Menu");
	SetMenuTitle(hMenu, cTempBuffer);
	
	Format(cTempBuffer, 127, "%t", "Manage_Maps");
	AddMenuItem(hMenu, cTempBuffer, cTempBuffer);
	
	Format(cTempBuffer, 127, "%t", "Manage_Weathers");
	AddMenuItem(hMenu, cTempBuffer, cTempBuffer);
	
	Format(cTempBuffer, 127, "%t", "Save_All");
	AddMenuItem(hMenu, cTempBuffer, cTempBuffer);
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public int MainMenuHandle(Handle hMenu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		if (IsValidHandle(hMenu)) CloseHandle(hMenu);
	}
	if (action == MenuAction_Cancel)
	{
		if (IsValidHandle(hMenu)) CloseHandle(hMenu);
	}
	else if (action == MenuAction_Select)
	{
		switch (item)
		{
			case 0:{ ManageMapsMenu(client); }
			case 1:{ ManageWeathersMenu(client); }
			case 2:{ SaveAllChangesToFile(); LoadThisMapConfiguration(); CreateRain(); CreateFog(); CreateSkybox(); MainMenu(client, 0); }
		}
	}
}

public void ManageMapsMenu(int client)
{
	Handle hMenu = CreateMenu(ManageMapsMenuHandle);
	char cTempBuffer[128];
	Format(cTempBuffer, 127, "%t", "Manage_Maps");
	SetMenuTitle(hMenu, cTempBuffer);
	
	bool bTempIsThisMapHere = false;
	char cCurrentMap[64];
	GetCurrentMap(cCurrentMap, sizeof(cCurrentMap));
	for (int i = 0; i < g_iAllMapsNumber; i++)
	{
		char cTempName[256];
		Format(cTempName, 255, "%s - %s", g_cAllMapsNames[i], g_cAllMapsConfig[i]);
		AddMenuItem(hMenu, cTempName, cTempName);
		if (StrEqual(cCurrentMap, g_cAllMapsNames[i]))
			bTempIsThisMapHere = true;
	}
	
	if (!bTempIsThisMapHere)
	{
		char cTempName[256];
		Format(cTempName, 255, "%t", "Add_Map", cCurrentMap);
		AddMenuItem(hMenu, cTempName, cTempName);
	}
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int ManageMapsMenuHandle(Handle hMenu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		if (IsValidHandle(hMenu)) CloseHandle(hMenu);
	}
	if (action == MenuAction_Cancel)
	{
		if (IsValidHandle(hMenu)) CloseHandle(hMenu);
		MainMenu(client, 0);
	}
	else if (action == MenuAction_Select)
	{
		if (item == g_iAllMapsNumber) //jeśli wybrał opcję nowej mapy
		{
			char cCurrentMap[64];
			GetCurrentMap(cCurrentMap, sizeof(cCurrentMap));
			strcopy(g_cAllMapsNames[g_iAllMapsNumber], 63, cCurrentMap);
			strcopy(g_cAllMapsConfig[g_iAllMapsNumber], 63, g_cAllMapsConfig[0]);
			g_iAllMapsCfgID[g_iAllMapsNumber] = 0;
			++g_iAllMapsNumber;
		}
		g_iMenuCurrentMap = item;
		ChooseCfgForMapMenu(client);
	}
}

public void ChooseCfgForMapMenu(int client)
{
	Handle hMenu = CreateMenu(ChooseCfgForMapMenuHandle);
	char cTempName[256];
	Format(cTempName, 255, "%t", "Choose_Weather", g_cAllMapsNames[g_iMenuCurrentMap], g_cAllMapsConfig[g_iMenuCurrentMap]);
	SetMenuTitle(hMenu, cTempName);
	
	for (int i = 0; i < g_iAllConfigNumber; i++)
	{
		AddMenuItem(hMenu, g_cAllConfigNames[i], g_cAllConfigNames[i]);
	}
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int ChooseCfgForMapMenuHandle(Handle hMenu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		if (IsValidHandle(hMenu)) CloseHandle(hMenu);
	}
	if (action == MenuAction_Cancel)
	{
		if (IsValidHandle(hMenu)) CloseHandle(hMenu);
		ManageMapsMenu(client);
	}
	else if (action == MenuAction_Select)
	{
		g_iAllMapsCfgID[g_iMenuCurrentMap] = item;
		
		strcopy(g_cAllMapsConfig[g_iMenuCurrentMap], 63, g_cAllConfigNames[item]);
		
		ManageMapsMenu(client);
	}
}

public void ManageWeathersMenu(int client)
{
	Handle hMenu = CreateMenu(ManageWeathersMenuHandle);
	char cTempBuffer[128];
	Format(cTempBuffer, 127, "%t", "Manage_Weathers");
	SetMenuTitle(hMenu, cTempBuffer);
	
	for (int i = 0; i < g_iAllConfigNumber; i++)
	{
		AddMenuItem(hMenu, g_cAllConfigNames[i], g_cAllConfigNames[i]);
	}
	
	Format(cTempBuffer, 127, "%t", "Add_New");
	AddMenuItem(hMenu, cTempBuffer, cTempBuffer);
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int ManageWeathersMenuHandle(Handle hMenu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		if (IsValidHandle(hMenu)) CloseHandle(hMenu);
	}
	if (action == MenuAction_Cancel)
	{
		if (IsValidHandle(hMenu)) CloseHandle(hMenu);
		MainMenu(client, 0);
	}
	else if (action == MenuAction_Select)
	{
		if (item == g_iAllConfigNumber) //nowa
		{
			PrintToChat(client, "%t", "Chat_New_Weather");
		}
		else
		{
			g_iMenuCurrentConfig = item;
			ChangeWeatherCfgMenu(client);
		}
	}
}

public Action NewWeatherConfig(int client, int args)
{
	if (args != 1)
	{
		PrintToChat(client, "%t", "Chat_New_Weather");
		return Plugin_Handled;
	}
	
	char cTempBuffer[32];
	GetCmdArg(1, cTempBuffer, 31);
	ReplaceString(cTempBuffer, 31, "<", "", false);
	ReplaceString(cTempBuffer, 31, ">", "", false);
	StripQuotes(cTempBuffer);
	strcopy(g_cAllConfigNames[g_iAllConfigNumber], 63, cTempBuffer);
	
	g_fAllConfigVariables[g_iAllConfigNumber][PROP_FOG_ON] = 0.0;
	g_fAllConfigVariables[g_iAllConfigNumber][PROP_FOG_START] = 0.0;
	g_fAllConfigVariables[g_iAllConfigNumber][PROP_FOG_END] = 0.0;
	g_fAllConfigVariables[g_iAllConfigNumber][PROP_FOG_DENSITY] = 0.0;
	g_fAllConfigVariables[g_iAllConfigNumber][PROP_FOG_COLOR_R] = 0.0;
	g_fAllConfigVariables[g_iAllConfigNumber][PROP_FOG_COLOR_G] = 0.0;
	g_fAllConfigVariables[g_iAllConfigNumber][PROP_FOG_COLOR_B] = 0.0;
	g_fAllConfigVariables[g_iAllConfigNumber][PROP_RAIN_ON] = 0.0;
	g_fAllConfigVariables[g_iAllConfigNumber][PROP_RAIN_TYPE] = 0.0;
	g_fAllConfigVariables[g_iAllConfigNumber][PROP_RAIN_DENSITY] = 0.0;
	g_fAllConfigVariables[g_iAllConfigNumber][PROP_RAIN_ORIGIN_HEIGHT] = 1.0;
	g_fAllConfigVariables[g_iAllConfigNumber][PROP_RAIN_COLOR_R] = 0.0;
	g_fAllConfigVariables[g_iAllConfigNumber][PROP_RAIN_COLOR_G] = 0.0;
	g_fAllConfigVariables[g_iAllConfigNumber][PROP_RAIN_COLOR_B] = 0.0;
	
	g_iMenuCurrentConfig = g_iAllConfigNumber;
	
	++g_iAllConfigNumber;
	
	ChangeWeatherCfgMenu(client);
	
	return Plugin_Handled;
}

public void ChangeWeatherCfgMenu(int client)
{
	Handle hMenu = CreateMenu(ChangeWeatherCfgMenuHandle);
	char cTempName[256];
	Format(cTempName, 255, "%t", "Choose_Property", g_cAllConfigNames[g_iMenuCurrentConfig]);
	SetMenuTitle(hMenu, cTempName);
	
	for (int i = 0; i < MAX_FOG_PROP+MAX_RAIN_PROP; i++)
	{
		Format(cTempName, 255, "%s: %f", g_fAllPropertyNames[i], g_fAllConfigVariables[g_iMenuCurrentConfig][i]);
		AddMenuItem(hMenu, cTempName, cTempName);
	}
	Format(cTempName, 255, "Skybox: %s", g_cAllConfigSkyboxes[g_iMenuCurrentConfig]);
	AddMenuItem(hMenu, cTempName, cTempName);
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int ChangeWeatherCfgMenuHandle(Handle hMenu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		if (IsValidHandle(hMenu)) CloseHandle(hMenu);
	}
	if (action == MenuAction_Cancel)
	{
		if (IsValidHandle(hMenu)) CloseHandle(hMenu);
		ManageWeathersMenu(client);
	}
	else if (action == MenuAction_Select)
	{
		if (item == MAX_FOG_PROP+MAX_RAIN_PROP) //skybox
			ChooseSkyboxForWeather(client);
		else
		{
			g_iMenuCurrentProperty = item;
			ChangeWeatherPropertyMenu(client);
		}
	}
}

public void ChooseSkyboxForWeather(int client)
{
	Handle hMenu = CreateMenu(ChooseSkyboxForWeatherHandle);
	char cTempName[256];
	Format(cTempName, 255, "%t", "Choose_Skybox", g_cAllConfigNames[g_iMenuCurrentConfig]);
	SetMenuTitle(hMenu, cTempName);
	
	for (int i = 0; i < g_iAllSkyboxesNumber; i++)
	{
		AddMenuItem(hMenu, g_cAllSkyboxesNames[i], g_cAllSkyboxesNames[i]);
	}
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int ChooseSkyboxForWeatherHandle(Handle hMenu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		if (IsValidHandle(hMenu)) CloseHandle(hMenu);
	}
	if (action == MenuAction_Cancel)
	{
		if (IsValidHandle(hMenu)) CloseHandle(hMenu);
		ChangeWeatherCfgMenu(client);
	}
	else if (action == MenuAction_Select)
	{
		strcopy(g_cAllConfigSkyboxes[g_iMenuCurrentConfig], 63, g_cAllSkyboxesNames[item]);
		ChangeWeatherCfgMenu(client);
		CreateSkybox();
	}
}

public void ChangeWeatherPropertyMenu(int client)
{
	Handle hMenu = CreateMenu(ChangeWeatherPropertyMenuHandle);
	char cTempName[256];
	Format(cTempName, 255, "%t", "Change_Property", g_fAllPropertyNames[g_iMenuCurrentProperty], g_fAllConfigVariables[g_iMenuCurrentConfig][g_iMenuCurrentProperty], g_cAllConfigNames[g_iMenuCurrentConfig]);
	SetMenuTitle(hMenu, cTempName);
	
	Format(cTempName, 255, "+%f", g_fMenuCurrentChangeAmount);
	AddMenuItem(hMenu, cTempName, cTempName);
	Format(cTempName, 255, "-%f", g_fMenuCurrentChangeAmount);
	AddMenuItem(hMenu, cTempName, cTempName);
	
	Format(cTempName, 255, "%t", "Change_Amount");
	AddMenuItem(hMenu, cTempName, cTempName);
	
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public int ChangeWeatherPropertyMenuHandle(Handle hMenu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
	{
		if (IsValidHandle(hMenu)) CloseHandle(hMenu);
	}
	if (action == MenuAction_Cancel)
	{
		if (IsValidHandle(hMenu)) CloseHandle(hMenu);
		ChangeWeatherCfgMenu(client);
	}
	else if (action == MenuAction_Select)
	{
		switch (item)
		{
			case 0: g_fAllConfigVariables[g_iMenuCurrentConfig][g_iMenuCurrentProperty] += g_fMenuCurrentChangeAmount;
			case 1: g_fAllConfigVariables[g_iMenuCurrentConfig][g_iMenuCurrentProperty] -= g_fMenuCurrentChangeAmount;
			case 2: 
			{
					switch(g_fMenuCurrentChangeAmount)
					{
						case 0.01: g_fMenuCurrentChangeAmount = 0.1;
						case 0.1: g_fMenuCurrentChangeAmount = 1.0;
						case 1.0: g_fMenuCurrentChangeAmount = 5.0;
						case 5.0: g_fMenuCurrentChangeAmount = 15.0;
						case 15.0: g_fMenuCurrentChangeAmount = 25.0;
						case 25.0: g_fMenuCurrentChangeAmount = 100.0;
						case 100.0: g_fMenuCurrentChangeAmount = 0.01;
					}
			}
		}
		LoadThisMapConfiguration();
		CreateRain();
		CreateFog();
		ChangeWeatherPropertyMenu(client);
	}
}

//Stocks
stock void SaveAllChangesToFile()
{
	kvMaps = new KeyValues("Maps");
	for (int i = 0; i < g_iAllMapsNumber; i++)
	{
		kvMaps.JumpToKey(g_cAllMapsNames[i], true);
		kvMaps.SetString("name", g_cAllMapsConfig[i]);
		kvMaps.Rewind();
	}
	kvMaps.ExportToFile(KEYVALUES_MAPS);
	
	kvConfig = new KeyValues("Configurations");
	for (int i = 0; i < g_iAllConfigNumber; i++)
	{
		kvConfig.JumpToKey(g_cAllConfigNames[i], true);
		char cTempSaveVariable[14];
		FloatToString(g_fAllConfigVariables[i][PROP_FOG_ON], cTempSaveVariable, 13);
		kvConfig.SetString("fog_on", cTempSaveVariable);
		FloatToString(g_fAllConfigVariables[i][PROP_FOG_START], cTempSaveVariable, 13);
		kvConfig.SetString("fog_start", cTempSaveVariable);
		FloatToString(g_fAllConfigVariables[i][PROP_FOG_END], cTempSaveVariable, 13);
		kvConfig.SetString("fog_end", cTempSaveVariable);
		FloatToString(g_fAllConfigVariables[i][PROP_FOG_DENSITY], cTempSaveVariable, 13);
		kvConfig.SetString("fog_density", cTempSaveVariable);
		Format(cTempSaveVariable, 13, "%i %i %i", RoundFloat(g_fAllConfigVariables[i][PROP_FOG_COLOR_R]), RoundFloat(g_fAllConfigVariables[i][PROP_FOG_COLOR_G]), RoundFloat(g_fAllConfigVariables[i][PROP_FOG_COLOR_B]));
		kvConfig.SetString("fog_colors", cTempSaveVariable);
		FloatToString(g_fAllConfigVariables[i][PROP_RAIN_ON], cTempSaveVariable, 13);
		kvConfig.SetString("rain_on", cTempSaveVariable);
		FloatToString(g_fAllConfigVariables[i][PROP_RAIN_TYPE], cTempSaveVariable, 13);
		kvConfig.SetString("rain_type", cTempSaveVariable);
		FloatToString(g_fAllConfigVariables[i][PROP_RAIN_DENSITY], cTempSaveVariable, 13);
		kvConfig.SetString("rain_density", cTempSaveVariable);
		Format(cTempSaveVariable, 13, "%i %i %i", RoundFloat(g_fAllConfigVariables[i][PROP_RAIN_COLOR_R]), RoundFloat(g_fAllConfigVariables[i][PROP_RAIN_COLOR_G]), RoundFloat(g_fAllConfigVariables[i][PROP_RAIN_COLOR_B]));
		kvConfig.SetString("rain_colors", cTempSaveVariable);
		FloatToString(g_fAllConfigVariables[i][PROP_RAIN_ORIGIN_HEIGHT], cTempSaveVariable, 13);
		kvConfig.SetString("rain_height", cTempSaveVariable);
		kvConfig.SetString("skybox", g_cAllConfigSkyboxes[i]);
		kvConfig.Rewind();
	}
	kvConfig.ExportToFile(KEYVALUES_CFG);
	
}

stock void KeyValuesToArraysSkyboxes()
{
	kvSkyboxes.Rewind();
	if (kvSkyboxes.GotoFirstSubKey())
	{
		do
		{
			kvSkyboxes.GetSectionName(g_cAllSkyboxesNames[g_iAllSkyboxesNumber], 63);
			
			if (StrEqual(g_cAllSkyboxesNames[g_iAllSkyboxesNumber], "none"))
				continue;
			
			kvSkyboxes.GetString("filename", g_cAllSkyboxesPaths[g_iAllSkyboxesNumber], 127);
			
			char cTempSuffixes[][] = {
				"bk",
				"dn",
				"ft",
				"lf",
				"rt",
				"up",
			};
			char cTempFileVTF[256], cTempFileVMT[256];
			int j = 0;
			for (int i = 0; i < sizeof(cTempSuffixes); i++)
			{
				Format(cTempFileVTF, sizeof(cTempFileVTF), "materials/skybox/%s%s.vtf", g_cAllSkyboxesPaths[g_iAllSkyboxesNumber], cTempSuffixes[i]);
				Format(cTempFileVMT, sizeof(cTempFileVMT), "materials/skybox/%s%s.vmt", g_cAllSkyboxesPaths[g_iAllSkyboxesNumber], cTempSuffixes[i]);
				
				if (FileExists(cTempFileVTF, false) && FileExists(cTempFileVMT, false))
				{
					AddFileToDownloadsTable(cTempFileVTF);
					AddFileToDownloadsTable(cTempFileVMT);
					++j;
				}
			}
			
			if (j == 6)
			{
				PrintToServer("[CustomWeather][Skyboxes] %i Skybox %s fully loaded", g_iAllSkyboxesNumber, g_cAllSkyboxesNames[g_iAllSkyboxesNumber]);
				++g_iAllSkyboxesNumber;
			}
			else
				PrintToServer("[CustomWeather][Skyboxes] Whoops, something went wrong, no complite 6 (%i exacly) skybox files found under name %s", j, g_cAllSkyboxesNames[g_iAllSkyboxesNumber]);
		}
		while (kvSkyboxes.GotoNextKey());
	}
}

stock void KeyValuesToArraysConfig()
{
	kvConfig.Rewind();
	if (kvConfig.GotoFirstSubKey())
	{
		do
		{
			kvConfig.GetSectionName(g_cAllConfigNames[g_iAllConfigNumber], 63);
			
			
			char cTempIsFogTurnedOn[12];
			kvConfig.GetString("fog_on", cTempIsFogTurnedOn, 11);
			g_fAllConfigVariables[g_iAllConfigNumber][PROP_FOG_ON] = StringToFloat(cTempIsFogTurnedOn);
			
			char cTempFogStart[12];
			kvConfig.GetString("fog_start", cTempFogStart, 11);
			g_fAllConfigVariables[g_iAllConfigNumber][PROP_FOG_START] = StringToFloat(cTempFogStart);
			
			char cTempFogEnd[12];
			kvConfig.GetString("fog_end", cTempFogEnd, 11);
			g_fAllConfigVariables[g_iAllConfigNumber][PROP_FOG_END] = StringToFloat(cTempFogEnd);
			
			char cTempFogDensity[12];
			kvConfig.GetString("fog_density", cTempFogDensity, 11);
			g_fAllConfigVariables[g_iAllConfigNumber][PROP_FOG_DENSITY] = StringToFloat(cTempFogDensity);
			
			char cTempFogColorsAll[12];
			char cTempFogColorsSplit[3][14];
			kvConfig.GetString("fog_colors", cTempFogColorsAll, 13);
			ExplodeString(cTempFogColorsAll, " ", cTempFogColorsSplit, 3, 13);
			g_fAllConfigVariables[g_iAllConfigNumber][PROP_FOG_COLOR_R] = StringToFloat(cTempFogColorsSplit[0]);
			g_fAllConfigVariables[g_iAllConfigNumber][PROP_FOG_COLOR_G] = StringToFloat(cTempFogColorsSplit[1]);
			g_fAllConfigVariables[g_iAllConfigNumber][PROP_FOG_COLOR_B] = StringToFloat(cTempFogColorsSplit[2]);
			
			char cTempRainTurnedOn[12];
			kvConfig.GetString("rain_on", cTempRainTurnedOn, 11);
			g_fAllConfigVariables[g_iAllConfigNumber][PROP_RAIN_ON] = StringToFloat(cTempRainTurnedOn);
			
			char cTempRainType[12];
			kvConfig.GetString("rain_type", cTempRainType, 11);
			g_fAllConfigVariables[g_iAllConfigNumber][PROP_RAIN_TYPE] = StringToFloat(cTempRainType);
			
			char cTempRainDensity[12];
			kvConfig.GetString("rain_density", cTempRainDensity, 11);
			g_fAllConfigVariables[g_iAllConfigNumber][PROP_RAIN_DENSITY] = StringToFloat(cTempRainDensity);
			
			char cTempRainHeight[12];
			kvConfig.GetString("rain_height", cTempRainHeight, 11);
			g_fAllConfigVariables[g_iAllConfigNumber][PROP_RAIN_ORIGIN_HEIGHT] = StringToFloat(cTempRainHeight);
			
			char cTempRainColorsAll[12], cTempRainColorsSplit[3][14];
			kvConfig.GetString("rain_colors", cTempRainColorsAll, 13);
			ExplodeString(cTempRainColorsAll, " ", cTempRainColorsSplit, 3, 13);
			g_fAllConfigVariables[g_iAllConfigNumber][PROP_RAIN_COLOR_R] = StringToFloat(cTempRainColorsSplit[0]);
			g_fAllConfigVariables[g_iAllConfigNumber][PROP_RAIN_COLOR_G] = StringToFloat(cTempRainColorsSplit[1]);
			g_fAllConfigVariables[g_iAllConfigNumber][PROP_RAIN_COLOR_B] = StringToFloat(cTempRainColorsSplit[2]);
			
			kvConfig.GetString("skybox", g_cAllConfigSkyboxes[g_iAllConfigNumber], 63);
			
			if (StrEqual(g_cAllConfigSkyboxes[g_iAllConfigNumber], ""))
				strcopy(g_cAllConfigSkyboxes[g_iAllConfigNumber], 63, "none");
			
			PrintToServer("[CustomWeather][Configurations] %i Configname found %s", g_iAllConfigNumber, g_cAllConfigNames[g_iAllConfigNumber]);
			
			//przyporządkowanie nazwy pogody do ID
			for(int i = 0; i <= g_iAllMapsNumber; i++)
			{
				if (StrEqual(g_cAllConfigNames[g_iAllConfigNumber], g_cAllMapsConfig[i]))
				{
					g_iAllMapsCfgID[i] = g_iAllConfigNumber;
					break;
				}
			}
			
			++g_iAllConfigNumber;
			
		}
		while (kvConfig.GotoNextKey());
	}
}

stock void KeyValuesToArraysMaps()
{
	kvMaps.Rewind();
	kvMaps.JumpToKey("Maps");
	kvMaps.GotoFirstSubKey(false);
	do
	{
		kvMaps.GetSectionName(g_cAllMapsNames[g_iAllMapsNumber], 63);
		kvMaps.GetString("name", g_cAllMapsConfig[g_iAllMapsNumber], 63);
		PrintToServer("[CustomWeather][Maps] %i Mapname found %s with weather %s", g_iAllMapsNumber, g_cAllMapsNames[g_iAllMapsNumber], g_cAllMapsConfig[g_iAllMapsNumber]);
		++g_iAllMapsNumber;
	}
	while (kvMaps.GotoNextKey(false));
}

stock void LoadThisMapConfiguration()
{
	char currentMap[64];
	GetCurrentMap(currentMap, sizeof(currentMap));
	for (int i = 0; i < g_iAllMapsNumber; i++)
	{
		if (StrEqual(currentMap, g_cAllMapsNames[i]))
		{
			g_iCurrentConfigurationID = i;
			break;
		}
	}
	for (int i = 0; i < g_iAllConfigNumber; i++)
	{
		if (StrEqual(g_cAllConfigNames[i], g_cAllMapsConfig[g_iCurrentConfigurationID]))
		{
			g_iCurrentConfigurationID = i;
			break;
		}
	}
}

stock void KeyValuesSaveDefault()
{
	//Create KeyValues files
	kvMaps = new KeyValues("Maps");
	kvMaps.ImportFromFile(KEYVALUES_MAPS);
	kvMaps.JumpToKey("none", true);
	kvMaps.SetString("name", "default");
	kvMaps.Rewind();
	kvMaps.ExportToFile(KEYVALUES_MAPS);
	
	kvConfig = new KeyValues("Configurations");
	kvConfig.ImportFromFile(KEYVALUES_CFG);
	kvConfig.JumpToKey("default", true);
	kvConfig.SetString("fog_on", "0.0");
	kvConfig.SetString("fog_start", "0.0");
	kvConfig.SetString("fog_end", "0.0");
	kvConfig.SetString("fog_density", "0.0");
	kvConfig.SetString("fog_colors", "255 255 255");
	kvConfig.SetString("rain_on", "0.0");
	kvConfig.SetString("rain_type", "0.0");
	kvConfig.SetString("rain_density", "0.0");
	kvConfig.SetString("rain_colors", "255 255 255");
	kvConfig.SetString("rain_height", "1.0");
	kvConfig.SetString("skybox", "none");
	kvConfig.Rewind();
	kvConfig.ExportToFile(KEYVALUES_CFG);
	
	kvSkyboxes = new KeyValues("Skyboxes");
	kvSkyboxes.ImportFromFile(KEYVALUES_SKYBOX);
	kvSkyboxes.JumpToKey("none", true);
	kvSkyboxes.SetString("filename", "none");
	kvSkyboxes.Rewind();
	kvSkyboxes.ExportToFile(KEYVALUES_SKYBOX);
	
}

stock void ConfigurateFog()
{
	//Create Fog entity if not exists
	int entity;
	entity = FindEntityByClassname(-1, "env_fog_controller");
	if (entity != -1){
		g_iMainFogEntity = entity;
	}
	else{
		g_iMainFogEntity = CreateEntityByName("env_fog_controller");
		DispatchSpawn(g_iMainFogEntity);
	}
}

stock void ConfigurateRain()
{
	//Configurate Rain vectors
	char MapName[64]; 
	GetCurrentMap(MapName, 63);
	Format(g_cRainModel, sizeof(g_cRainModel), "maps/%s.bsp", MapName); //Ściągnięcie modelu
	PrecacheModel(g_cRainModel, true);
	
	GetEntPropVector(0, Prop_Data, "m_WorldMins", g_fRainMinRange); // Obiczenie rozmiarów mapy
	GetEntPropVector(0, Prop_Data, "m_WorldMaxs", g_fRainMaxRange);
	float normal_vector[3] = {1.0, 1.0, 1.0};
	while(TR_PointOutsideWorld(g_fRainMinRange))
		AddVectors(g_fRainMinRange, normal_vector, g_fRainMinRange);
	ScaleVector(normal_vector, -1.0);
	while(TR_PointOutsideWorld(g_fRainMaxRange))
		AddVectors(g_fRainMaxRange, normal_vector, g_fRainMaxRange);
	
	AddVectors(g_fRainMinRange, g_fRainMaxRange, g_fRainOrigin); // Obliczenie środka mapy
	ScaleVector(g_fRainOrigin, 0.5);
}

stock void CreateFog()
{
	if (g_iMainFogEntity != -1)
	{
		AcceptEntityInput(g_iMainFogEntity, "TurnOff");//wylacz przed zmianami
		
		char cTempText[14];
		Format(cTempText, 13, "%i %i %i", RoundFloat(g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_FOG_COLOR_R]), RoundFloat(g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_FOG_COLOR_G]), RoundFloat(g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_FOG_COLOR_B]));
		
		DispatchKeyValue(g_iMainFogEntity, "fogblend", "0");
		DispatchKeyValue(g_iMainFogEntity, "fogcolor", cTempText);
		DispatchKeyValue(g_iMainFogEntity, "fogcolor2", cTempText);
		DispatchKeyValueFloat(g_iMainFogEntity, "fogstart", g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_FOG_START]);
		DispatchKeyValueFloat(g_iMainFogEntity, "fogend", g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_FOG_END]);
		DispatchKeyValueFloat(g_iMainFogEntity, "fogmaxdensity", g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_FOG_DENSITY]);
		
		if (g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_FOG_ON])//wlacz jesli byla wlaczona
			AcceptEntityInput(g_iMainFogEntity, "TurnOn");
		else
			AcceptEntityInput(g_iMainFogEntity, "TurnOff");
	}
}

stock void CreateRain()
{
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "func_precipitation")) != -1)
		AcceptEntityInput(entity, "Kill");
	if (g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_RAIN_ON])
	{
		g_iMainRainEntity = CreateEntityByName("func_precipitation");
		if (g_iMainRainEntity != -1)
		{
			char cTempText[12];
			DispatchKeyValue(g_iMainRainEntity, "model", g_cRainModel);
			Format(cTempText, 11, "%i", RoundFloat(g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_RAIN_TYPE]));
			DispatchKeyValue(g_iMainRainEntity, "preciptype", cTempText);
			Format(cTempText, 11, "%i", RoundFloat(g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_RAIN_DENSITY]));
			DispatchKeyValue(g_iMainRainEntity, "density", cTempText);
			Format(cTempText, 11, "%i %i %i", RoundFloat(g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_RAIN_COLOR_R]), RoundFloat(g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_RAIN_COLOR_G]), RoundFloat(g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_RAIN_COLOR_B]));
			DispatchKeyValue(g_iMainRainEntity, "rendercolor", cTempText);
			DispatchSpawn(g_iMainRainEntity);
			ActivateEntity(g_iMainRainEntity);
			
			float minrange[3];
			minrange[0] = g_fRainMinRange[0];
			minrange[1] = g_fRainMinRange[1];
			minrange[2] = g_fRainMinRange[2] * g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_RAIN_ORIGIN_HEIGHT];
			float maxrange[3];
			maxrange[0] = g_fRainMaxRange[0];
			maxrange[1] = g_fRainMaxRange[1];
			maxrange[2] = g_fRainMaxRange[2] * g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_RAIN_ORIGIN_HEIGHT];
			
			SetEntPropVector(g_iMainRainEntity, Prop_Send, "m_vecMins", g_fRainMinRange);
			SetEntPropVector(g_iMainRainEntity, Prop_Send, "m_vecMaxs", g_fRainMaxRange);
			
			float origin[3];
			origin[0] = g_fRainOrigin[0];
			origin[1] = g_fRainOrigin[1];
			origin[2] = g_fRainOrigin[2] * g_fAllConfigVariables[g_iCurrentConfigurationID][PROP_RAIN_ORIGIN_HEIGHT];
			TeleportEntity(g_iMainRainEntity, origin, NULL_VECTOR, NULL_VECTOR);
		}
	}
}

stock void CreateSkybox()
{
	int iTempSkyboxID = -1;
	for (int i = 0; i < g_iAllSkyboxesNumber; i++) //Szuka czy we wszystkich skyboxach jest nazwa skyboxa który posiada konfiguracja
	{
		if (StrEqual(g_cAllConfigSkyboxes[g_iCurrentConfigurationID], g_cAllSkyboxesNames[i]))
		{
			iTempSkyboxID = i;
			break;
		}
	}
	
	if (iTempSkyboxID == -1 || StrEqual(g_cAllSkyboxesPaths[iTempSkyboxID], "mapdefault") || StrEqual(g_cAllSkyboxesPaths[iTempSkyboxID], "none") || StrEqual(g_cAllSkyboxesPaths[iTempSkyboxID], "default") || StrEqual(g_cAllSkyboxesPaths[iTempSkyboxID], ""))
	{
		SetConVarString(cvCurrentSkybox, g_cDefaultMapSkybox, true, false);
	}
	else
	{
		//LogToFile(LOG_FILE, "Setting up %s with ID %i, current skybox name in configuration %s", g_cAllSkyboxesPaths[iTempSkyboxID], iTempSkyboxID, g_cAllConfigSkyboxes[g_iCurrentConfigurationID]);
		SetConVarString(cvCurrentSkybox, g_cAllSkyboxesPaths[iTempSkyboxID], true, false);
	}
}

