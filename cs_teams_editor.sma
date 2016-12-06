/*
    CS Teams Editor
    Version 1.0
    Copyright  2013, Danakt Frost

    CS Teams Editor is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    CS Teams Editor is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with CS Teams Editor. If not, see <http://www.gnu.org/licenses/>.

    Description:
    This plugin is designed to modify and supplement the Team Select Menu.
    See team_select_menu.ini
*/

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>

// Defines and variables -------------------------------------------------------
#define PLUGIN        "CS Teams Editor"
#define VERSION       "1.0"
#define AUTHOR        "Danakt Frost"

#define FILE_NAME     "team_select_menu.ini"
#define MODEL         "model"
#define MAX_NUM_TEAMS 2
#define MAX_PLAYERS   32

#define KEYS          ( 1<<0 | 1<<1 | 1<<2 | 1<<3 | 1<<4 | 1<<5 | 1<<6 | 1<<7 | 1<<8 | 1<<9 )

#define EXTRAOFFSET   5
#define OFFSET_ISVIP  209
#define PLAYER_IS_VIP ( 1<<8 )

#define USER_TEAM     114
#define cste_get_user_team(%0) (get_pdata_int(%0, USER_TEAM) - 1)

enum {
    CSTE_UNASSIGNED = -1,
    CSTE_TEAM_T     = 0,
    CSTE_TEAM_CT,
    CSTE_SPECTATOR
}

enum _:NumDatas {
    CLASS_NAME = 0,
    CLASS_TAG,
    CLASS_ACCESS
}

new g_szConfigFile[128];
new g_szClassesT[32][NumDatas][64],
    g_szClassesCT[32][NumDatas][64],
    g_szClassAccess[MAX_NUM_TEAMS][32];
new g_szTeamName[2][128];
new g_iCount[MAX_NUM_TEAMS];
new g_iMsgId[MAX_PLAYERS+1],
    g_iUserTeam[MAX_PLAYERS+1];
new bool:g_bChanged[MAX_PLAYERS+1];
new g_szPlayerModel[MAX_PLAYERS+1][128];
new g_iMaxPlayers;
new g_pCvarAllowSpec,
    g_pCvarLimitTeams,
    g_pCvarTeamBalance;

// Plugin initialisation -------------------------------------------------------
public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_clcmd("chooseteam", "clcmd_chooseteam");

    register_message(get_user_msgid("ShowMenu"), "TeamMenu_Hook");
    register_message(get_user_msgid("VGUIMenu"), "TeamMenuVGUI_Hook");
    register_message(get_user_msgid("ClCorpse"), "Message_ClCorpse");

    register_forward(FM_SetClientKeyValue, "SetClientKeyValue");
    register_event("HLTV", "NewRound", "a", "1=0", "2=0")

    register_menucmd(register_menuid("TeamMenu"), KEYS, "team_menu_handler");
    register_menucmd(register_menuid("ClassMenu"), KEYS, "class_menu_handler");

    // Cvars
    g_pCvarAllowSpec   = get_cvar_pointer("allow_spectators");
    g_pCvarLimitTeams  = get_cvar_pointer("mp_limitteams");
    g_pCvarTeamBalance = get_cvar_pointer("mp_autoteambalance");

    g_iMaxPlayers = get_maxplayers();
}

// Plugin precaches ------------------------------------------------------------
public plugin_precache() {
    get_configsdir(g_szConfigFile, 127);
    format(g_szConfigFile, 127, "%s/%s", g_szConfigFile, FILE_NAME);

    new dFile = fopen(g_szConfigFile, "rt");
    new szModelFile[128], szErrorMsg[128];
    new szData[256];
    new iTeam = -1;

    if(!dFile) {
        format(
            szErrorMsg, 127, "Plugin can't found file ^"%s^"",
            g_szConfigFile
        );

        return set_fail_state(szErrorMsg);
    }


    while(!feof(dFile)) {
        fgets(dFile, szData, 255);
        if(szData[0] == '/' && szData[1] == '/'
        || szData[0] == ';' || szData[0] == '^n')
            continue;

        replace(szData, 255, "^n", "");

        if(szData[0] == '[') {
            iTeam++;
            if(iTeam > MAX_NUM_TEAMS)
                break;

            replace(szData, 255, "]", "");
            replace(szData, 255, "[", "");
            format(g_szTeamName[iTeam], 127, "%s", szData);
        }
        else {
            if(iTeam < 0)
                continue;

            new szClassData[NumDatas][64];

            parse(
                szData, szClassData[CLASS_NAME], 63,
                szClassData[CLASS_TAG], 63,
                szClassData[CLASS_ACCESS], 63
            );

            format(
                szModelFile, 127, "models/player/%s/%s.mdl",
                szClassData[CLASS_TAG],  szClassData[CLASS_TAG]
            );
            if(!file_exists(szModelFile) || !szClassData[CLASS_TAG][0] ) {
                server_print(
                    "[CSTE] Warning! Item ^"%s^" wasn't created: file ^"%s^" doesn't exist.",
                    szClassData[CLASS_NAME], szModelFile
                );
                continue;
            }
            precache_model(szModelFile);

            new iClassId = g_iCount[iTeam];
            for(new i = 0; i < NumDatas; i++) {
                if(iTeam == CSTE_TEAM_T)
                    g_szClassesT[iClassId][i] = szClassData[i];
                else if(iTeam == CSTE_TEAM_CT)
                    g_szClassesCT[iClassId][i] = szClassData[i];
            }

            if(szClassData[CLASS_ACCESS][0])
                g_szClassAccess[iTeam][iClassId] = read_flags(
                    szClassData[CLASS_ACCESS]
                );
            else
                g_szClassAccess[iTeam][iClassId] = ADMIN_ALL;

            g_iCount[iTeam]++;
        }
    }

    return PLUGIN_CONTINUE;
}

// New round event -------------------------------------------------------------
public NewRound() {
    for (new id = 1; id <= g_iMaxPlayers; id ++)
        g_bChanged[id] = false;
}

// Client disconnect event -----------------------------------------------------
public client_connect(id) {
    g_iUserTeam[id] = CSTE_UNASSIGNED;
    g_bChanged[id]  = false;
}

// Opening teams menu ----------------------------------------------------------
public team_menu(id) {
    if(g_bChanged[id]) {
        client_print(id, print_center, "#Cstrike_TitlesTXT_Only_1_Team_Change");
        return;
    }

    new szItem[512], len, bitKeys;
    bitKeys = ( 1<<0 | 1<<1 | 1<<4 | 1<<9 );

    len = format(
        szItem, 511,"\ySelect a team^n^n\w1. %s^n\w2. %s^n^n\w5. Auto-select^n",
        g_szTeamName[0], g_szTeamName[1]
    );

    if(get_pcvar_num(g_pCvarAllowSpec) && !is_user_alive(id)) {
        bitKeys |= 1<<5;
        len += format(szItem[len], 511-len, "\w6. Spectator^n");
    }

    len += format(szItem[len], 511-len, "^n\w0. Exit^n");
    show_menu(id, bitKeys, szItem, -1, "TeamMenu");
}

// Handle teams menu -----------------------------------------------------------
public team_menu_handler(id, key) {
    switch(key+1) {
        case 1, 2: {
            if(join_allow(id) != key+1 && join_allow(id) != 3) {
                g_iUserTeam[id] = key;
                team_join(id, key);
                create_classes_menu(id, key);
            }
        }
        case 5: {
            new iRand;
            iRand = random(2);
            g_iUserTeam[id] = iRand;
            team_join(id, iRand);
            create_classes_menu(id, iRand);
        }
        case 6: {
            if(get_pcvar_num(g_pCvarAllowSpec) && !is_user_alive(id)) {
                g_iUserTeam[id] = CSTE_SPECTATOR;
                g_bChanged[id] = true;
                engclient_cmd(id, "jointeam", "6")
            }else
                team_menu(id);
        }
    }

    return PLUGIN_HANDLED;
}

// Opening classes menu --------------------------------------------------------
public create_classes_menu(id, iTeam) {
    new szItem[512], len, bitKeys = 1<<(g_iCount[iTeam]), bAccess;

    len = format(szItem, 511,"\ySelect your appearance^n^n");
    for(new i=0; i<g_iCount[iTeam];i++) {
        bAccess = (get_user_flags(id) & g_szClassAccess[iTeam][i]);

        if(bAccess || g_szClassAccess[iTeam][i] == ADMIN_ALL) {
            len += format(
                szItem[len], 511-len, "%s%d. %s^n",
                (bAccess ? "\y" : "\w"), i + 1,
                get_class_info(iTeam, i, CLASS_NAME)
            );

            bitKeys |= 1<<i;
        }else
            len += format(
                szItem[len], 511-len, "\d%d. %s\R\rNO ACCESS^n",
                i+1, get_class_info(iTeam, i, CLASS_NAME)
            );

    }
    len += format(
        szItem[len], 511-len, "^n\w%d. Auto-select",
        g_iCount[iTeam] + 1
    );

    show_menu(id, bitKeys, szItem, -1, "ClassMenu");

    return PLUGIN_HANDLED;
}

// Handle classes menu ---------------------------------------------------------
public class_menu_handler(id, key) {
    new iMenuMsgid = g_iMsgId[id];
    new iMsgBlock  = get_msg_block(iMenuMsgid);

    set_msg_block(iMenuMsgid, BLOCK_SET);
    engclient_cmd(id, "joinclass", "1");
    set_msg_block(iMenuMsgid, iMsgBlock);

    format(
        g_szPlayerModel[id], 127, "%s",
        get_class_info(g_iUserTeam[id], key, CLASS_TAG)
    );

    // Auto-select
    if(key == g_iCount[g_iUserTeam[id]] )
        get_random_class_tag(id, g_iUserTeam[id], g_szPlayerModel[id], 127);

    set_user_info(id, MODEL, g_szPlayerModel[id]);
    g_bChanged[id] = true;

    return PLUGIN_HANDLED;
}

// SetClientKeyValue forward ---------------------------------------------------
public SetClientKeyValue(id, szInfoBuffer[], szKey[], szValue[]) {
    if(equal(szKey, MODEL) && is_user_connected(id)) {
        g_iUserTeam[id] = cste_get_user_team(id);

        if(g_iUserTeam[id] == get_class_team_by_tag(g_szPlayerModel[id])
        && !equal(szValue, g_szPlayerModel[id])) {
            set_user_info(id, MODEL, g_szPlayerModel[id]);
            return FMRES_SUPERCEDE;
        }
    }

    return FMRES_IGNORED;
}

// Message ClCorpse ------------------------------------------------------------
public Message_ClCorpse() {
    new id = get_msg_arg_int(12);

    // if user is not VIP
    if(!(get_pdata_int(id, OFFSET_ISVIP, EXTRAOFFSET) & PLAYER_IS_VIP)) {
        set_msg_arg_string(1, g_szPlayerModel[id]);
    }
}

// Player actions hooks --------------------------------------------------------
// Team select menu hook
public TeamMenu_Hook(iMsgid, dest, id) {
    static szTeamSelect[] = "#Team_Select";
    static szMenuTextCode[32];
    get_msg_arg_string(4, szMenuTextCode, sizeof szMenuTextCode - 1);

    if(contain(szMenuTextCode, szTeamSelect) > -1) {
        team_menu(id);
        return PLUGIN_HANDLED;
    }

    g_iMsgId[id] = iMsgid;

    return PLUGIN_CONTINUE;
}

// VGUI menu hook
public TeamMenuVGUI_Hook(iMsgid, dest, id) {
    if(get_msg_arg_int(1) == 2) {
        team_menu(id);
        return PLUGIN_HANDLED;
    }
    else    if(get_msg_arg_int(1) == 26) {
        create_classes_menu(id, CSTE_TEAM_T);
        return PLUGIN_HANDLED;
    }
    else if(get_msg_arg_int(1) == 27) {
        create_classes_menu(id, CSTE_TEAM_CT);
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

// Console command hook
public clcmd_chooseteam(id) {
    team_menu(id);
    return PLUGIN_HANDLED;
}

//
stock team_join(id, iTeam) {
    new szTeam[2];
    new iMenuMsgid = g_iMsgId[id];
    new iMsgBlock = get_msg_block(iMenuMsgid);

    g_iUserTeam[id] = iTeam;
    g_bChanged[id] = true;

    num_to_str(iTeam+1, szTeam, 1);
    set_msg_block(iMenuMsgid, BLOCK_SET);
    engclient_cmd(id, "jointeam", szTeam);
    set_msg_block(iMenuMsgid, iMsgBlock);
}

// Stocks ----------------------------------------------------------------------
stock get_class_info(iTeam, iClass, iData) {
    new szReturn[64];

    if(iTeam == CSTE_TEAM_T)
         szReturn = g_szClassesT[iClass][iData];
    else if(iTeam == CSTE_TEAM_CT)
        szReturn = g_szClassesCT[iClass][iData];

    return szReturn;
}

stock get_random_class_tag(id, iTeam, szOutput[], len) {
    new bool:bDone = false;
    while(!bDone) {
        new iCount = g_iCount[iTeam];
        new iRandomClassNum = random_num(0, iCount);

        if(g_szClassAccess[iTeam][iRandomClassNum] != ADMIN_ALL
        && (!(get_user_flags(id) & g_szClassAccess[iTeam][iRandomClassNum])
        || is_user_bot(id)))
            continue;

        copy(szOutput, len, get_class_info(iTeam, iRandomClassNum, CLASS_TAG))
        bDone = true;
    }
}

stock get_class_team_by_tag(const szTag[]) {
    for(new iTeam=0; iTeam<MAX_NUM_TEAMS; iTeam++)
        for(new i=0; i<g_iCount[iTeam]; i++) {
            if(equal(szTag, get_class_info(iTeam, i, CLASS_TAG)))
            return iTeam;
        }

    return -2;
}

stock join_allow(id) {
    new iNumT, iNumCT;
    new iPlayers[32];

    get_players(iPlayers, iNumT, "eh", "TERRORIST")
    get_players(iPlayers, iNumCT, "eh", "CT")

    if(cste_get_user_team(id) == CSTE_TEAM_CT)
        iNumCT--;
    else if(cste_get_user_team(id) == CSTE_TEAM_T)
        iNumT--;

    new iTeamsLimit = get_pcvar_num(g_pCvarLimitTeams);

    if(get_pcvar_num(g_pCvarTeamBalance) && iTeamsLimit != 0) {
        if(iNumT-iNumCT >= iTeamsLimit && iNumCT-iNumT >= iTeamsLimit)
            return 3;
        else if(iNumT-iNumCT >= iTeamsLimit)
            return 1;
        else if (iNumCT-iNumT >= iTeamsLimit)
            return 2;
    }

    return 0;
}
