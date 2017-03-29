--
-- (C) 2013-17 - ntop.org
--

dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path

if (ntop.isPro()) then
  package.path = dirs.installdir .. "/pro/scripts/callbacks/?.lua;" .. package.path
  require("5min")

  package.path = dirs.installdir .. "/pro/scripts/lua/modules/?.lua;" .. package.path
  require "snmp_utils"
end

require "lua_utils"
require "graph_utils"
require "alert_utils"
local host_pools_utils = require "host_pools_utils"
local callback_utils = require "callback_utils"

local when = os.time()
local verbose = ntop.verboseTrace()

-- We must complete within the 5 minutes
local time_threshold = when - (when % 300) + 300 - 10 -- safe margin

-- ########################################################

local host_rrd_creation = ntop.getCache("ntopng.prefs.host_rrd_creation")
local host_ndpi_rrd_creation = ntop.getCache("ntopng.prefs.host_ndpi_rrd_creation")
local host_categories_rrd_creation = ntop.getCache("ntopng.prefs.host_categories_rrd_creation")
local flow_devices_rrd_creation = ntop.getCache("ntopng.prefs.flow_device_port_rrd_creation")
local host_pools_rrd_creation = ntop.getCache("ntopng.prefs.host_pools_rrd_creation")
local snmp_devices_rrd_creation = ntop.getCache("ntopng.prefs.snmp_devices_rrd_creation")
local asn_rrd_creation = ntop.getCache("ntopng.prefs.asn_rrd_creation")

if(tostring(flow_devices_rrd_creation) == "1" and ntop.isEnterprise() == false) then
   flow_devices_rrd_creation = "0"
end

if(tostring(snmp_devices_rrd_creation) == "1" and ntop.isEnterprise() == false) then
   snmp_devices_rrd_creation = "0"
end

local ifnames = interface.getIfNames()
local prefs = ntop.getPrefs()

-- Scan "5 minute" alerts
callback_utils.foreachInterface(ifnames, verbose, function(ifname, ifstats)
   scanAlerts("5mins", ifname)
end)

-- ########################################################

callback_utils.foreachInterface(ifnames, verbose, function(_ifname, ifstats)
  basedir = fixPath(dirs.workingdir .. "/" .. ifstats.id .. "/rrd")
  for k in pairs(ifstats["ndpi"]) do
    v = ifstats["ndpi"][k]["bytes.sent"]+ifstats["ndpi"][k]["bytes.rcvd"]
      if(verbose) then print("["..__FILE__()..":"..__LINE__().."] ".._ifname..": "..k.."="..v.."\n") end

    name = fixPath(basedir .. "/"..k..".rrd")
    createSingleRRDcounter(name, 300, verbose)
    ntop.rrd_update(name, "N:".. tolongint(v))
  end

  if (not ntop.exists(fixPath(basedir.."/localstats/"))) then
    if(verbose) then print("\n["..__FILE__()..":"..__LINE__().."] Creating localstats directory ", fixPath(basedir.."/localstats"), '\n') end
    ntop.mkdir(fixPath(basedir.."/localstats/"))
  end

  -- IN/OUT counters
  if (ifstats["localstats"]["bytes"]["local2remote"] > 0) then
    name = fixPath(basedir .. "/localstats/local2remote.rrd")
    createSingleRRDcounter(name, 300, verbose)
    ntop.rrd_update(name, "N:"..tolongint(ifstats["localstats"]["bytes"]["local2remote"]))
    if (verbose) then print("\n["..__FILE__()..":"..__LINE__().."] Updating RRD [".. ifstats.name .."] "..name..'\n') end
  end

  if (ifstats["localstats"]["bytes"]["remote2local"] > 0) then
    name = fixPath(basedir .. "/localstats/remote2local.rrd")
    createSingleRRDcounter(name, 300, verbose)
    ntop.rrd_update(name, "N:"..tolongint(ifstats["localstats"]["bytes"]["remote2local"]))
    if (verbose) then print("\n["..__FILE__()..":"..__LINE__().."] Updating RRD [".. ifstats.name .."] "..name..'\n') end
  end

  -- Save hosts stats
  if((host_rrd_creation ~= "0") or (asn_rrd_creation ~= "0")) then
    local networks_aggr = {}
    local vlans_aggr    = {}
    local asn_aggr      = {}

    local in_time = callback_utils.foreachHost(_ifname, verbose, function (hostname, host, hostbase)
      -- Aggregate ASN
      local host_asn = host["asn"]

      if ((not isEmptyString(host_asn)) and (tonumber(host_asn) ~= 0)) then
        asn_aggr[host_asn] = asn_aggr[host_asn] or {}
        asn_aggr[host_asn]["bytes.sent"] = (asn_aggr[host_asn]["bytes.sent"] or 0) + host["bytes.sent"]
        asn_aggr[host_asn]["bytes.rcvd"] = (asn_aggr[host_asn]["bytes.rcvd"] or 0) + host["bytes.rcvd"]
        asn_aggr[host_asn]["ndpi"] = asn_aggr[host_asn]["ndpi"] or {}

        for k in pairs(host["ndpi"]) do
          asn_aggr[host_asn]["ndpi"][k] = asn_aggr[host_asn]["ndpi"][k] or {}
          asn_aggr[host_asn]["ndpi"][k]["bytes.sent"] = (asn_aggr[host_asn]["ndpi"][k]["bytes.sent"] or 0) + host["ndpi"][k]["bytes.sent"]
          asn_aggr[host_asn]["ndpi"][k]["bytes.rcvd"] = (asn_aggr[host_asn]["ndpi"][k]["bytes.rcvd"] or 0) + host["ndpi"][k]["bytes.rcvd"]
        end
      end

      if host_rrd_creation ~= "1" then
        -- only ASN enabled
        return
      end

      -- Aggregate VLAN stats
      local host_vlan = host["vlan"]

      if host_vlan ~= nil and host_vlan ~= 0 then
        if vlans_aggr[host_vlan] == nil then
          vlans_aggr[host_vlan] = {}
        end

        if vlans_aggr[host_vlan]["bytes.sent"] == nil then
          vlans_aggr[host_vlan]["bytes.sent"] = host["bytes.sent"]
          vlans_aggr[host_vlan]["bytes.rcvd"] = host["bytes.rcvd"]
        else
          vlans_aggr[host_vlan]["bytes.sent"] = vlans_aggr[host_vlan]["bytes.sent"] + host["bytes.sent"]
          vlans_aggr[host_vlan]["bytes.rcvd"] = vlans_aggr[host_vlan]["bytes.rcvd"] + host["bytes.rcvd"]
        end
      end

      if(host.localhost) then
        if host_categories_rrd_creation ~= "0" and not ntop.exists(fixPath(hostbase.."/categories")) then
          ntop.mkdir(fixPath(hostbase.."/categories"))
        end

        -- Aggregate network stats
        local network_name = host["local_network_name"]

        --io.write("==> Adding "..network_name.."\n")
        if (networks_aggr[network_name] == nil) then
          networks_aggr[network_name] = {}
        end
        if (networks_aggr[network_name]["bytes.sent"] == nil) then
          networks_aggr[network_name]["bytes.sent"] = host["bytes.sent"]
          networks_aggr[network_name]["bytes.rcvd"] = host["bytes.rcvd"]
        else
          networks_aggr[network_name]["bytes.sent"] = networks_aggr[network_name]["bytes.sent"] + host["bytes.sent"]
          networks_aggr[network_name]["bytes.rcvd"] = networks_aggr[network_name]["bytes.rcvd"] + host["bytes.rcvd"]
        end

        -- Traffic stats
        local name = fixPath(hostbase .. "/bytes.rrd")
        createRRDcounter(name, 300, verbose)
        ntop.rrd_update(name, "N:"..tolongint(host["bytes.sent"]) .. ":" .. tolongint(host["bytes.rcvd"]))
        if(verbose) then
          print("\n["..__FILE__()..":"..__LINE__().."] Updating RRD [".. ifstats.name .."] "..name..'\n')
        end

        -- L4 Protocols
        for id, _ in ipairs(l4_keys) do
          k = l4_keys[id][2]
          if((host[k..".bytes.sent"] ~= nil) and (host[k..".bytes.rcvd"] ~= nil)) then
            if(verbose) then print("["..__FILE__()..":"..__LINE__().."]\t"..k.."\n") end

            name = fixPath(hostbase .. "/".. k .. ".rrd")
            createRRDcounter(name, 300, verbose)
            -- io.write(name.."="..host[k..".bytes.sent"].."|".. host[k..".bytes.rcvd"] .. "\n")
            ntop.rrd_update(name, "N:".. tolongint(host[k..".bytes.sent"]) .. ":" .. tolongint(host[k..".bytes.rcvd"]))
            if(verbose) then print("\n["..__FILE__()..":"..__LINE__().."] Updating RRD [".. ifstats.name .."] "..name..'\n') end
          else
            -- L2 host
            --io.write("Discarding "..k.."@"..hostname.."\n")
          end
        end

        if(host_ndpi_rrd_creation ~= "0") then
          -- nDPI Protocols
          for k in pairs(host["ndpi"]) do
            name = fixPath(hostbase .. "/".. k .. ".rrd")
            createRRDcounter(name, 300, verbose)
            ntop.rrd_update(name, "N:".. tolongint(host["ndpi"][k]["bytes.sent"]) .. ":" .. tolongint(host["ndpi"][k]["bytes.rcvd"]))

            -- Aggregate network NDPI stats
            if (networks_aggr[network_name]["ndpi"] == nil) then
              networks_aggr[network_name]["ndpi"] = {}
            end
            if (networks_aggr[network_name]["ndpi"][k] == nil) then
              networks_aggr[network_name]["ndpi"][k] = {}
            end
            if (networks_aggr[network_name]["ndpi"][k]["bytes.sent"] == nil) then
              networks_aggr[network_name]["ndpi"][k]["bytes.sent"] = host["ndpi"][k]["bytes.sent"]
            else
              networks_aggr[network_name]["ndpi"][k]["bytes.sent"] =
              networks_aggr[network_name]["ndpi"][k]["bytes.sent"] +
              host["ndpi"][k]["bytes.sent"]
            end
            if (networks_aggr[network_name]["ndpi"][k]["bytes.rcvd"] == nil) then
              networks_aggr[network_name]["ndpi"][k]["bytes.rcvd"] = host["ndpi"][k]["bytes.rcvd"]
            else
              networks_aggr[network_name]["ndpi"][k]["bytes.rcvd"] =
              networks_aggr[network_name]["ndpi"][k]["bytes.rcvd"] +
              host["ndpi"][k]["bytes.rcvd"]
            end

            if(verbose) then print("\n["..__FILE__()..":"..__LINE__().."] Updating RRD [".. ifstats.name .."] "..name..'\n') end
          end
          if(host_categories_rrd_creation ~= "0") then
            if host["categories"] ~= nil then
              if networks_aggr[network_name]["categories"] == nil then
                networks_aggr[network_name]["categories"] = {}
              end
              for _cat_name, cat_bytes in pairs(host["categories"]) do
                cat_name = getCategoryLabel(_cat_name)
                -- io.write('cat_name: '..cat_name..' cat_bytes:'..tostring(cat_bytes)..'\n')
                name = fixPath(hostbase.."/categories/"..cat_name..".rrd")
                createSingleRRDcounter(name, 300, verbose)
                ntop.rrd_update(name, "N:".. tolongint(cat_bytes))

                if networks_aggr[network_name]["categories"][cat_name] == nil then
                  networks_aggr[network_name]["categories"][cat_name] = cat_bytes
                else
                  networks_aggr[network_name]["categories"][cat_name] =
                  networks_aggr[network_name]["categories"][cat_name] + cat_bytes
                end
              end
            end
          end

          if(host["epp"]) then dumpSingleTreeCounters(hostbase, "epp", host, verbose) end
          if(host["dns"]) then dumpSingleTreeCounters(hostbase, "dns", host, verbose) end
        end
      else
        -- print("ERROR: ["..__FILE__()..":"..__LINE__().."] Skipping non local host "..hostname.."\n")
      end
    end, time_threshold) -- end foreachHost

    if not in_time then
      callback_utils.print(__FILE__(), __LINE__(), "ERROR: Cannot complete local hosts RRD dump in 5 minutes. Please check your RRD configuration.")
      return false
    end

    -- create RRD for ASN
    if asn_rrd_creation ~= "0" then
      local basedir = fixPath(dirs.workingdir .. "/" .. ifstats.id..'/asnstats')

      for asn_id, asn_stats in pairs(asn_aggr) do
        local asnpath = fixPath(basedir.. "/" .. asn_id)
        if not ntop.exists(asnpath) then
          ntop.mkdir(asnpath)
        end

        -- Save ASN bytes
        local asn_bytes_rrd = fixPath(asnpath .. "/bytes.rrd")
        createRRDcounter(asn_bytes_rrd, 300, false)
        ntop.rrd_update(asn_bytes_rrd, "N:"..tolongint(asn_stats["bytes.sent"]) .. ":" .. tolongint(asn_stats["bytes.rcvd"]))

        -- Save ASN ndpi stats
        if asn_stats["ndpi"] ~= nil then
          for proto_name, proto_stats in pairs(asn_stats["ndpi"]) do
            local asn_ndpi_rrd = fixPath(asnpath.."/"..proto_name..".rrd")
            createRRDcounter(asn_ndpi_rrd, 300, verbose)
            ntop.rrd_update(asn_ndpi_rrd, "N:"..tolongint(proto_stats["bytes.sent"])..":"..tolongint(proto_stats["bytes.rcvd"]))
          end
        end
      end
    end

    if host_rrd_creation ~= "1" then
      -- only ASN enabled
      return
    end

    -- create RRD for vlans
    local basedir = fixPath(dirs.workingdir .. "/" .. ifstats.id..'/vlanstats')
    for vlan_id, vlan_stats in pairs(vlans_aggr) do
      local vlanpath = getPathFromKey(vlan_id)
      vlanpath = fixPath(basedir.. "/" .. vlanpath)
      if not ntop.exists(vlanpath) then
        ntop.mkdir(vlanpath)
      end
      vlanpath = fixPath(vlanpath .. "/bytes.rrd")
      createRRDcounter(vlanpath, 300, false)
      ntop.rrd_update(vlanpath, "N:"..tolongint(vlan_stats["bytes.sent"]) .. ":" .. tolongint(vlan_stats["bytes.rcvd"]))
    end

    --- Create RRD for networks
    for n,m in pairs(networks_aggr) do
      local netname = getPathFromKey(n)
      local base = dirs.workingdir .. "/" .. ifstats.id .. "/rrd/".. netname
      base = fixPath(base)
      --io.write("->"..n.."\n")
      if(not(ntop.exists(base))) then ntop.mkdir(base) end

      name = fixPath(base .. "/bytes.rrd")
      createRRDcounter(name, 300, verbose)
      str = "N:".. tolongint(m["bytes.sent"]) .. ":" .. tolongint(m["bytes.rcvd"])
      --io.write(name.."="..str.."\n")
      ntop.rrd_update(name, str)
      if (m["ndpi"]) then -- nDPI data could be disabled
        for k in pairs(m["ndpi"]) do
          local ndpiname = fixPath(base.."/"..k..".rrd")
          createRRDcounter(ndpiname, 300, verbose)
          ntop.rrd_update(ndpiname, "N:"..tolongint(m["ndpi"][k]["bytes.sent"])..":"..tolongint(m["ndpi"][k]["bytes.rcvd"]))
        end
      end

      if (m["categories"]) then
        if not ntop.exists(fixPath(base.."/categories")) then ntop.mkdir(fixPath(base.."/categories")) end
        for cat_name, cat_bytes in pairs(m["categories"]) do
          local catrrdname = fixPath(base.."/categories/"..cat_name..".rrd")
          createSingleRRDcounter(catrrdname, 300, verbose)
          ntop.rrd_update(catrrdname, "N:"..tolongint(cat_bytes))
        end
      end
    end -- for

    -- Create RRDs for flow and sFlow devices
    if(tostring(flow_devices_rrd_creation) == "1" and ntop.isEnterprise()) then
      local flowdevs = interface.getSFlowDevices()

      for flow_device_ip,_ in pairs(flowdevs) do
        local ports = interface.getSFlowDeviceInfo(flow_device_ip)

        if(verbose) then
          print ("["..__FILE__()..":"..__LINE__().."] Processing sFlow device "..flow_device_ip.."\n")
        end

        for port_idx,port_value in pairs(ports) do
          local base = dirs.workingdir .. "/" .. ifstats.id .. "/rrd/sflow_devices/".. flow_device_ip

          base = fixPath(base)
          if(not(ntop.exists(base))) then ntop.mkdir(base) end
          name = fixPath(base .. "/"..port_idx..".rrd")
          createRRDcounter(name, 300, verbose)
          str = "N:".. tolongint(port_value.ifOutOctets) .. ":" .. tolongint(port_value.ifInOctets)
          ntop.rrd_update(name, str)

          if(verbose) then
            print ("["..__FILE__()..":"..__LINE__().."]  Processing flow device "..flow_device_ip.." / port "..port_idx.." ["..name.."]\n")
          end
        end
      end

      local flowdevs = interface.getFlowDevices() -- Flow, not sFlow here

      for flow_device_ip,_ in pairs(flowdevs) do
	 local ports = interface.getFlowDeviceInfo(flow_device_ip)

	 if(verbose) then
	    print ("["..__FILE__()..":"..__LINE__().."] Processing flow device "..flow_device_ip.."\n")
	 end

	 for port_idx,port_value in pairs(ports) do
	    local base = getRRDName(ifstats.id, "flow_device:"..flow_device_ip, port_idx)
	    if(not(ntop.exists(base))) then ntop.mkdir(base) end

	    local name = getRRDName(ifstats.id, "flow_device:"..flow_device_ip, port_idx.."/bytes.rrd")

	    createRRDcounter(name, 300, verbose)
	    str = "N:".. tolongint(port_value["bytes.out_bytes"]) .. ":" .. tolongint(port_value["bytes.in_bytes"])
	    ntop.rrd_update(name, str)

	    if(verbose) then
	       print ("["..__FILE__()..":"..__LINE__().."]  Processing flow device "..flow_device_ip.." / port "..port_idx.." ["..name.."]\n")
	    end
	 end
      end

    end

    -- Save host activity stats only if flow activities are actually enabled
    -- TODO: it is pointless to call foreachHost one more time. This is too expensive
    -- and determines an attitional call to getHostInfo for every host
    if ((prefs.is_flow_activity_enabled == true) and (ntop.getCache("ntopng.prefs.host_activity_rrd_creation") == true)) then
      local in_time = callback_utils.foreachHost(_ifname, verbose, callback_utils.saveLocalHostsActivity, time_threshold)
      if not in_time then
        callback_utils.print(__FILE__(), __LINE__(), "ERROR: Cannot complete local hosts RRD activity dump in 5 minutes. Please check your RRD configuration.")
        return false
      end
    end
  end -- if rrd

  -- Save Host Pools stats every 5 minutes
  if((ntop.isPro()) and (tostring(host_pools_rrd_creation) == "1") and (not ifstats.isView)) then
    host_pools_utils.updateRRDs(ifstats.id, true --[[ also dump nDPI data ]], verbose)
  end
end)

-- ########################################################

-- This must be placed at the end of the script
if(tostring(snmp_devices_rrd_creation) == "1") then
   snmp_update_rrds(time_threshold, verbose)
end
