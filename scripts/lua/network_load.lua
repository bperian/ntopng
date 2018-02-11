--
-- (C) 2013-17 - ntop.org
--

dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path

require "lua_utils"
json = require("dkjson")

--sendHTTPContentTypeHeader('text/html')
sendHTTPHeader('application/json')

function dumpInterfaceStats(interface_name)
   interface.select(interface_name)

   local ifstats = interface.getStats()
   local stats = interface.getFlowsStats()

   local res = {}
   if(ifstats ~= nil) then
      uptime = ntop.getUptime()
      prefs = ntop.getPrefs()

      -- Round up
      hosts_pctg = math.floor(1+((ifstats.stats.hosts*100)/prefs.max_num_hosts))
      flows_pctg = math.floor(1+((ifstats.stats.flows*100)/prefs.max_num_flows))

      res["ifname"]  = interface_name
      res["speed"]  = getInterfaceSpeed(ifstats)
      -- network load is used by web pages that are shown to the user
      -- so we must return statistics since the latest (possible) reset
      res["packets"] = ifstats.stats_since_reset.packets
      res["bytes"]   = ifstats.stats_since_reset.bytes
      res["drops"]   = ifstats.stats_since_reset.drops
      
      if prefs.is_dump_flows_to_es_enabled == true
       or prefs.is_dump_flows_to_mysql_enabled == true 
	or prefs.is_dump_flows_to_ls_enabled then
	  res["flow_export_drops"]  = ifstats.stats_since_reset.flow_export_drops
	  res["flow_export_rate"]   = ifstats.stats_since_reset.flow_export_rate
	  res["flow_export_count"]  = ifstats.stats_since_reset.flow_export_count
      end

      if prefs.are_alerts_enabled == true then
	 local alert_cache = interface.getCachedNumAlerts() or {}
	 res["engaged_alerts"]     = alert_cache["num_alerts_engaged"] or 0
	 res["alerts_stored"]      = alert_cache["alerts_stored"] or 0
      end

      res["num_flows"]        = ifstats.stats.flows
      res["num_hosts"]        = ifstats.stats.hosts
      res["num_local_hosts"]  = ifstats.stats.local_hosts
      res["num_devices"]      = ifstats.stats.devices

      res["epoch"]      = os.time()
      res["localtime"]  = os.date("%H:%M:%S %z", res["epoch"])
      res["uptime"]     = secondsToTime(uptime)
      res["system_host_stats"] = ntop.systemHostStat()
      res["hosts_pctg"] = hosts_pctg
      res["flows_pctg"] = flows_pctg
      res["remote_pps"] = ifstats.remote_pps
      res["remote_bps"] = ifstats.remote_bps
      res["is_view"]    = ifstats.isView

      res["local2remote"] = ifstats["localstats"]["bytes"]["local2remote"]
      res["remote2local"] = ifstats["localstats"]["bytes"]["remote2local"]

      if ntop.isnEdge() then
        res["bytes_upload"] = ifstats["eth"]["egress"]["bytes"]
        res["bytes_download"] = ifstats["eth"]["ingress"]["bytes"]
      end

      if(ifstats.zmqRecvStats ~= nil) then
	 res["zmqRecvStats"] = {}
	 res["zmqRecvStats"]["flows"] = ifstats.zmqRecvStats.flows
	 res["zmqRecvStats"]["events"] = ifstats.zmqRecvStats.events
	 res["zmqRecvStats"]["counters"] = ifstats.zmqRecvStats.counters
	 res["zmqRecvStats"]["zmq_msg_drops"] = ifstats.zmqRecvStats.zmq_msg_drops

	 res["zmq.num_flow_exports"] = ifstats["zmq.num_flow_exports"] or 0
	 res["zmq.num_exporters"] = ifstats["zmq.num_exporters"] or 0
      end
      
      res["tcpPacketStats"] = {}
      res["tcpPacketStats"]["retransmissions"] = ifstats.tcpPacketStats.retransmissions
      res["tcpPacketStats"]["out_of_order"]    = ifstats.tcpPacketStats.out_of_order
      res["tcpPacketStats"]["lost"]            = ifstats.tcpPacketStats.lost
      
      if(ifstats["bridge.device_a"] ~= nil) then
	 res["a_to_b_in_pkts"]       = ifstats["bridge.a_to_b.in_pkts"]
	 res["a_to_b_in_bytes"]      = ifstats["bridge.a_to_b.in_bytes"]
	 res["a_to_b_out_pkts"]      = ifstats["bridge.a_to_b.out_pkts"]
	 res["a_to_b_out_bytes"]     = ifstats["bridge.a_to_b.out_bytes"]
	 res["a_to_b_filtered_pkts"] = ifstats["bridge.a_to_b.filtered_pkts"]
	 res["a_to_b_shaped_pkts"]   = ifstats["bridge.a_to_b.shaped_pkts"]

	 res["b_to_a_in_pkts"]       = ifstats["bridge.b_to_a.in_pkts"]
	 res["b_to_a_in_bytes"]      = ifstats["bridge.b_to_a.in_bytes"]
	 res["b_to_a_out_pkts"]      = ifstats["bridge.b_to_a.out_pkts"]
	 res["b_to_a_out_bytes"]     = ifstats["bridge.b_to_a.out_bytes"]
	 res["b_to_a_filtered_pkts"] = ifstats["bridge.b_to_a.filtered_pkts"]
	 res["b_to_a_shaped_pkts"]   = ifstats["bridge.b_to_a.shaped_pkts"]

	 res["a_to_b_num_pkts_send_buffer_full"] = ifstats["bridge.a_to_b.num_pkts_send_buffer_full"]
	 res["a_to_b_num_pkts_send_error"]       = ifstats["bridge.a_to_b.num_pkts_send_error"]
	 res["b_to_a_num_pkts_send_buffer_full"] = ifstats["bridge.b_to_a.num_pkts_send_buffer_full"]
	 res["b_to_a_num_pkts_send_error"]       = ifstats["bridge.b_to_a.num_pkts_send_error"] 
      end

      if(ifstats["profiles"] ~= nil) then
	 res["profiles"] = ifstats["profiles"]
      end

      res["breed"] = stats["breeds"]
   end
   return res
end

-- ###############################

local res = {}
if(_GET["iffilter"] == "all") then
   for _, ifname in pairs(interface.getIfNames()) do
      local ifid = getInterfaceId(ifname)
      -- ifid in the key must be a string or json.encode will think
      -- its a lua array and will look for integers starting at one
      res[ifid..""] = dumpInterfaceStats(ifname)
   end
else
   res = dumpInterfaceStats(ifname)
end
print(json.encode(res))
