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

/* **************************************************** */

static void* lsLoop(void* ptr) {
  ntop->getLogstash()->sendLSdata();
  return(NULL);
}

/* **************************************** */



Logstash::Logstash() {
  num_queued_elems = 0;
  head = NULL;
  tail = NULL;
  reportDrops = false;
  checkpointDroppedFlows = checkpointExportedFlows = 0;
  lastUpdateTime.tv_sec = 0, lastUpdateTime.tv_usec = 0;
}

/* **************************************** */

Logstash::~Logstash(){

}

/* ******************************************* */

void Logstash::updateStats(const struct timeval *tv) {
  if(tv == NULL)
    return;

  if(lastUpdateTime.tv_sec > 0) {
    float tdiffMsec = ((float)(tv->tv_sec-lastUpdateTime.tv_sec)*1000)+((tv->tv_usec-lastUpdateTime.tv_usec)/(float)1000);

    if(tdiffMsec >= 1000) { /* al least one second */
      u_int64_t diffFlows = elkExportedFlows - elkLastExportedFlows;
      
      elkLastExportedFlows = elkExportedFlows;
      elkExportRate = ((float)(diffFlows * 1000)) / tdiffMsec;
      if(elkExportRate < 0) elkExportRate = 0;
    }
  }

  memcpy(&lastUpdateTime, tv, sizeof(struct timeval));
}

/* ******************************************* */

void Logstash::lua(lua_State *vm, bool since_last_checkpoint) const {
  lua_push_int_table_entry(vm,   "flow_export_count",
			   elkExportedFlows - (since_last_checkpoint ? checkpointExportedFlows : 0));
  lua_push_int32_table_entry(vm, "flow_export_drops",
			     elkDroppedFlowsQueueTooLong - (since_last_checkpoint ? checkpointDroppedFlows : 0));
  lua_push_float_table_entry(vm, "flow_export_rate",
			     elkExportRate >= 0 ? elkExportRate : 0);
}

/* **************************************** */

int Logstash::sendToLS(char* msg) {
  struct string_list *e;
  int rc = 0;

  if(!strcmp(msg,"")){
    return (-1);
  }
  
  if(num_queued_elems >= LS_MAX_QUEUE_LEN) {
    if(!reportDrops) {
      ntop->getTrace()->traceEvent(TRACE_WARNING, "[LS] Export queue too long [%d]: expect drops",
				   num_queued_elems);
      reportDrops = true;
    }

    elkDroppedFlowsQueueTooLong++;
    ntop->getTrace()->traceEvent(TRACE_INFO, "[LS] Message dropped. Total messages dropped: %lu\n",
				 elkDroppedFlowsQueueTooLong);

    return(-1);
  }

  listMutex.lock(__FILE__, __LINE__);
  e = (struct string_list*)calloc(1, sizeof(struct string_list));
  if( e != NULL) {
    e->str = strdup(msg), e->next = head;

    if(e->str) {
      if(head)
        head->prev = e;
      head = e;
      if(tail == NULL)
	tail = e;
      num_queued_elems++;

      rc = 0;
    } else {
      /* Out of memory */
      free(e);
      rc = -1;
    }
  }

  listMutex.unlock(__FILE__, __LINE__);
  return rc;
}

/* **************************************** */

void Logstash::startFlowDump() {
  if(ntop->getPrefs()->do_dump_flows_on_ls()){
    pthread_create(&lsThreadLoop, NULL, lsLoop, (void*)this);
  }
}

/* **************************************** */

void Logstash::sendLSdata() {
  const u_int watermark = 8, min_buf_size = 512;
  char postbuf[16384];
  char *proto = NULL;
  struct hostent *server = NULL;
  char *portstr = NULL;
  int sendTCP = 1;
  struct sockaddr_in serv_addr;
  int sockfd;
  int portno;


  server = gethostbyname(ntop->getPrefs()->get_ls_host());
  portstr = ntop->getPrefs()->get_ls_port();

  if(server == NULL || portstr==NULL){
     //can't send
     return;
  }

  proto = ntop->getPrefs()->get_ls_proto();
  if(proto&&!strncmp(proto,"udp",3)){
     sendTCP = 0;
  }
  portno = atoi(portstr);

  bzero((char *) &serv_addr,sizeof(serv_addr));
  serv_addr.sin_family = AF_INET;
  bcopy((char *) server->h_addr, (char *)&serv_addr.sin_addr.s_addr, server->h_length);
  serv_addr.sin_port = htons(portno);

  while(!ntop->getGlobals()->isShutdown()) {
    if(num_queued_elems >= watermark) {
      u_int len, num_flows;
      len = 0, num_flows = 0;

      listMutex.lock(__FILE__, __LINE__);
      for(u_int i=0; (i<watermark) && ((sizeof(postbuf)-len) > min_buf_size); i++) {
        struct string_list *prev;
	if(!(tail && tail->str)){
          //No events in queue
	  break;
	}
        prev = tail->prev;
	len += snprintf(&postbuf[len], sizeof(postbuf)-len, "%s\n", tail->str), num_flows++;
        free(tail->str);
        free(tail);
        tail = prev,
	  num_queued_elems--;

        if(num_queued_elems == 0)
	  head = NULL;
      } /* for */

      listMutex.unlock(__FILE__, __LINE__);
      postbuf[len] = '\0';

      if(postbuf[0]!='{') {
	continue;
      }

      if(!sendTCP) { //UDP socket
	sockfd = socket(AF_INET,SOCK_DGRAM, IPPROTO_UDP);
      } else {	//TCP socket
	sockfd = socket(AF_INET, SOCK_STREAM, 0);
      }

      if(sockfd < 0) {
	/* Post failure */
        continue;
      }

      //Set nonblocking
      fcntl(sockfd, F_SETFL, MSG_DONTWAIT);

      if(sendTCP
	 && (connect(sockfd,(struct sockaddr *)&serv_addr,sizeof(serv_addr)) < 0)
        ) {
	sleep(1);
        close(sockfd);
        continue;
      }

      if(
          (sendTCP
	  && (send(sockfd,postbuf,sizeof(postbuf),0) < 0))
	  ||
	  (!sendTCP
	   &&
	   (sendto(sockfd, postbuf, sizeof(postbuf), 0,
		   (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0)
           )
	  ){
        sleep(1);
        close(sockfd);
        continue;
      }

      //If all steps succeded, increment exported flows
      elkExportedFlows += num_flows;
      close(sockfd);

    } else {
      sleep(1);
    }
  } /* while */
  if(proto)  free(proto);
  if(portstr) free(portstr);

}
