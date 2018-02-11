/*
 *
 * (C) 2013-17 - ntop.org
 *
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 */

#include "ntop_includes.h"

/* *************************************** */

GenericHost::GenericHost(NetworkInterface *_iface) : GenericHashEntry(_iface) {
  if(_iface == NULL)
    ntop->getTrace()->traceEvent(TRACE_WARNING, "NULL interface");

  ndpiStats = new nDPIStats();

  systemHost = false, localHost = false;
  last_bytes = 0, last_bytes_thpt = bytes_thpt = 0, bytes_thpt_trend = trend_unknown;
  bytes_thpt_diff = 0, last_epoch_update = 0;
  total_activity_time = 0;
  last_packets = 0, last_pkts_thpt = pkts_thpt = 0, pkts_thpt_trend = trend_unknown;
  last_update_time.tv_sec = 0, last_update_time.tv_usec = 0, vlan_id = 0;
  low_goodput_client_flows = low_goodput_server_flows = 0;
  // readStats(); - Commented as if put here it's too early and the key is not yet set
  goodput_bytes_thpt = last_goodput_bytes_thpt = bytes_goodput_thpt_diff = 0;
  bytes_goodput_thpt_trend = trend_unknown;

}

/* *************************************** */

void GenericHost::incStats(u_int32_t when, u_int8_t l4_proto, u_int ndpi_proto,
			   u_int64_t sent_packets, u_int64_t sent_bytes, u_int64_t sent_goodput_bytes,
			   u_int64_t rcvd_packets, u_int64_t rcvd_bytes,  u_int64_t rcvd_goodput_bytes) {
  if(sent_packets || rcvd_packets) {
    sent.incStats(sent_packets, sent_bytes), rcvd.incStats(rcvd_packets, rcvd_bytes);

    if(ndpiStats) {
      ndpiStats->incStats(when, ndpi_proto, sent_packets, sent_bytes, rcvd_packets, rcvd_bytes),
	ndpiStats->incCategoryStats(when,
				    getInterface()->get_ndpi_proto_category(ndpi_proto),
				    sent_bytes, rcvd_bytes);
      
    }

    if((when != 0) && (last_epoch_update != when))
      total_activity_time += ntop->getPrefs()->get_housekeeping_frequency(), last_epoch_update = when;

    updateSeen();
  }
}
