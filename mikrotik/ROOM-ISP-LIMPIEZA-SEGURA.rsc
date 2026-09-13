# ROOM ISP - limpieza segura de restos de instalaciones fallidas
# SOLO elimina objetos creados por ROOM ISP.
{
    :log warning "ROOM ISP: iniciando limpieza segura";
    :foreach x in=[/system scheduler find where name~"^ROOM_ISP_"] do={ /system scheduler disable $x; };
    :foreach x in=[/system scheduler find where name~"^ROOM_ISP_"] do={ /system scheduler remove $x; };
    :foreach x in=[/system script find where name~"^ROOM_ISP_"] do={ /system script remove $x; };
    :foreach x in=[/ip firewall filter find where comment="ROOM ISP - suspension"] do={ /ip firewall filter remove $x; };
    :foreach x in=[/certificate find where name~"^ROOM_ISP_CA_"] do={ /certificate remove $x; };
    :foreach x in=[/file find where name~"^ROOM_ISP_CA_"] do={ /file remove $x; };
    :log warning "ROOM ISP: limpieza terminada. PPPoE, perfiles, colas, leases, usuarios Hotspot y certificados ajenos a ROOM NO fueron tocados.";
}
