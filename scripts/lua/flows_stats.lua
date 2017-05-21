--
-- (C) 2013-17 - ntop.org
--

dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path

require "lua_utils"
require "graph_utils"

sendHTTPContentTypeHeader('text/html')
ntop.dumpFile(dirs.installdir .. "/httpdocs/inc/header.inc")

active_page = "flows"
dofile(dirs.installdir .. "/scripts/lua/inc/menu.lua")

application = _GET["application"]
application_filter = ""
hosts = _GET["hosts"]
host = _GET["host"]
vhost = _GET["vhost"]
flowhosts_type = _GET["flowhosts_type"]
flowhosts_type_filter = ""
ipversion = _GET["version"]
ipversion_filter = ""
traffic_type = _GET["traffic_type"]
traffic_type_filter = ""
flow_status = _GET["flow_status"]
flow_status_filter = ""
port = _GET["port"]

network_id = _GET["network"]

prefs = ntop.getPrefs()
interface.select(ifname)
ifstats = interface.getStats()
ndpistats = interface.getnDPIStats()

local base_url = ntop.getHttpPrefix() .. "/lua/flows_stats.lua"
local page_params = {}

if (network_id ~= nil) then
network_name = ntop.getNetworkNameById(tonumber(network_id))
url = ntop.getHttpPrefix()..'/lua/flows_stats.lua?network='..network_id

print [[
  <nav class="navbar navbar-default" role="navigation">
  <div class="navbar-collapse collapse">
    <ul class="nav navbar-nav">
]]
print("<li><a href=\"#\"> Network "..network_name)
print("</a></li>\n")

page = _GET["page"]

if(page == "flows") then
  print("<li class=\"active\"><a href=\"#\">"..i18n("flows").."</a></li>\n")
else
  print("<li><a href=\""..url.."&page=flows\">"..i18n("flows").."</a></li>")
end
if (page == "historical") then
  print("<li class=\"active\"><a href=\"#\"><i class='fa fa-area-chart fa-lg'></i></a></li>\n")
else
  print("<li><a href=\""..url.."&page=historical\"><i class='fa fa-area-chart fa-lg'></i></a></li>")
end

print [[
<li><a href="javascript:history.go(-1)"><i class='fa fa-reply'></i></a></li>
</ul>
</div>
</nav>
   ]]
end

if (page == "flows" or page == nil) then

print [[
      <hr>
      <div id="table-flows"></div>
	 <script>
   var url_update = "]]

if(application ~= nil) then
   page_params["application"] = application
   application_filter = '<span class="glyphicon glyphicon-filter"></span>'
end

if(host ~= nil) then
  page_params["host"] = host
end

if(vhost ~= nil) then
  page_params["vhost"] = vhost
end

if(hosts ~= nil) then
  page_params["hosts"] = hosts
end

if(port ~= nil) then
  page_params["port"] = port
end

if(ipversion ~= nil) then
  page_params["version"] = ipversion
  ipversion_filter = '<span class="glyphicon glyphicon-filter"></span>'
end

if(traffic_type ~= nil) then
   page_params["traffic_type"] = traffic_type
   traffic_type_filter = '<span class="glyphicon glyphicon-filter"></span>'
end

if(flow_status ~= nil) then
   page_params["flow_status"] = flow_status
   flow_status_filter = '<span class="glyphicon glyphicon-filter"></span>'
end

if(network_id ~= nil) then
  page_params["network"] = network_id
end

if(flowhosts_type ~= nil) then
  page_params["flowhosts_type"] = flowhosts_type
  flowhosts_type_filter = '<span class="glyphicon glyphicon-filter"></span>'
end

print(getPageUrl(ntop.getHttpPrefix().."/lua/get_flows_data.lua", page_params))

print ('";')

ntop.dumpFile(dirs.installdir .. "/httpdocs/inc/flows_stats_id.inc")
-- Set the flow table option

if(ifstats.vlan) then print ('flow_rows_option["vlan"] = true;\n') end

   print [[
	 var table = $("#table-flows").datatable({
			url: url_update , ]]
print ('rowCallback: function ( row ) { return flow_table_setID(row); },\n')

preference = tablePreferences("rows_number",_GET["perPage"])
if (preference ~= "") then print ('perPage: '..preference.. ",\n") end

local filter_msg = (application or vhost or "")
local active_msg

if not interface.isPacketInterface() then
   active_msg = i18n("flows_page.recently_active_flows", {filter=filter_msg})
elseif interface.isPcapDumpInterface() then
   active_msg = i18n("flows_page.flows", {filter=filter_msg})
else
   active_msg = i18n("flows_page.active_flows", {filter=filter_msg})
end

if(network_name ~= nil) then
   active_msg = active_msg .. i18n("network", {network=network_name})
end

print(" title: \""..active_msg)


print [[",
         showFilter: true,
         showPagination: true,
]]

-- Automatic default sorted. NB: the column must be exists.
print ('sort: [ ["' .. getDefaultTableSort("flows") ..'","' .. getDefaultTableSortOrder("flows").. '"] ],\n')

print ('buttons: [')

-- begin buttons

-- Local / Remote hosts selector
local flowhosts_type_params = table.clone(page_params)
flowhosts_type_params["flowhosts_type"] = nil

local function printDropdownEntries(entries, param_arr, param_filter, curr_filter)
   for _, htype in ipairs(entries) do
      param_arr[param_filter] = htype[1]
      print[[<li]]

      if htype[1] == curr_filter then print(' class="active"') end

      print[[><a href="]] print(getPageUrl(base_url, param_arr)) print[[">]] print(htype[2]) print[[</a></li>]]
   end
end

print[['\
   <div class="btn-group">\
      <button class="btn btn-link dropdown-toggle" data-toggle="dropdown">]] print(i18n("flows_page.hosts")) print(flowhosts_type_filter) print[[<span class="caret"></span></button>\
      <ul class="dropdown-menu" role="menu" id="flow_dropdown">\
         <li><a href="]] print(getPageUrl(base_url, flowhosts_type_params)) print[[">]] print(i18n("flows_page.all_hosts")) print[[</a></li>\]]
   printDropdownEntries({
      {"local_only", i18n("flows_page.local_only")},
      {"remote_only", i18n("flows_page.remote_only")},
      {"local_origin_remote_target", i18n("flows_page.local_cli_remote_srv")},
      {"remote_origin_local_target", i18n("flows_page.local_srv_remote_cli")}
   }, flowhosts_type_params, "flowhosts_type", flowhosts_type)
print[[\
      </ul>\
   </div>\
']]

-- Status selector
local flow_status_params = table.clone(page_params)
flow_status_params["flow_status"] = nil

print[[, '\
   <div class="btn-group">\
      <button class="btn btn-link dropdown-toggle" data-toggle="dropdown">]] print(i18n("status")) print(flow_status_filter) print[[<span class="caret"></span></button>\
      <ul class="dropdown-menu" role="menu">\
      <li><a href="]] print(getPageUrl(base_url, flow_status_params)) print[[">]] print(i18n("flows_page.all_flows")) print[[</a></li>\]]
   printDropdownEntries({
      {"normal", i18n("flows_page.normal")},
      {"alerted", i18n("flows_page.alerted")},
   }, flow_status_params, "flow_status", flow_status)
print[[\
      </ul>\
   </div>\
']]

-- Unidirectional flows selector
local traffic_type_params = table.clone(page_params)
traffic_type_params["traffic_type"] = nil

print[[, '\
   <div class="btn-group">\
      <button class="btn btn-link dropdown-toggle" data-toggle="dropdown">]] print(i18n("flows_page.direction")) print(traffic_type_filter) print[[<span class="caret"></span></button>\
      <ul class="dropdown-menu" role="menu">\
         <li><a href="]] print(getPageUrl(base_url, traffic_type_params)) print[[">]] print(i18n("flows_page.all_flows")) print[[</a></li>\]]
   printDropdownEntries({
      {"broadcast_multicast", i18n("flows_page.one_way_multicast")},
      {"unicast", i18n("flows_page.one_way_non_multicast")},
   }, traffic_type_params, "traffic_type", traffic_type)
print[[\
      </ul>\
   </div>\
']]

-- L7 Application
print(', \'<div class="btn-group"><button class="btn btn-link dropdown-toggle" data-toggle="dropdown">'..i18n("report.applications")..' ' .. application_filter .. '<span class="caret"></span></button> <ul class="dropdown-menu" role="menu" id="flow_dropdown">')
print('<li><a href="')
local application_filter_params = table.clone(page_params)
application_filter_params["application"] = nil
print(getPageUrl(base_url, application_filter_params))
print('">'..i18n("flows_page.all_proto")..'</a></li>')

for key, value in pairsByKeys(ndpistats["ndpi"], asc) do
   class_active = ''
   if(key == application) then
      class_active = ' class="active"'
   end
   print('<li '..class_active..'><a href="')
   application_filter_params["application"] = key
   print(getPageUrl(base_url, application_filter_params))
   print('">'..key..'</a></li>')
end

print("</ul> </div>'")

-- Ip version selector
local ipversion_params = table.clone(page_params)
ipversion_params["version"] = nil

print[[, '<div class="btn-group pull-right">]]
printIpVersionDropdown(base_url, ipversion_params)
print [[</div>']]

-- end buttons

print(" ],\n")

print[[
   columns: [
      {
         title: "]] print(i18n("key")) print[[",
         field: "key",
         hidden: true,
         css: {
              textAlign: 'center'
         }
      }, {
         title: "",
         field: "column_key",
         css: {
            textAlign: 'center'
         }
      }, {
         title: "]] print(i18n("application")) print[[",
         field: "column_ndpi",
         sortable: true,
         css: {
            textAlign: 'center'
         }
      }, {
         title: "]] print(i18n("db_explorer.l4_proto")) print[[",
         field: "column_proto_l4",
         sortable: true,
         css: {
            textAlign: 'center'
         }
      },
]]

if(ifstats.vlan) then
   print [[
      {
        title: "]] print(i18n("vlan")) print[[",
        field: "column_vlan",
        sortable: true,
        css: {
           textAlign: 'center'
        }
      },
   ]]
end
end

print[[
      {
         title: "]] print(i18n("client")) print[[",
         field: "column_client",
         sortable: true,
      }, {
         title: "]] print(i18n("server")) print[[",
         field: "column_server",
         sortable: true,
      }, {
         title: "]] print(i18n("duration")) print[[",
         field: "column_duration",
         sortable: true,
         css: {
           textAlign: 'center'
         }
      }, {
         title: "]] print(i18n("breakdown")) print[[",
         field: "column_breakdown",
         sortable: false,
            css: {
               textAlign: 'center'
            }
      }, {
         title: "]] print(i18n("flows_page.actual_throughput")) print[[",
         field: "column_thpt",
         sortable: true,
         css: {
            textAlign: 'right'
         }
      }, {
         title: "]] print(i18n("flows_page.total_bytes")) print[[",
         field: "column_bytes",
         sortable: true,
            css: {
               textAlign: 'right'
            }
      }, {
         title: "]] print(i18n("info")) print[[",
         field: "column_info",
         sortable: true,
            css: {
               textAlign: 'left'
            }
         }
      ]
   });
</script>
]]

if (page == "historical" and network_name ~= nil) then
  local netname_format = string.gsub(network_name, "_", "/")
  local rrd_file = _GET["rrd_file"]
  if (rrd_file == nil or rrd_file == "all") then
    rrd_file = "all"
  else
    rrd_file = getPathFromKey(netname_format).."/"..rrd_file
  end
  drawRRD(ifstats.id, nil, rrd_file, "1d", url.."&page=historical", 1, os.time() , "", nil)
end

dofile(dirs.installdir .. "/scripts/lua/inc/footer.lua")
