/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include "nl80211.h"
#include "nl.h"

#define BIT(x) (1ULL<<(x))

static int parse_sta_flag_update(lua_State *L)
{
    struct nl80211_sta_flag_update *flags = (struct nl80211_sta_flag_update *)luaL_checkstring(L, 1);

    lua_newtable(L);

    if (flags->mask & BIT(NL80211_STA_FLAG_AUTHORIZED)) {
        lua_pushboolean(L, flags->set & BIT(NL80211_STA_FLAG_AUTHORIZED));
        lua_setfield(L, -2, "authorized");
    }

    if (flags->mask & BIT(NL80211_STA_FLAG_AUTHENTICATED)) {
        lua_pushboolean(L, flags->set & BIT(NL80211_STA_FLAG_AUTHENTICATED));
        lua_setfield(L, -2, "authenticated");
    }

    if (flags->mask & BIT(NL80211_STA_FLAG_ASSOCIATED)) {
        lua_pushboolean(L, flags->set & BIT(NL80211_STA_FLAG_ASSOCIATED));
        lua_setfield(L, -2, "associated");
    }

    if (flags->mask & BIT(NL80211_STA_FLAG_SHORT_PREAMBLE)) {
        if (flags->set & BIT(NL80211_STA_FLAG_SHORT_PREAMBLE))
            lua_pushliteral(L, "short");
        else
            lua_pushliteral(L, "long");
        lua_setfield(L, -2, "preamble");
    }

    if (flags->mask & BIT(NL80211_STA_FLAG_WME)) {
        lua_pushboolean(L, flags->set & BIT(NL80211_STA_FLAG_WME));
        lua_setfield(L, -2, "wme");
    }

    if (flags->mask & BIT(NL80211_STA_FLAG_MFP)) {
        lua_pushboolean(L, flags->set & BIT(NL80211_STA_FLAG_MFP));
        lua_setfield(L, -2, "mfp");
    }

    return 1;
}

int luaopen_eco_core_nl80211(lua_State *L)
{
    lua_newtable(L);

    lua_add_constant(L, "CMD_GET_WIPHY", NL80211_CMD_GET_WIPHY);
    lua_add_constant(L, "CMD_SET_WIPHY", NL80211_CMD_SET_WIPHY);

    lua_add_constant(L, "CMD_GET_INTERFACE", NL80211_CMD_GET_INTERFACE);
    lua_add_constant(L, "CMD_SET_INTERFACE", NL80211_CMD_SET_INTERFACE);
    lua_add_constant(L, "CMD_NEW_INTERFACE", NL80211_CMD_NEW_INTERFACE);
    lua_add_constant(L, "CMD_DEL_INTERFACE", NL80211_CMD_DEL_INTERFACE);

    lua_add_constant(L, "CMD_GET_STATION", NL80211_CMD_GET_STATION);
    lua_add_constant(L, "CMD_SET_STATION", NL80211_CMD_SET_STATION);
    lua_add_constant(L, "CMD_NEW_STATION", NL80211_CMD_NEW_STATION);
    lua_add_constant(L, "CMD_DEL_STATION", NL80211_CMD_DEL_STATION);

    lua_add_constant(L, "CMD_SET_REG", NL80211_CMD_SET_REG);
    lua_add_constant(L, "CMD_REQ_SET_REG", NL80211_CMD_REQ_SET_REG);
    lua_add_constant(L, "CMD_GET_REG", NL80211_CMD_GET_REG);
    lua_add_constant(L, "CMD_GET_SCAN", NL80211_CMD_GET_SCAN);
    lua_add_constant(L, "CMD_TRIGGER_SCAN", NL80211_CMD_TRIGGER_SCAN);
    lua_add_constant(L, "CMD_NEW_SCAN_RESULTS", NL80211_CMD_NEW_SCAN_RESULTS);
    lua_add_constant(L, "CMD_SCAN_ABORTED", NL80211_CMD_SCAN_ABORTED);

    lua_add_constant(L, "CMD_RADAR_DETECT", NL80211_CMD_RADAR_DETECT);
    lua_add_constant(L, "CMD_CH_SWITCH_STARTED_NOTIFY", NL80211_CMD_CH_SWITCH_STARTED_NOTIFY);
    lua_add_constant(L, "CMD_ABORT_SCAN", NL80211_CMD_ABORT_SCAN);

    lua_add_constant(L, "ATTR_WIPHY", NL80211_ATTR_WIPHY);
    lua_add_constant(L, "ATTR_WIPHY_NAME", NL80211_ATTR_WIPHY_NAME);
    lua_add_constant(L, "ATTR_IFINDEX", NL80211_ATTR_IFINDEX);
    lua_add_constant(L, "ATTR_IFNAME", NL80211_ATTR_IFNAME);
    lua_add_constant(L, "ATTR_IFTYPE", NL80211_ATTR_IFTYPE);
    lua_add_constant(L, "ATTR_MAC", NL80211_ATTR_MAC);
    lua_add_constant(L, "ATTR_KEY_DATA", NL80211_ATTR_KEY_DATA);
    lua_add_constant(L, "ATTR_KEY_IDX", NL80211_ATTR_KEY_IDX);
    lua_add_constant(L, "ATTR_KEY_CIPHER", NL80211_ATTR_KEY_CIPHER);
    lua_add_constant(L, "ATTR_KEY_SEQ", NL80211_ATTR_KEY_SEQ);
    lua_add_constant(L, "ATTR_KEY_DEFAULT", NL80211_ATTR_KEY_DEFAULT);
    lua_add_constant(L, "ATTR_BEACON_INTERVAL", NL80211_ATTR_BEACON_INTERVAL);
    lua_add_constant(L, "ATTR_DTIM_PERIOD", NL80211_ATTR_DTIM_PERIOD);
    lua_add_constant(L, "ATTR_BEACON_HEAD", NL80211_ATTR_BEACON_HEAD);
    lua_add_constant(L, "ATTR_BEACON_TAIL", NL80211_ATTR_BEACON_TAIL);
    lua_add_constant(L, "ATTR_STA_AID", NL80211_ATTR_STA_AID);
    lua_add_constant(L, "ATTR_STA_FLAGS", NL80211_ATTR_STA_FLAGS);
    lua_add_constant(L, "ATTR_STA_LISTEN_INTERVAL", NL80211_ATTR_STA_LISTEN_INTERVAL);
    lua_add_constant(L, "ATTR_STA_SUPPORTED_RATES", NL80211_ATTR_STA_SUPPORTED_RATES);
    lua_add_constant(L, "ATTR_STA_VLAN", NL80211_ATTR_STA_VLAN);
    lua_add_constant(L, "ATTR_STA_INFO", NL80211_ATTR_STA_INFO);
    lua_add_constant(L, "ATTR_WIPHY_BANDS", NL80211_ATTR_WIPHY_BANDS);
    lua_add_constant(L, "ATTR_STA_PLINK_ACTION", NL80211_ATTR_STA_PLINK_ACTION);
    lua_add_constant(L, "ATTR_BSS_CTS_PROT", NL80211_ATTR_BSS_CTS_PROT);
    lua_add_constant(L, "ATTR_BSS_SHORT_PREAMBLE", NL80211_ATTR_BSS_SHORT_PREAMBLE);
    lua_add_constant(L, "ATTR_BSS_SHORT_SLOT_TIME", NL80211_ATTR_BSS_SHORT_SLOT_TIME);
    lua_add_constant(L, "ATTR_HT_CAPABILITY", NL80211_ATTR_HT_CAPABILITY);
    lua_add_constant(L, "ATTR_SUPPORTED_IFTYPES", NL80211_ATTR_SUPPORTED_IFTYPES);
    lua_add_constant(L, "ATTR_REG_ALPHA2", NL80211_ATTR_REG_ALPHA2);
    lua_add_constant(L, "ATTR_REG_RULES", NL80211_ATTR_REG_RULES);
    lua_add_constant(L, "ATTR_MESH_CONFIG", NL80211_ATTR_MESH_CONFIG);
    lua_add_constant(L, "ATTR_BSS_BASIC_RATES", NL80211_ATTR_BSS_BASIC_RATES);
    lua_add_constant(L, "ATTR_WIPHY_TXQ_PARAMS", NL80211_ATTR_WIPHY_TXQ_PARAMS);
    lua_add_constant(L, "ATTR_WIPHY_FREQ", NL80211_ATTR_WIPHY_FREQ);
    lua_add_constant(L, "ATTR_WIPHY_CHANNEL_TYPE", NL80211_ATTR_WIPHY_CHANNEL_TYPE);
    lua_add_constant(L, "ATTR_KEY_DEFAULT_MGMT", NL80211_ATTR_KEY_DEFAULT_MGMT);
    lua_add_constant(L, "ATTR_MGMT_SUBTYPE", NL80211_ATTR_MGMT_SUBTYPE);
    lua_add_constant(L, "ATTR_IE", NL80211_ATTR_IE);
    lua_add_constant(L, "ATTR_MAX_NUM_SCAN_SSIDS", NL80211_ATTR_MAX_NUM_SCAN_SSIDS);
    lua_add_constant(L, "ATTR_SCAN_FREQUENCIES", NL80211_ATTR_SCAN_FREQUENCIES);
    lua_add_constant(L, "ATTR_SCAN_SSIDS", NL80211_ATTR_SCAN_SSIDS);
    lua_add_constant(L, "ATTR_GENERATION", NL80211_ATTR_GENERATION);
    lua_add_constant(L, "ATTR_BSS", NL80211_ATTR_BSS);
    lua_add_constant(L, "ATTR_REG_INITIATOR", NL80211_ATTR_REG_INITIATOR);
    lua_add_constant(L, "ATTR_REG_TYPE", NL80211_ATTR_REG_TYPE);
    lua_add_constant(L, "ATTR_SUPPORTED_COMMANDS", NL80211_ATTR_SUPPORTED_COMMANDS);
    lua_add_constant(L, "ATTR_FRAME", NL80211_ATTR_FRAME);
    lua_add_constant(L, "ATTR_SSID", NL80211_ATTR_SSID);
    lua_add_constant(L, "ATTR_AUTH_TYPE", NL80211_ATTR_AUTH_TYPE);
    lua_add_constant(L, "ATTR_REASON_CODE", NL80211_ATTR_REASON_CODE);
    lua_add_constant(L, "ATTR_KEY_TYPE", NL80211_ATTR_KEY_TYPE);
    lua_add_constant(L, "ATTR_MAX_SCAN_IE_LEN", NL80211_ATTR_MAX_SCAN_IE_LEN);
    lua_add_constant(L, "ATTR_CIPHER_SUITES", NL80211_ATTR_CIPHER_SUITES);
    lua_add_constant(L, "ATTR_FREQ_BEFORE", NL80211_ATTR_FREQ_BEFORE);
    lua_add_constant(L, "ATTR_FREQ_AFTER", NL80211_ATTR_FREQ_AFTER);
    lua_add_constant(L, "ATTR_FREQ_FIXED", NL80211_ATTR_FREQ_FIXED);
    lua_add_constant(L, "ATTR_WIPHY_RETRY_SHORT", NL80211_ATTR_WIPHY_RETRY_SHORT);
    lua_add_constant(L, "ATTR_WIPHY_RETRY_LONG", NL80211_ATTR_WIPHY_RETRY_LONG);
    lua_add_constant(L, "ATTR_WIPHY_FRAG_THRESHOLD", NL80211_ATTR_WIPHY_FRAG_THRESHOLD);
    lua_add_constant(L, "ATTR_WIPHY_RTS_THRESHOLD", NL80211_ATTR_WIPHY_RTS_THRESHOLD);
    lua_add_constant(L, "ATTR_TIMED_OUT", NL80211_ATTR_TIMED_OUT);
    lua_add_constant(L, "ATTR_USE_MFP", NL80211_ATTR_USE_MFP);
    lua_add_constant(L, "ATTR_STA_FLAGS2", NL80211_ATTR_STA_FLAGS2);
    lua_add_constant(L, "ATTR_CONTROL_PORT", NL80211_ATTR_CONTROL_PORT);
    lua_add_constant(L, "ATTR_TESTDATA", NL80211_ATTR_TESTDATA);
    lua_add_constant(L, "ATTR_PRIVACY", NL80211_ATTR_PRIVACY);
    lua_add_constant(L, "ATTR_DISCONNECTED_BY_AP", NL80211_ATTR_DISCONNECTED_BY_AP);
    lua_add_constant(L, "ATTR_STATUS_CODE", NL80211_ATTR_STATUS_CODE);
    lua_add_constant(L, "ATTR_CIPHER_SUITES_PAIRWISE", NL80211_ATTR_CIPHER_SUITES_PAIRWISE);
    lua_add_constant(L, "ATTR_CIPHER_SUITE_GROUP", NL80211_ATTR_CIPHER_SUITE_GROUP);
    lua_add_constant(L, "ATTR_WPA_VERSIONS", NL80211_ATTR_WPA_VERSIONS);
    lua_add_constant(L, "ATTR_AKM_SUITES", NL80211_ATTR_AKM_SUITES);
    lua_add_constant(L, "ATTR_REQ_IE", NL80211_ATTR_REQ_IE);
    lua_add_constant(L, "ATTR_RESP_IE", NL80211_ATTR_RESP_IE);
    lua_add_constant(L, "ATTR_PREV_BSSID", NL80211_ATTR_PREV_BSSID);
    lua_add_constant(L, "ATTR_KEY", NL80211_ATTR_KEY);
    lua_add_constant(L, "ATTR_KEYS", NL80211_ATTR_KEYS);
    lua_add_constant(L, "ATTR_PID", NL80211_ATTR_PID);
    lua_add_constant(L, "ATTR_4ADDR", NL80211_ATTR_4ADDR);
    lua_add_constant(L, "ATTR_SURVEY_INFO", NL80211_ATTR_SURVEY_INFO);
    lua_add_constant(L, "ATTR_PMKID", NL80211_ATTR_PMKID);
    lua_add_constant(L, "ATTR_MAX_NUM_PMKIDS", NL80211_ATTR_MAX_NUM_PMKIDS);
    lua_add_constant(L, "ATTR_DURATION", NL80211_ATTR_DURATION);
    lua_add_constant(L, "ATTR_COOKIE", NL80211_ATTR_COOKIE);
    lua_add_constant(L, "ATTR_WIPHY_COVERAGE_CLASS", NL80211_ATTR_WIPHY_COVERAGE_CLASS);
    lua_add_constant(L, "ATTR_TX_RATES", NL80211_ATTR_TX_RATES);
    lua_add_constant(L, "ATTR_FRAME_MATCH", NL80211_ATTR_FRAME_MATCH);
    lua_add_constant(L, "ATTR_ACK", NL80211_ATTR_ACK);
    lua_add_constant(L, "ATTR_PS_STATE", NL80211_ATTR_PS_STATE);
    lua_add_constant(L, "ATTR_CQM", NL80211_ATTR_CQM);
    lua_add_constant(L, "ATTR_LOCAL_STATE_CHANGE", NL80211_ATTR_LOCAL_STATE_CHANGE);
    lua_add_constant(L, "ATTR_AP_ISOLATE", NL80211_ATTR_AP_ISOLATE);
    lua_add_constant(L, "ATTR_WIPHY_TX_POWER_SETTING", NL80211_ATTR_WIPHY_TX_POWER_SETTING);
    lua_add_constant(L, "ATTR_WIPHY_TX_POWER_LEVEL", NL80211_ATTR_WIPHY_TX_POWER_LEVEL);
    lua_add_constant(L, "ATTR_TX_FRAME_TYPES", NL80211_ATTR_TX_FRAME_TYPES);
    lua_add_constant(L, "ATTR_RX_FRAME_TYPES", NL80211_ATTR_RX_FRAME_TYPES);
    lua_add_constant(L, "ATTR_FRAME_TYPE", NL80211_ATTR_FRAME_TYPE);
    lua_add_constant(L, "ATTR_CONTROL_PORT_ETHERTYPE", NL80211_ATTR_CONTROL_PORT_ETHERTYPE);
    lua_add_constant(L, "ATTR_CONTROL_PORT_NO_ENCRYPT", NL80211_ATTR_CONTROL_PORT_NO_ENCRYPT);
    lua_add_constant(L, "ATTR_SUPPORT_IBSS_RSN", NL80211_ATTR_SUPPORT_IBSS_RSN);
    lua_add_constant(L, "ATTR_WIPHY_ANTENNA_TX", NL80211_ATTR_WIPHY_ANTENNA_TX);
    lua_add_constant(L, "ATTR_WIPHY_ANTENNA_RX", NL80211_ATTR_WIPHY_ANTENNA_RX);
    lua_add_constant(L, "ATTR_MCAST_RATE", NL80211_ATTR_MCAST_RATE);
    lua_add_constant(L, "ATTR_OFFCHANNEL_TX_OK", NL80211_ATTR_OFFCHANNEL_TX_OK);
    lua_add_constant(L, "ATTR_BSS_HT_OPMODE", NL80211_ATTR_BSS_HT_OPMODE);
    lua_add_constant(L, "ATTR_KEY_DEFAULT_TYPES", NL80211_ATTR_KEY_DEFAULT_TYPES);
    lua_add_constant(L, "ATTR_MAX_REMAIN_ON_CHANNEL_DURATION", NL80211_ATTR_MAX_REMAIN_ON_CHANNEL_DURATION);
    lua_add_constant(L, "ATTR_MESH_SETUP", NL80211_ATTR_MESH_SETUP);
    lua_add_constant(L, "ATTR_WIPHY_ANTENNA_AVAIL_TX", NL80211_ATTR_WIPHY_ANTENNA_AVAIL_TX);
    lua_add_constant(L, "ATTR_WIPHY_ANTENNA_AVAIL_RX", NL80211_ATTR_WIPHY_ANTENNA_AVAIL_RX);
    lua_add_constant(L, "ATTR_SUPPORT_MESH_AUTH", NL80211_ATTR_SUPPORT_MESH_AUTH);
    lua_add_constant(L, "ATTR_STA_PLINK_STATE", NL80211_ATTR_STA_PLINK_STATE);
    lua_add_constant(L, "ATTR_WOWLAN_TRIGGERS", NL80211_ATTR_WOWLAN_TRIGGERS);
    lua_add_constant(L, "ATTR_WOWLAN_TRIGGERS_SUPPORTED", NL80211_ATTR_WOWLAN_TRIGGERS_SUPPORTED);
    lua_add_constant(L, "ATTR_SCHED_SCAN_INTERVAL", NL80211_ATTR_SCHED_SCAN_INTERVAL);
    lua_add_constant(L, "ATTR_INTERFACE_COMBINATIONS", NL80211_ATTR_INTERFACE_COMBINATIONS);
    lua_add_constant(L, "ATTR_SOFTWARE_IFTYPES", NL80211_ATTR_SOFTWARE_IFTYPES);
    lua_add_constant(L, "ATTR_REKEY_DATA", NL80211_ATTR_REKEY_DATA);
    lua_add_constant(L, "ATTR_MAX_NUM_SCHED_SCAN_SSIDS", NL80211_ATTR_MAX_NUM_SCHED_SCAN_SSIDS);
    lua_add_constant(L, "ATTR_MAX_SCHED_SCAN_IE_LEN", NL80211_ATTR_MAX_SCHED_SCAN_IE_LEN);
    lua_add_constant(L, "ATTR_SCAN_SUPP_RATES", NL80211_ATTR_SCAN_SUPP_RATES);
    lua_add_constant(L, "ATTR_HIDDEN_SSID", NL80211_ATTR_HIDDEN_SSID);
    lua_add_constant(L, "ATTR_IE_PROBE_RESP", NL80211_ATTR_IE_PROBE_RESP);
    lua_add_constant(L, "ATTR_IE_ASSOC_RESP", NL80211_ATTR_IE_ASSOC_RESP);
    lua_add_constant(L, "ATTR_STA_WME", NL80211_ATTR_STA_WME);
    lua_add_constant(L, "ATTR_SUPPORT_AP_UAPSD", NL80211_ATTR_SUPPORT_AP_UAPSD);
    lua_add_constant(L, "ATTR_ROAM_SUPPORT", NL80211_ATTR_ROAM_SUPPORT);
    lua_add_constant(L, "ATTR_SCHED_SCAN_MATCH", NL80211_ATTR_SCHED_SCAN_MATCH);
    lua_add_constant(L, "ATTR_MAX_MATCH_SETS", NL80211_ATTR_MAX_MATCH_SETS);
    lua_add_constant(L, "ATTR_PMKSA_CANDIDATE", NL80211_ATTR_PMKSA_CANDIDATE);
    lua_add_constant(L, "ATTR_TX_NO_CCK_RATE", NL80211_ATTR_TX_NO_CCK_RATE);
    lua_add_constant(L, "ATTR_TDLS_ACTION", NL80211_ATTR_TDLS_ACTION);
    lua_add_constant(L, "ATTR_TDLS_DIALOG_TOKEN", NL80211_ATTR_TDLS_DIALOG_TOKEN);
    lua_add_constant(L, "ATTR_TDLS_OPERATION", NL80211_ATTR_TDLS_OPERATION);
    lua_add_constant(L, "ATTR_TDLS_SUPPORT", NL80211_ATTR_TDLS_SUPPORT);
    lua_add_constant(L, "ATTR_TDLS_EXTERNAL_SETUP", NL80211_ATTR_TDLS_EXTERNAL_SETUP);
    lua_add_constant(L, "ATTR_DEVICE_AP_SME", NL80211_ATTR_DEVICE_AP_SME);
    lua_add_constant(L, "ATTR_DONT_WAIT_FOR_ACK", NL80211_ATTR_DONT_WAIT_FOR_ACK);
    lua_add_constant(L, "ATTR_FEATURE_FLAGS", NL80211_ATTR_FEATURE_FLAGS);
    lua_add_constant(L, "ATTR_PROBE_RESP_OFFLOAD", NL80211_ATTR_PROBE_RESP_OFFLOAD);
    lua_add_constant(L, "ATTR_PROBE_RESP", NL80211_ATTR_PROBE_RESP);
    lua_add_constant(L, "ATTR_DFS_REGION", NL80211_ATTR_DFS_REGION);
    lua_add_constant(L, "ATTR_DISABLE_HT", NL80211_ATTR_DISABLE_HT);
    lua_add_constant(L, "ATTR_HT_CAPABILITY_MASK", NL80211_ATTR_HT_CAPABILITY_MASK);
    lua_add_constant(L, "ATTR_NOACK_MAP", NL80211_ATTR_NOACK_MAP);
    lua_add_constant(L, "ATTR_INACTIVITY_TIMEOUT", NL80211_ATTR_INACTIVITY_TIMEOUT);
    lua_add_constant(L, "ATTR_RX_SIGNAL_DBM", NL80211_ATTR_RX_SIGNAL_DBM);
    lua_add_constant(L, "ATTR_BG_SCAN_PERIOD", NL80211_ATTR_BG_SCAN_PERIOD);
    lua_add_constant(L, "ATTR_WDEV", NL80211_ATTR_WDEV);
    lua_add_constant(L, "ATTR_USER_REG_HINT_TYPE", NL80211_ATTR_USER_REG_HINT_TYPE);
    lua_add_constant(L, "ATTR_CONN_FAILED_REASON", NL80211_ATTR_CONN_FAILED_REASON);
    lua_add_constant(L, "ATTR_SAE_DATA", NL80211_ATTR_SAE_DATA);
    lua_add_constant(L, "ATTR_VHT_CAPABILITY", NL80211_ATTR_VHT_CAPABILITY);
    lua_add_constant(L, "ATTR_SCAN_FLAGS", NL80211_ATTR_SCAN_FLAGS);
    lua_add_constant(L, "ATTR_CHANNEL_WIDTH", NL80211_ATTR_CHANNEL_WIDTH);
    lua_add_constant(L, "ATTR_CENTER_FREQ1", NL80211_ATTR_CENTER_FREQ1);
    lua_add_constant(L, "ATTR_CENTER_FREQ2", NL80211_ATTR_CENTER_FREQ2);
    lua_add_constant(L, "ATTR_P2P_CTWINDOW", NL80211_ATTR_P2P_CTWINDOW);
    lua_add_constant(L, "ATTR_P2P_OPPPS", NL80211_ATTR_P2P_OPPPS);
    lua_add_constant(L, "ATTR_LOCAL_MESH_POWER_MODE", NL80211_ATTR_LOCAL_MESH_POWER_MODE);
    lua_add_constant(L, "ATTR_ACL_POLICY", NL80211_ATTR_ACL_POLICY);
    lua_add_constant(L, "ATTR_MAC_ADDRS", NL80211_ATTR_MAC_ADDRS);
    lua_add_constant(L, "ATTR_MAC_ACL_MAX", NL80211_ATTR_MAC_ACL_MAX);
    lua_add_constant(L, "ATTR_RADAR_EVENT", NL80211_ATTR_RADAR_EVENT);
    lua_add_constant(L, "ATTR_EXT_CAPA", NL80211_ATTR_EXT_CAPA);
    lua_add_constant(L, "ATTR_EXT_CAPA_MASK", NL80211_ATTR_EXT_CAPA_MASK);
    lua_add_constant(L, "ATTR_STA_CAPABILITY", NL80211_ATTR_STA_CAPABILITY);
    lua_add_constant(L, "ATTR_STA_EXT_CAPABILITY", NL80211_ATTR_STA_EXT_CAPABILITY);
    lua_add_constant(L, "ATTR_PROTOCOL_FEATURES", NL80211_ATTR_PROTOCOL_FEATURES);
    lua_add_constant(L, "ATTR_SPLIT_WIPHY_DUMP", NL80211_ATTR_SPLIT_WIPHY_DUMP);
    lua_add_constant(L, "ATTR_DISABLE_VHT", NL80211_ATTR_DISABLE_VHT);
    lua_add_constant(L, "ATTR_VHT_CAPABILITY_MASK", NL80211_ATTR_VHT_CAPABILITY_MASK);
    lua_add_constant(L, "ATTR_MDID", NL80211_ATTR_MDID);
    lua_add_constant(L, "ATTR_IE_RIC", NL80211_ATTR_IE_RIC);
    lua_add_constant(L, "ATTR_CRIT_PROT_ID", NL80211_ATTR_CRIT_PROT_ID);
    lua_add_constant(L, "ATTR_MAX_CRIT_PROT_DURATION", NL80211_ATTR_MAX_CRIT_PROT_DURATION);
    lua_add_constant(L, "ATTR_PEER_AID", NL80211_ATTR_PEER_AID);
    lua_add_constant(L, "ATTR_COALESCE_RULE", NL80211_ATTR_COALESCE_RULE);
    lua_add_constant(L, "ATTR_CH_SWITCH_COUNT", NL80211_ATTR_CH_SWITCH_COUNT);
    lua_add_constant(L, "ATTR_CH_SWITCH_BLOCK_TX", NL80211_ATTR_CH_SWITCH_BLOCK_TX);
    lua_add_constant(L, "ATTR_CSA_IES", NL80211_ATTR_CSA_IES);
    lua_add_constant(L, "ATTR_CSA_C_OFF_BEACON", NL80211_ATTR_CSA_C_OFF_BEACON);
    lua_add_constant(L, "ATTR_CSA_C_OFF_PRESP", NL80211_ATTR_CSA_C_OFF_PRESP);
    lua_add_constant(L, "ATTR_RXMGMT_FLAGS", NL80211_ATTR_RXMGMT_FLAGS);
    lua_add_constant(L, "ATTR_STA_SUPPORTED_CHANNELS", NL80211_ATTR_STA_SUPPORTED_CHANNELS);
    lua_add_constant(L, "ATTR_STA_SUPPORTED_OPER_CLASSES", NL80211_ATTR_STA_SUPPORTED_OPER_CLASSES);
    lua_add_constant(L, "ATTR_HANDLE_DFS", NL80211_ATTR_HANDLE_DFS);
    lua_add_constant(L, "ATTR_SUPPORT_5_MHZ", NL80211_ATTR_SUPPORT_5_MHZ);
    lua_add_constant(L, "ATTR_SUPPORT_10_MHZ", NL80211_ATTR_SUPPORT_10_MHZ);
    lua_add_constant(L, "ATTR_OPMODE_NOTIF", NL80211_ATTR_OPMODE_NOTIF);
    lua_add_constant(L, "ATTR_VENDOR_ID", NL80211_ATTR_VENDOR_ID);
    lua_add_constant(L, "ATTR_VENDOR_SUBCMD", NL80211_ATTR_VENDOR_SUBCMD);
    lua_add_constant(L, "ATTR_VENDOR_DATA", NL80211_ATTR_VENDOR_DATA);
    lua_add_constant(L, "ATTR_VENDOR_EVENTS", NL80211_ATTR_VENDOR_EVENTS);
    lua_add_constant(L, "ATTR_MAC_HINT", NL80211_ATTR_MAC_HINT);
    lua_add_constant(L, "ATTR_WIPHY_FREQ_HINT", NL80211_ATTR_WIPHY_FREQ_HINT);
    lua_add_constant(L, "ATTR_MAX_AP_ASSOC_STA", NL80211_ATTR_MAX_AP_ASSOC_STA);
    lua_add_constant(L, "ATTR_SOCKET_OWNER", NL80211_ATTR_SOCKET_OWNER);
    lua_add_constant(L, "ATTR_CSA_C_OFFSETS_TX", NL80211_ATTR_CSA_C_OFFSETS_TX);
    lua_add_constant(L, "ATTR_MAX_CSA_COUNTERS", NL80211_ATTR_MAX_CSA_COUNTERS);
    lua_add_constant(L, "ATTR_USE_RRM", NL80211_ATTR_USE_RRM);
    lua_add_constant(L, "ATTR_WIPHY_DYN_ACK", NL80211_ATTR_WIPHY_DYN_ACK);
    lua_add_constant(L, "ATTR_TSID", NL80211_ATTR_TSID);
    lua_add_constant(L, "ATTR_USER_PRIO", NL80211_ATTR_USER_PRIO);
    lua_add_constant(L, "ATTR_ADMITTED_TIME", NL80211_ATTR_ADMITTED_TIME);
    lua_add_constant(L, "ATTR_SMPS_MODE", NL80211_ATTR_SMPS_MODE);
    lua_add_constant(L, "ATTR_OPER_CLASS", NL80211_ATTR_OPER_CLASS);
    lua_add_constant(L, "ATTR_MAC_MASK", NL80211_ATTR_MAC_MASK);
    lua_add_constant(L, "ATTR_WIPHY_SELF_MANAGED_REG", NL80211_ATTR_WIPHY_SELF_MANAGED_REG);
    lua_add_constant(L, "ATTR_EXT_FEATURES", NL80211_ATTR_EXT_FEATURES);
    lua_add_constant(L, "ATTR_NETNS_FD", NL80211_ATTR_NETNS_FD);
    lua_add_constant(L, "ATTR_SCHED_SCAN_DELAY", NL80211_ATTR_SCHED_SCAN_DELAY);
    lua_add_constant(L, "ATTR_REG_INDOOR", NL80211_ATTR_REG_INDOOR);
    lua_add_constant(L, "ATTR_BSS_SELECT", NL80211_ATTR_BSS_SELECT);

    lua_add_constant(L, "IFTYPE_UNSPECIFIED", NL80211_IFTYPE_UNSPECIFIED);
    lua_add_constant(L, "IFTYPE_ADHOC", NL80211_IFTYPE_ADHOC);
    lua_add_constant(L, "IFTYPE_STATION", NL80211_IFTYPE_STATION);
    lua_add_constant(L, "IFTYPE_AP", NL80211_IFTYPE_AP);
    lua_add_constant(L, "IFTYPE_AP_VLAN", NL80211_IFTYPE_AP_VLAN);
    lua_add_constant(L, "IFTYPE_WDS", NL80211_IFTYPE_WDS);
    lua_add_constant(L, "IFTYPE_MONITOR", NL80211_IFTYPE_MONITOR);
    lua_add_constant(L, "IFTYPE_MESH_POINT", NL80211_IFTYPE_MESH_POINT);
    lua_add_constant(L, "IFTYPE_P2P_CLIENT", NL80211_IFTYPE_P2P_CLIENT);
    lua_add_constant(L, "IFTYPE_P2P_GO", NL80211_IFTYPE_P2P_GO);
    lua_add_constant(L, "IFTYPE_P2P_DEVICE", NL80211_IFTYPE_P2P_DEVICE);
    lua_add_constant(L, "IFTYPE_OCB", NL80211_IFTYPE_OCB);

    lua_add_constant(L, "CHAN_WIDTH_20_NOHT", NL80211_CHAN_WIDTH_20_NOHT);
    lua_add_constant(L, "CHAN_WIDTH_20", NL80211_CHAN_WIDTH_20);
    lua_add_constant(L, "CHAN_WIDTH_40", NL80211_CHAN_WIDTH_40);
    lua_add_constant(L, "CHAN_WIDTH_80", NL80211_CHAN_WIDTH_80);
    lua_add_constant(L, "CHAN_WIDTH_80P80", NL80211_CHAN_WIDTH_80P80);
    lua_add_constant(L, "CHAN_WIDTH_160", NL80211_CHAN_WIDTH_160);
    lua_add_constant(L, "CHAN_WIDTH_5", NL80211_CHAN_WIDTH_5);
    lua_add_constant(L, "CHAN_WIDTH_10", NL80211_CHAN_WIDTH_10);

    lua_add_constant(L, "CHAN_NO_HT", NL80211_CHAN_NO_HT);
    lua_add_constant(L, "CHAN_HT20", NL80211_CHAN_HT20);
    lua_add_constant(L, "CHAN_HT40MINUS", NL80211_CHAN_HT40MINUS);
    lua_add_constant(L, "CHAN_HT40PLUS", NL80211_CHAN_HT40PLUS);

    lua_add_constant(L, "BAND_ATTR_FREQS", NL80211_BAND_ATTR_FREQS);
    lua_add_constant(L, "BAND_ATTR_RATES", NL80211_BAND_ATTR_RATES);
    lua_add_constant(L, "BAND_ATTR_HT_MCS_SET", NL80211_BAND_ATTR_HT_MCS_SET);
    lua_add_constant(L, "BAND_ATTR_HT_CAPA", NL80211_BAND_ATTR_HT_CAPA);
    lua_add_constant(L, "BAND_ATTR_HT_AMPDU_FACTOR", NL80211_BAND_ATTR_HT_AMPDU_FACTOR);
    lua_add_constant(L, "BAND_ATTR_HT_AMPDU_DENSITY", NL80211_BAND_ATTR_HT_AMPDU_DENSITY);
    lua_add_constant(L, "BAND_ATTR_VHT_MCS_SET", NL80211_BAND_ATTR_VHT_MCS_SET);
    lua_add_constant(L, "BAND_ATTR_VHT_CAPA", NL80211_BAND_ATTR_VHT_CAPA);

    lua_add_constant(L, "FREQUENCY_ATTR_FREQ", NL80211_FREQUENCY_ATTR_FREQ);
    lua_add_constant(L, "FREQUENCY_ATTR_DISABLED", NL80211_FREQUENCY_ATTR_DISABLED);
    lua_add_constant(L, "FREQUENCY_ATTR_NO_IR", NL80211_FREQUENCY_ATTR_NO_IR);
    lua_add_constant(L, "FREQUENCY_ATTR_NO_IBSS", __NL80211_FREQUENCY_ATTR_NO_IBSS);
    lua_add_constant(L, "FREQUENCY_ATTR_RADAR", NL80211_FREQUENCY_ATTR_RADAR);
    lua_add_constant(L, "FREQUENCY_ATTR_MAX_TX_POWER", NL80211_FREQUENCY_ATTR_MAX_TX_POWER);
    lua_add_constant(L, "FREQUENCY_ATTR_DFS_STATE", NL80211_FREQUENCY_ATTR_DFS_STATE);
    lua_add_constant(L, "FREQUENCY_ATTR_DFS_TIME", NL80211_FREQUENCY_ATTR_DFS_TIME);
    lua_add_constant(L, "FREQUENCY_ATTR_NO_HT40_MINUS", NL80211_FREQUENCY_ATTR_NO_HT40_MINUS);
    lua_add_constant(L, "FREQUENCY_ATTR_NO_HT40_PLUS", NL80211_FREQUENCY_ATTR_NO_HT40_PLUS);
    lua_add_constant(L, "FREQUENCY_ATTR_NO_80MHZ", NL80211_FREQUENCY_ATTR_NO_80MHZ);
    lua_add_constant(L, "FREQUENCY_ATTR_NO_160MHZ", NL80211_FREQUENCY_ATTR_NO_160MHZ);
    lua_add_constant(L, "FREQUENCY_ATTR_DFS_CAC_TIME", NL80211_FREQUENCY_ATTR_DFS_CAC_TIME);
    lua_add_constant(L, "FREQUENCY_ATTR_INDOOR_ONLY", NL80211_FREQUENCY_ATTR_INDOOR_ONLY);
    lua_add_constant(L, "FREQUENCY_ATTR_IR_CONCURRENT", NL80211_FREQUENCY_ATTR_IR_CONCURRENT);
    lua_add_constant(L, "FREQUENCY_ATTR_NO_20MHZ", NL80211_FREQUENCY_ATTR_NO_20MHZ);
    lua_add_constant(L, "FREQUENCY_ATTR_NO_10MHZ", NL80211_FREQUENCY_ATTR_NO_10MHZ);

    lua_add_constant(L, "BSS_BSSID", NL80211_BSS_BSSID);
    lua_add_constant(L, "BSS_FREQUENCY", NL80211_BSS_FREQUENCY);
    lua_add_constant(L, "BSS_TSF", NL80211_BSS_TSF);
    lua_add_constant(L, "BSS_BEACON_INTERVAL", NL80211_BSS_BEACON_INTERVAL);
    lua_add_constant(L, "BSS_CAPABILITY", NL80211_BSS_CAPABILITY);
    lua_add_constant(L, "BSS_INFORMATION_ELEMENTS", NL80211_BSS_INFORMATION_ELEMENTS);
    lua_add_constant(L, "BSS_SIGNAL_MBM", NL80211_BSS_SIGNAL_MBM);
    lua_add_constant(L, "BSS_SIGNAL_UNSPEC", NL80211_BSS_SIGNAL_UNSPEC);
    lua_add_constant(L, "BSS_STATUS", NL80211_BSS_STATUS);
    lua_add_constant(L, "BSS_SEEN_MS_AGO", NL80211_BSS_SEEN_MS_AGO);
    lua_add_constant(L, "BSS_BEACON_IES", NL80211_BSS_BEACON_IES);
    lua_add_constant(L, "BSS_CHAN_WIDTH", NL80211_BSS_CHAN_WIDTH);
    lua_add_constant(L, "BSS_BEACON_TSF", NL80211_BSS_BEACON_TSF);
    lua_add_constant(L, "BSS_PRESP_DATA", NL80211_BSS_PRESP_DATA);

    lua_add_constant(L, "STA_INFO_INACTIVE_TIME", NL80211_STA_INFO_INACTIVE_TIME);
    lua_add_constant(L, "STA_INFO_RX_BYTES", NL80211_STA_INFO_RX_BYTES);
    lua_add_constant(L, "STA_INFO_TX_BYTES", NL80211_STA_INFO_TX_BYTES);
    lua_add_constant(L, "STA_INFO_LLID", NL80211_STA_INFO_LLID);
    lua_add_constant(L, "STA_INFO_PLID", NL80211_STA_INFO_PLID);
    lua_add_constant(L, "STA_INFO_PLINK_STATE", NL80211_STA_INFO_PLINK_STATE);
    lua_add_constant(L, "STA_INFO_SIGNAL", NL80211_STA_INFO_SIGNAL);
    lua_add_constant(L, "STA_INFO_TX_BITRATE", NL80211_STA_INFO_TX_BITRATE);
    lua_add_constant(L, "STA_INFO_RX_PACKETS", NL80211_STA_INFO_RX_PACKETS);
    lua_add_constant(L, "STA_INFO_TX_PACKETS", NL80211_STA_INFO_TX_PACKETS);
    lua_add_constant(L, "STA_INFO_TX_RETRIES", NL80211_STA_INFO_TX_RETRIES);
    lua_add_constant(L, "STA_INFO_TX_FAILED", NL80211_STA_INFO_TX_FAILED);
    lua_add_constant(L, "STA_INFO_SIGNAL_AVG", NL80211_STA_INFO_SIGNAL_AVG);
    lua_add_constant(L, "STA_INFO_RX_BITRATE", NL80211_STA_INFO_RX_BITRATE);
    lua_add_constant(L, "STA_INFO_BSS_PARAM", NL80211_STA_INFO_BSS_PARAM);
    lua_add_constant(L, "STA_INFO_CONNECTED_TIME", NL80211_STA_INFO_CONNECTED_TIME);
    lua_add_constant(L, "STA_INFO_STA_FLAGS", NL80211_STA_INFO_STA_FLAGS);
    lua_add_constant(L, "STA_INFO_BEACON_LOSS", NL80211_STA_INFO_BEACON_LOSS);
    lua_add_constant(L, "STA_INFO_T_OFFSET", NL80211_STA_INFO_T_OFFSET);
    lua_add_constant(L, "STA_INFO_LOCAL_PM", NL80211_STA_INFO_LOCAL_PM);
    lua_add_constant(L, "STA_INFO_PEER_PM", NL80211_STA_INFO_PEER_PM);
    lua_add_constant(L, "STA_INFO_NONPEER_PM", NL80211_STA_INFO_NONPEER_PM);
    lua_add_constant(L, "STA_INFO_RX_BYTES64", NL80211_STA_INFO_RX_BYTES64);
    lua_add_constant(L, "STA_INFO_TX_BYTES64", NL80211_STA_INFO_TX_BYTES64);
    lua_add_constant(L, "STA_INFO_CHAIN_SIGNAL", NL80211_STA_INFO_CHAIN_SIGNAL);
    lua_add_constant(L, "STA_INFO_CHAIN_SIGNAL_AVG", NL80211_STA_INFO_CHAIN_SIGNAL_AVG);
    lua_add_constant(L, "STA_INFO_EXPECTED_THROUGHPUT", NL80211_STA_INFO_EXPECTED_THROUGHPUT);
    lua_add_constant(L, "STA_INFO_RX_DROP_MISC", NL80211_STA_INFO_RX_DROP_MISC);
    lua_add_constant(L, "STA_INFO_BEACON_RX", NL80211_STA_INFO_BEACON_RX);
    lua_add_constant(L, "STA_INFO_BEACON_SIGNAL_AVG", NL80211_STA_INFO_BEACON_SIGNAL_AVG);
    lua_add_constant(L, "STA_INFO_TID_STATS", NL80211_STA_INFO_TID_STATS);
    lua_add_constant(L, "STA_INFO_RX_DURATION", NL80211_STA_INFO_RX_DURATION);
    lua_add_constant(L, "STA_INFO_PAD", NL80211_STA_INFO_PAD);
    lua_add_constant(L, "STA_INFO_ACK_SIGNAL", NL80211_STA_INFO_ACK_SIGNAL);
    lua_add_constant(L, "STA_INFO_ACK_SIGNAL_AVG", NL80211_STA_INFO_ACK_SIGNAL_AVG);
    lua_add_constant(L, "STA_INFO_RX_MPDUS", NL80211_STA_INFO_RX_MPDUS);
    lua_add_constant(L, "STA_INFO_FCS_ERROR_COUNT", NL80211_STA_INFO_FCS_ERROR_COUNT);
    lua_add_constant(L, "STA_INFO_CONNECTED_TO_GATE", NL80211_STA_INFO_CONNECTED_TO_GATE);
    lua_add_constant(L, "STA_INFO_TX_DURATION", NL80211_STA_INFO_TX_DURATION);
    lua_add_constant(L, "STA_INFO_AIRTIME_WEIGHT", NL80211_STA_INFO_AIRTIME_WEIGHT);
    lua_add_constant(L, "STA_INFO_AIRTIME_LINK_METRIC", NL80211_STA_INFO_AIRTIME_LINK_METRIC);
    lua_add_constant(L, "STA_INFO_ASSOC_AT_BOOTTIME", NL80211_STA_INFO_ASSOC_AT_BOOTTIME);

    lua_add_constant(L, "RATE_INFO_BITRATE", NL80211_RATE_INFO_BITRATE);
    lua_add_constant(L, "RATE_INFO_MCS", NL80211_RATE_INFO_MCS);
    lua_add_constant(L, "RATE_INFO_40_MHZ_WIDTH", NL80211_RATE_INFO_40_MHZ_WIDTH);
    lua_add_constant(L, "RATE_INFO_SHORT_GI", NL80211_RATE_INFO_SHORT_GI);
    lua_add_constant(L, "RATE_INFO_BITRATE32", NL80211_RATE_INFO_BITRATE32);
    lua_add_constant(L, "RATE_INFO_VHT_MCS", NL80211_RATE_INFO_VHT_MCS);
    lua_add_constant(L, "RATE_INFO_VHT_NSS", NL80211_RATE_INFO_VHT_NSS);
    lua_add_constant(L, "RATE_INFO_80_MHZ_WIDTH", NL80211_RATE_INFO_80_MHZ_WIDTH);
    lua_add_constant(L, "RATE_INFO_80P80_MHZ_WIDTH", NL80211_RATE_INFO_80P80_MHZ_WIDTH);
    lua_add_constant(L, "RATE_INFO_160_MHZ_WIDTH", NL80211_RATE_INFO_160_MHZ_WIDTH);
    lua_add_constant(L, "RATE_INFO_10_MHZ_WIDTH", NL80211_RATE_INFO_10_MHZ_WIDTH);
    lua_add_constant(L, "RATE_INFO_5_MHZ_WIDTH", NL80211_RATE_INFO_5_MHZ_WIDTH);
    lua_add_constant(L, "RATE_INFO_HE_MCS", NL80211_RATE_INFO_HE_MCS);
    lua_add_constant(L, "RATE_INFO_HE_NSS", NL80211_RATE_INFO_HE_NSS);
    lua_add_constant(L, "RATE_INFO_HE_GI", NL80211_RATE_INFO_HE_GI);
    lua_add_constant(L, "RATE_INFO_HE_DCM", NL80211_RATE_INFO_HE_DCM);
    lua_add_constant(L, "RATE_INFO_320_MHZ_WIDTH", NL80211_RATE_INFO_320_MHZ_WIDTH);
    lua_add_constant(L, "RATE_INFO_EHT_MCS", NL80211_RATE_INFO_EHT_MCS);
    lua_add_constant(L, "RATE_INFO_EHT_NSS", NL80211_RATE_INFO_EHT_NSS);
    lua_add_constant(L, "RATE_INFO_EHT_GI", NL80211_RATE_INFO_EHT_GI);

    lua_pushcfunction(L, parse_sta_flag_update);
    lua_setfield(L, -2, "parse_sta_flag_update");

    return 1;
}
