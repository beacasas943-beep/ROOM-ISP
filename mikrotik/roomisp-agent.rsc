# ROOM ISP - agente seguro v4.1 para RouterOS 6.49+
# Generado desde el portal ISP. No copie configuracion.rsc ni credenciales antiguas.
# Instala SOLO scripts/schedulers ROOM_ISP_* y una regla de corte para la lista ROOM_ISP_SUSPENDED.

{
    :local roomEnrollUrl "__ROOM_ENROLL_URL__";
    :local roomAgentUrl "__ROOM_AGENT_URL__";
    :local roomEnrollCode "__ROOM_ENROLL_CODE__";
    :if (([:find $roomEnrollUrl "__ROOM_"] != nil) || ([:find $roomAgentUrl "__ROOM_"] != nil) || ([:find $roomEnrollCode "__ROOM_"] != nil)) do={ :error "ROOM ISP: instalador no generado"; };

    :local roomIdentity [/system identity get name];
    :local roomVersion [/system resource get version];
    :local roomModel [/system resource get board-name];
    :local roomArchitecture [/system resource get architecture-name];
    :local roomSoftwareId [/system license get software-id];
    :local roomPppoe [/ppp secret print count-only where service=pppoe];
    :local roomDhcp [/ip dhcp-server lease print count-only];
    :local roomHotspot [/ip hotspot user print count-only];
    :local roomQueues [/queue simple print count-only];
    :local roomBody ("{\"protocol\":4,\"enrollment_code\":\"" . $roomEnrollCode . "\",\"device\":{\"identity\":\"" . $roomIdentity . "\",\"routeros_version\":\"" . $roomVersion . "\",\"architecture\":\"" . $roomArchitecture . "\",\"model\":\"" . $roomModel . "\",\"software_id\":\"" . $roomSoftwareId . "\"},\"capabilities\":{\"pppoe\":" . $roomPppoe . ",\"dhcp\":" . $roomDhcp . ",\"hotspot\":" . $roomHotspot . ",\"simple_queues\":" . $roomQueues . "}}");

    :local roomEnrollment;
    :do { :set roomEnrollment [/tool fetch url=$roomEnrollUrl http-method=post http-header-field="Content-Type:application/json" http-data=$roomBody output=user as-value check-certificate=yes-without-crl]; } on-error={ :error "ROOM ISP enrollment failed"; };
    :local roomResponse ($roomEnrollment->"data");
    :if ([:pick $roomResponse 0 3] != "OK|") do={ :error "ROOM ISP enrollment rejected"; };
    :local roomRest [:pick $roomResponse 3 [:len $roomResponse]]; :local roomP1 [:find $roomRest "|"]; :local roomRouterId [:pick $roomRest 0 $roomP1];
    :set roomRest [:pick $roomRest ($roomP1 + 1) [:len $roomRest]]; :local roomP2 [:find $roomRest "|"]; :local roomAgentToken [:pick $roomRest 0 $roomP2];
    :local roomPollMinutes [:tonum [:pick $roomRest ($roomP2 + 1) [:len $roomRest]]]; :if (($roomPollMinutes < 5) || ($roomPollMinutes > 60)) do={ :set roomPollMinutes 5; };
    :if (([:len $roomRouterId] < 20) || ([:len $roomAgentToken] < 32)) do={ :error "ROOM ISP: respuesta incompleta"; };

    :foreach roomItem in=[/system scheduler find where name~"^ROOM_ISP_"] do={ /system scheduler disable $roomItem; };
    :foreach roomItem in=[/system script find where name~"^ROOM_ISP_"] do={ /system script remove $roomItem; };
    :foreach roomItem in=[/system scheduler find where name~"^ROOM_ISP_"] do={ /system scheduler remove $roomItem; };

    # Regla de corte para IP fija/DHCP. Solo afecta direcciones que ROOM agregue a su propia address-list.
    :if ([:len [/ip firewall filter find where comment="ROOM ISP - suspension"]] = 0) do={
        /ip firewall filter add chain=forward src-address-list=ROOM_ISP_SUSPENDED action=drop place-before=0 comment="ROOM ISP - suspension";
    };

    :local roomStateSource (":global roomIspRouterId \"" . $roomRouterId . "\";\r\n:global roomIspAgentToken \"" . $roomAgentToken . "\";\r\n:global roomIspAgentUrl \"" . $roomAgentUrl . "\";\r\n:global roomIspProtocol 4;");
    /system script add name=ROOM_ISP_STATE comment="ROOM ISP v4.1 - credencial privada" policy=read source=$roomStateSource;

    /system script add name=ROOM_ISP_AGENT comment="ROOM ISP v4.1 - control de acceso y cobros" policy=read,write,test source={
        :do {
            /system script run ROOM_ISP_STATE;
            :global roomIspRouterId; :global roomIspAgentToken; :global roomIspAgentUrl;
            :local roomCpu [/system resource get cpu-load]; :local roomFree [/system resource get free-memory]; :local roomUptime [/system resource get uptime];
            :local roomBody ("{\"protocol\":4,\"mode\":\"poll\",\"router_id\":\"" . $roomIspRouterId . "\",\"health\":{\"cpu\":" . $roomCpu . ",\"free_memory\":" . $roomFree . ",\"uptime\":\"" . $roomUptime . "\"}}");
            :local roomHeaders ("Content-Type:application/json,Authorization:Bearer " . $roomIspAgentToken);
            :local roomFetch [/tool fetch url=$roomIspAgentUrl http-method=post http-header-field=$roomHeaders http-data=$roomBody output=user as-value check-certificate=yes-without-crl];
            :local roomData ($roomFetch->"data");
            :if ([:pick $roomData 0 5] != "NONE|") do={
                :if ([:pick $roomData 0 4] != "CMD|") do={ :error "ROOM ISP: respuesta desconocida"; };
                # CMD|id|tipo|acceso|clave-o-alias|perfil|secreto|rate-limit|duracion-min
                :local rest [:pick $roomData 4 [:len $roomData]]; :local p [:find $rest "|"];
                :local commandId [:pick $rest 0 $p]; :set rest [:pick $rest ($p+1) [:len $rest]]; :set p [:find $rest "|"];
                :local commandType [:pick $rest 0 $p]; :set rest [:pick $rest ($p+1) [:len $rest]]; :set p [:find $rest "|"];
                :local accessType [:pick $rest 0 $p]; :set rest [:pick $rest ($p+1) [:len $rest]]; :set p [:find $rest "|"];
                :local sourceKey [:pick $rest 0 $p]; :set rest [:pick $rest ($p+1) [:len $rest]]; :set p [:find $rest "|"];
                :local routerProfile [:pick $rest 0 $p]; :set rest [:pick $rest ($p+1) [:len $rest]]; :set p [:find $rest "|"];
                :local accessSecret [:pick $rest 0 $p]; :set rest [:pick $rest ($p+1) [:len $rest]]; :set p [:find $rest "|"];
                :local rateLimit [:pick $rest 0 $p]; :local durationMinutes [:pick $rest ($p+1) [:len $rest]];
                :local success true; :local result "applied";
                :do {
                    :if ($commandType="CREATE_ACCESS") do={
                        :if ($accessType="PPPOE") do={
                            :if ([:len $accessSecret] < 1) do={ :error "SECRET_REQUIRED"; };
                            :local ids [/ppp secret find where name=$sourceKey];
                            :if ([:len $ids] = 0) do={ /ppp secret add name=$sourceKey password=$accessSecret profile=$routerProfile service=pppoe comment="ROOM ISP"; } else={ /ppp secret set $ids password=$accessSecret profile=$routerProfile service=pppoe disabled=no; };
                        } else={ :if ($accessType="HOTSPOT") do={
                            :local ids [/ip hotspot user find where name=$sourceKey]; :local lim ($durationMinutes . "m");
                            :if ([:len $ids] = 0) do={ /ip hotspot user add name=$sourceKey password=$accessSecret profile=$routerProfile limit-uptime=$lim comment="ROOM ISP"; } else={ /ip hotspot user set $ids password=$accessSecret profile=$routerProfile limit-uptime=$lim disabled=no; };
                        } else={ :if ($accessType="DHCP") do={
                            :local ids [/ip dhcp-server lease find where mac-address=$sourceKey]; :if ([:len $ids]=0) do={ :error "DHCP_LEASE_NOT_FOUND"; };
                            :do { /ip dhcp-server lease make-static $ids; } on-error={}; :set ids [/ip dhcp-server lease find where mac-address=$sourceKey];
                            :if ([:len $rateLimit] > 0) do={ /ip dhcp-server lease set $ids rate-limit=$rateLimit; }; /ip dhcp-server lease set $ids disabled=no;
                        } else={ :if ($accessType="STATIC") do={
                            :local q [/queue simple find where target=$sourceKey]; :if ([:len $q]=0) do={ /queue simple add name=("ROOM-".$sourceKey) target=$sourceKey max-limit=$rateLimit comment="ROOM ISP"; } else={ /queue simple set $q max-limit=$rateLimit disabled=no; };
                            :foreach z in=[/ip firewall address-list find where list=ROOM_ISP_SUSPENDED and address=$sourceKey] do={ /ip firewall address-list remove $z; };
                        } else={ :error "ACCESS_UNSUPPORTED"; };};};};
                    } else={ :if (($commandType="ENABLE") || ($commandType="SUSPEND") || ($commandType="REMOVE_ACCESS")) do={
                        :local disable (($commandType="SUSPEND") || ($commandType="REMOVE_ACCESS"));
                        :if ($accessType="PPPOE") do={
                            :local ids [/ppp secret find where name=$sourceKey]; :if ([:len $ids]=0) do={:error "PPPOE_NOT_FOUND"}; /ppp secret set $ids disabled=$disable;
                            :if ($disable) do={ :foreach a in=[/ppp active find where name=$sourceKey] do={ /ppp active remove $a; }; };
                        } else={ :if ($accessType="HOTSPOT") do={
                            :local ids [/ip hotspot user find where name=$sourceKey]; :if ([:len $ids]=0) do={:error "HOTSPOT_NOT_FOUND"}; /ip hotspot user set $ids disabled=$disable;
                            :if ($disable) do={ :foreach a in=[/ip hotspot active find where user=$sourceKey] do={ /ip hotspot active remove $a; }; };
                        } else={ :if ($accessType="DHCP") do={
                            :local ids [/ip dhcp-server lease find where mac-address=$sourceKey]; :if ([:len $ids]=0) do={:error "DHCP_NOT_FOUND"}; :local ip [/ip dhcp-server lease get [:pick $ids 0] address];
                            :do { /ip dhcp-server lease make-static $ids; } on-error={}; :set ids [/ip dhcp-server lease find where mac-address=$sourceKey]; /ip dhcp-server lease set $ids disabled=$disable;
                            :if ($disable) do={ :if ([:len [/ip firewall address-list find where list=ROOM_ISP_SUSPENDED and address=$ip]]=0) do={ /ip firewall address-list add list=ROOM_ISP_SUSPENDED address=$ip comment="ROOM ISP"; }; } else={ :foreach z in=[/ip firewall address-list find where list=ROOM_ISP_SUSPENDED and address=$ip] do={ /ip firewall address-list remove $z; }; };
                        } else={ :if ($accessType="STATIC") do={
                            :if ($disable) do={ :if ([:len [/ip firewall address-list find where list=ROOM_ISP_SUSPENDED and address=$sourceKey]]=0) do={ /ip firewall address-list add list=ROOM_ISP_SUSPENDED address=$sourceKey comment="ROOM ISP"; }; } else={ :foreach z in=[/ip firewall address-list find where list=ROOM_ISP_SUSPENDED and address=$sourceKey] do={ /ip firewall address-list remove $z; }; };
                        } else={ :error "ACCESS_UNSUPPORTED"; };};};};
                    } else={ :if ($commandType="PLAN_CHANGE") do={
                        :if ($accessType="PPPOE") do={ /ppp secret set [/ppp secret find where name=$sourceKey] profile=$routerProfile; } else={ :if ($accessType="HOTSPOT") do={ /ip hotspot user set [/ip hotspot user find where name=$sourceKey] profile=$routerProfile; } else={ :if ($accessType="DHCP") do={ :local ids [/ip dhcp-server lease find where mac-address=$sourceKey]; :do { /ip dhcp-server lease make-static $ids; } on-error={}; :set ids [/ip dhcp-server lease find where mac-address=$sourceKey]; /ip dhcp-server lease set $ids rate-limit=$rateLimit; } else={ :if ($accessType="STATIC") do={ :local q [/queue simple find where target=$sourceKey]; :if ([:len $q]=0) do={ /queue simple add name=("ROOM-".$sourceKey) target=$sourceKey max-limit=$rateLimit comment="ROOM ISP"; } else={ /queue simple set $q max-limit=$rateLimit; }; } else={ :error "PLAN_CHANGE_UNSUPPORTED"; };};};};
                    } else={ :if ($commandType="INVENTORY_NOW") do={
                        /system script run ROOM_ISP_INVENTORY; :set result "inventory_started";
                    } else={ :if ($commandType="TERMINAL_READ") do={
                        :if ($sourceKey="system_resource") do={ :set result ("model=".[/system resource get board-name]."; version=".[/system resource get version]."; cpu=".[/system resource get cpu-load]."%; free-memory=".[/system resource get free-memory]."; uptime=".[/system resource get uptime]); } else={
                        :if ($sourceKey="interfaces") do={ :set result ("interfaces=".[/interface print count-only]."; running=".[/interface print count-only where running=yes]); } else={
                        :if ($sourceKey="ip_addresses") do={ :set result ("ip-addresses=".[/ip address print count-only]); } else={
                        :if ($sourceKey="routes") do={ :set result ("routes=".[/ip route print count-only]."; active=".[/ip route print count-only where active=yes]); } else={
                        :if ($sourceKey="ppp_active") do={ :set result ("pppoe-active=".[/ppp active print count-only]); } else={
                        :if ($sourceKey="dhcp_leases") do={ :set result ("dhcp-leases=".[/ip dhcp-server lease print count-only]."; bound=".[/ip dhcp-server lease print count-only where status=bound]); } else={
                        :if ($sourceKey="hotspot_active") do={ :set result ("hotspot-active=".[/ip hotspot active print count-only]); } else={
                        :if ($sourceKey="ping_gateway") do={ :set result ("ping-8.8.8.8 replies=".[/ping 8.8.8.8 count=3]); } else={ :error "TERMINAL_ALIAS_NOT_ALLOWED"; };};};};};};};};
                    } else={ :error "COMMAND_NOT_ALLOWLISTED"; };};};};};
                } on-error={ :set success false; :set result "router_rejected"; };
                :local resultBody ("{\"protocol\":4,\"mode\":\"result\",\"router_id\":\"".$roomIspRouterId."\",\"command_id\":\"".$commandId."\",\"success\":" . $success . ",\"result\":\"".$result."\"}");
                :do { /tool fetch url=$roomIspAgentUrl http-method=post http-header-field=$roomHeaders http-data=$resultBody output=user as-value check-certificate=yes-without-crl; } on-error={ :log warning "ROOM ISP: ACK pendiente"; };
            };
        } on-error={ :log warning "ROOM ISP: backend no disponible; la red sigue operando"; };
    };

    /system script add name=ROOM_ISP_INVENTORY comment="ROOM ISP v4.1 - inventario por lotes sin passwords" policy=read,test source={
        :do {
            /system script run ROOM_ISP_STATE;
            :global roomIspRouterId;
            :global roomIspAgentToken;
            :global roomIspAgentUrl;

            :local roomEsc do={
                :local s [:tostr $1]; :local out ""; :local n [:len $s];
                :if ($n = 0) do={ :return ""; };
                :for i from=0 to=($n - 1) do={
                    :local c [:pick $s $i ($i + 1)];
                    :if ($c = "\\") do={ :set out ($out . "\\\\"); } else={
                        :if ($c = "\"") do={ :set out ($out . "\\\""); } else={
                            :if (($c = "\r") || ($c = "\n")) do={ :set out ($out . " "); } else={ :set out ($out . $c); };
                        };
                    };
                }; :return $out;
            };

            :local roomSend do={
                :global roomIspRouterId; :global roomIspAgentToken; :global roomIspAgentUrl;
                :local sequence $1; :local final $2; :local items $3;
                :if (([:len $items] = 0) && ($final != "true")) do={ :return true; };
                :local body ("{\"protocol\":4,\"mode\":\"inventory\",\"router_id\":\"" . $roomIspRouterId . "\",\"sequence\":" . $sequence . ",\"final\":" . $final . ",\"items\":[" . $items . "]}");
                :local headers ("Content-Type:application/json,Authorization:Bearer " . $roomIspAgentToken);
                :local f [/tool fetch url=$roomIspAgentUrl http-method=post http-header-field=$headers http-data=$body output=user as-value check-certificate=yes-without-crl];
                :if ([:pick ($f->"data") 0 2] != "OK") do={ :error "inventory batch rejected"; };
                :return true;
            };

            :local roomItems ""; :local roomSeq 1;
            :local roomAppend do={
                :local current $1; :local item $2;
                :if ([:len $current] = 0) do={ :return $item; };
                :return ($current . "," . $item);
            };

            # Perfiles PPP: permiten crear planes ROOM vinculados al nombre real del MikroTik.
            :foreach x in=[/ppp profile find] do={
                :local n [/ppp profile get $x name];
                :if ([:pick $n 0 7] != "default") do={
                    :local rate ""; :local localA ""; :local remoteA ""; :local one "";
                    :do {:set rate [/ppp profile get $x rate-limit]} on-error={}; :do {:set localA [/ppp profile get $x local-address]} on-error={};
                    :do {:set remoteA [/ppp profile get $x remote-address]} on-error={}; :do {:set one [/ppp profile get $x only-one]} on-error={};
                    :local item ("{\"type\":\"PROFILE\",\"key\":\"" . [$roomEsc $n] . "\",\"rate_limit\":\"" . [$roomEsc $rate] . "\",\"local_address\":\"" . [$roomEsc $localA] . "\",\"remote_address\":\"" . [$roomEsc $remoteA] . "\",\"only_one\":\"" . [$roomEsc $one] . "\"}");
                    :set roomItems [$roomAppend $roomItems $item];
                    :if ([:len $roomItems] > 2400) do={ [$roomSend $roomSeq "false" $roomItems]; :set roomSeq ($roomSeq + 1); :set roomItems ""; };
                };
            };

            # PPPoE: comentario legible; si falta o es tecnico, usar username. Nunca password.
            :foreach x in=[/ppp secret find where service=pppoe] do={
                :local u [/ppp secret get $x name]; :local c [/ppp secret get $x comment];
                :local p [/ppp secret get $x profile]; :local d [/ppp secret get $x disabled];
                :local ip ""; :local mac ""; :do {:set ip [/ppp secret get $x remote-address]} on-error={}; :do {:set mac [/ppp secret get $x caller-id]} on-error={};
                :local display $c; :if (([:len $display] = 0) || ([:pick $display 0 11] = "ROOMISP-LAB")) do={ :set display $u; };
                :local item ("{\"type\":\"PPPOE\",\"key\":\"" . [$roomEsc $u] . "\",\"name\":\"" . [$roomEsc $display] . "\",\"comment\":\"" . [$roomEsc $c] . "\",\"profile\":\"" . [$roomEsc $p] . "\",\"ip\":\"" . [$roomEsc $ip] . "\",\"caller_id\":\"" . [$roomEsc $mac] . "\",\"disabled\":\"" . $d . "\"}");
                :set roomItems [$roomAppend $roomItems $item];
                :if ([:len $roomItems] > 2400) do={ [$roomSend $roomSeq "false" $roomItems]; :set roomSeq ($roomSeq + 1); :set roomItems ""; };
            };

            # DHCP: identidad estable por MAC; nombre = comentario, hostname o sufijo MAC.
            :foreach x in=[/ip dhcp-server lease find] do={
                :local mac [/ip dhcp-server lease get $x mac-address]; :local c [/ip dhcp-server lease get $x comment];
                :local ip [/ip dhcp-server lease get $x address]; :local host ""; :local server ""; :local d [/ip dhcp-server lease get $x disabled];
                :do {:set host [/ip dhcp-server lease get $x host-name]} on-error={}; :do {:set server [/ip dhcp-server lease get $x server]} on-error={};
                :local display $c; :if ([:len $display] = 0) do={ :set display $host; }; :if ([:len $display] = 0) do={ :set display ("DHCP-" . [:pick $mac 9 17]); };
                :local item ("{\"type\":\"DHCP\",\"key\":\"" . [$roomEsc $mac] . "\",\"name\":\"" . [$roomEsc $display] . "\",\"comment\":\"" . [$roomEsc $c] . "\",\"hostname\":\"" . [$roomEsc $host] . "\",\"ip\":\"" . [$roomEsc $ip] . "\",\"server\":\"" . [$roomEsc $server] . "\",\"disabled\":\"" . $d . "\"}");
                :set roomItems [$roomAppend $roomItems $item];
                :if ([:len $roomItems] > 2400) do={ [$roomSend $roomSeq "false" $roomItems]; :set roomSeq ($roomSeq + 1); :set roomItems ""; };
            };

            # IP fija: Simple Queue es evidencia administrable; target es la clave.
            :foreach x in=[/queue simple find] do={
                :local n [/queue simple get $x name]; :local c [/queue simple get $x comment]; :local target [/queue simple get $x target];
                :local max [/queue simple get $x max-limit]; :local d [/queue simple get $x disabled];
                :local display $c; :if ([:len $display] = 0) do={ :set display $n; };
                :local item ("{\"type\":\"STATIC\",\"key\":\"" . [$roomEsc $target] . "\",\"name\":\"" . [$roomEsc $display] . "\",\"queue\":\"" . [$roomEsc $n] . "\",\"target\":\"" . [$roomEsc $target] . "\",\"max_limit\":\"" . [$roomEsc $max] . "\",\"disabled\":\"" . $d . "\"}");
                :set roomItems [$roomAppend $roomItems $item];
                :if ([:len $roomItems] > 2400) do={ [$roomSend $roomSeq "false" $roomItems]; :set roomSeq ($roomSeq + 1); :set roomItems ""; };
            };

            # Hotspot: usuario, comentario y perfil. Las claves nunca salen del router.
            :foreach x in=[/ip hotspot user find] do={
                :local u [/ip hotspot user get $x name]; :local c [/ip hotspot user get $x comment];
                :local p [/ip hotspot user get $x profile]; :local limit ""; :local d [/ip hotspot user get $x disabled];
                :do {:set limit [/ip hotspot user get $x limit-uptime]} on-error={};
                :local display $c; :if ([:len $display] = 0) do={ :set display $u; };
                :local item ("{\"type\":\"HOTSPOT\",\"key\":\"" . [$roomEsc $u] . "\",\"name\":\"" . [$roomEsc $display] . "\",\"profile\":\"" . [$roomEsc $p] . "\",\"limit_uptime\":\"" . [$roomEsc $limit] . "\",\"disabled\":\"" . $d . "\"}");
                :set roomItems [$roomAppend $roomItems $item];
                :if ([:len $roomItems] > 2400) do={ [$roomSend $roomSeq "false" $roomItems]; :set roomSeq ($roomSeq + 1); :set roomItems ""; };
            };

            # Inventario tecnico: topologia y capacidades sin secretos.
            :foreach x in=[/interface find] do={
                :local n [/interface get $x name]; :local t [/interface get $x type]; :local r [/interface get $x running]; :local d [/interface get $x disabled]; :local mac ""; :do {:set mac [/interface get $x mac-address]} on-error={};
                :local item ("{\"type\":\"INTERFACE\",\"key\":\"" . [$roomEsc $n] . "\",\"interface_type\":\"" . [$roomEsc $t] . "\",\"running\":\"" . $r . "\",\"disabled\":\"" . $d . "\",\"mac\":\"" . [$roomEsc $mac] . "\"}");
                :set roomItems [$roomAppend $roomItems $item]; :if ([:len $roomItems] > 2400) do={ [$roomSend $roomSeq "false" $roomItems]; :set roomSeq ($roomSeq + 1); :set roomItems ""; };
            };
            :foreach x in=[/ip address find] do={ :local a [/ip address get $x address]; :local i [/ip address get $x interface]; :local item ("{\"type\":\"IP_ADDRESS\",\"key\":\"" . [$roomEsc $a] . "\",\"interface\":\"" . [$roomEsc $i] . "\"}"); :set roomItems [$roomAppend $roomItems $item]; :if ([:len $roomItems] > 2400) do={ [$roomSend $roomSeq "false" $roomItems]; :set roomSeq ($roomSeq + 1); :set roomItems ""; }; };
            :foreach x in=[/interface bridge find] do={ :local n [/interface bridge get $x name]; :local item ("{\"type\":\"BRIDGE\",\"key\":\"" . [$roomEsc $n] . "\"}"); :set roomItems [$roomAppend $roomItems $item]; };
            :foreach x in=[/interface vlan find] do={ :local n [/interface vlan get $x name]; :local v [/interface vlan get $x vlan-id]; :local i [/interface vlan get $x interface]; :local item ("{\"type\":\"VLAN\",\"key\":\"" . [$roomEsc $n] . "\",\"vlan_id\":\"" . $v . "\",\"interface\":\"" . [$roomEsc $i] . "\"}"); :set roomItems [$roomAppend $roomItems $item]; };
            :foreach x in=[/ip pool find] do={ :local n [/ip pool get $x name]; :local ranges [/ip pool get $x ranges]; :local item ("{\"type\":\"IP_POOL\",\"key\":\"" . [$roomEsc $n] . "\",\"ranges\":\"" . [$roomEsc $ranges] . "\"}"); :set roomItems [$roomAppend $roomItems $item]; };
            :foreach x in=[/ip dhcp-server find] do={ :local n [/ip dhcp-server get $x name]; :local i [/ip dhcp-server get $x interface]; :local pool [/ip dhcp-server get $x address-pool]; :local item ("{\"type\":\"DHCP_SERVER\",\"key\":\"" . [$roomEsc $n] . "\",\"interface\":\"" . [$roomEsc $i] . "\",\"pool\":\"" . [$roomEsc $pool] . "\"}"); :set roomItems [$roomAppend $roomItems $item]; };
            :foreach x in=[/interface pppoe-server server find] do={ :local n [/interface pppoe-server server get $x service-name]; :local i [/interface pppoe-server server get $x interface]; :local item ("{\"type\":\"PPPOE_SERVER\",\"key\":\"" . [$roomEsc $n] . "\",\"interface\":\"" . [$roomEsc $i] . "\"}"); :set roomItems [$roomAppend $roomItems $item]; };
            :local sysKey [/system identity get name]; :local sysItem ("{\"type\":\"SYSTEM\",\"key\":\"" . [$roomEsc $sysKey] . "\",\"version\":\"" . [$roomEsc [/system resource get version]] . "\",\"model\":\"" . [$roomEsc [/system resource get board-name]] . "\",\"architecture\":\"" . [$roomEsc [/system resource get architecture-name]] . "\",\"software_id\":\"" . [$roomEsc [/system license get software-id]] . "\"}"); :set roomItems [$roomAppend $roomItems $sysItem];
            :if ([:len $roomItems] > 2400) do={ [$roomSend $roomSeq "false" $roomItems]; :set roomSeq ($roomSeq + 1); :set roomItems ""; };
            [$roomSend $roomSeq "true" $roomItems];
            :log info ("ROOM ISP: inventario terminado en " . $roomSeq . " lote(s), sin passwords");
        } on-error={
            :log warning "ROOM ISP: inventario incompleto; se reintentara en la proxima conciliacion";
        };
    };

    # Poll liviano y conciliacion diaria. No se guarda un heartbeat historico por ciclo.
    :local roomPollInterval ($roomPollMinutes . "m");
    /system scheduler add name=ROOM_ISP_AGENT_SCHED interval=$roomPollInterval start-time=startup on-event="/system script run ROOM_ISP_AGENT" policy=read,write,test comment="ROOM ISP v4.1 - poll";
    /system scheduler add name=ROOM_ISP_INVENTORY_SCHED interval=1d start-time=00:17:00 on-event="/system script run ROOM_ISP_INVENTORY" policy=read,test comment="ROOM ISP v4.1 - inventario diario";
    /system script run ROOM_ISP_AGENT;
    /system script run ROOM_ISP_INVENTORY;
    :log info ("ROOM ISP: vinculacion completada; poll=" . $roomPollInterval . ", inventario=1d");
}

