# ROOM ISP - instalador/agente seguro v5.0-RC2 para RouterOS 6.49+ y RouterOS 7.x
# Generado desde el portal ISP. No copie configuracion.rsc ni credenciales antiguas.
# Instala SOLO scripts/schedulers ROOM_ISP_* y una regla de corte para la lista ROOM_ISP_SUSPENDED.

{
    :local roomEnrollUrl "__ROOM_ENROLL_URL__";
    :local roomAgentUrl "__ROOM_AGENT_URL__";
    :local roomEnrollCode "__ROOM_ENROLL_CODE__";
    # Preflight del archivo personalizado.
    :if ([:len $roomEnrollCode] < 40) do={ :error "ROOM ISP: codigo de enrolamiento invalido o no personalizado"; };
    :if ([:pick $roomEnrollUrl 0 8] != "https://") do={ :error "ROOM ISP: URL de enrolamiento invalida"; };
    :if ([:pick $roomAgentUrl 0 8] != "https://") do={ :error "ROOM ISP: URL de agente invalida"; };
    :log info "ROOM ISP v5.0-RC2: archivo personalizado OK";

    :local roomIdentity [/system identity get name];
    :local roomVersion [/system resource get version];
    :local roomModel [/system resource get board-name];
    :local roomArchitecture [/system resource get architecture-name];
    :local roomSoftwareId [/system license get software-id];
    # Detecta RouterOS y selecciona el camino TLS sin cambiar la configuracion real del ISP.
    # 7.19-7.20: puede aprovechar el builtin trust store introducido en 7.19.
    # 7.21+: puede aprovechar builtin-trust-store; ROOM no cambia ese ajuste global.
    # Si el trust disponible no valida Supabase, se usa el fallback de CA locales ROOM.
    :local roomVerCore $roomVersion;
    :local roomSpace [:find $roomVerCore " "];
    :if ([:typeof $roomSpace] != "nil") do={ :set roomVerCore [:pick $roomVerCore 0 $roomSpace]; };
    :local roomDot1 [:find $roomVerCore "."];
    :if ([:typeof $roomDot1] = "nil") do={ :error "ROOM ISP: no se pudo interpretar la version de RouterOS"; };
    :local roomMajor [:tonum [:pick $roomVerCore 0 $roomDot1]];
    :local roomAfterMajor [:pick $roomVerCore ($roomDot1 + 1) [:len $roomVerCore]];
    :local roomDot2 [:find $roomAfterMajor "."];
    :local roomMinorText $roomAfterMajor;
    :if ([:typeof $roomDot2] != "nil") do={ :set roomMinorText [:pick $roomAfterMajor 0 $roomDot2]; };
    :local roomMinor [:tonum $roomMinorText];
    :local roomTlsProfile "COMPAT_LOCAL_CA";
    :if ($roomMajor = 6) do={ :set roomTlsProfile "ROS6_LOCAL_CA"; };
    :if (($roomMajor = 7) && ($roomMinor < 19)) do={ :set roomTlsProfile "ROS7_0_18_LOCAL_CA"; };
    :if (($roomMajor = 7) && ($roomMinor >= 19) && ($roomMinor < 21)) do={ :set roomTlsProfile "ROS7_19_20_BUILTIN_OR_LOCAL"; };
    :if (($roomMajor = 7) && ($roomMinor >= 21)) do={ :set roomTlsProfile "ROS7_21_PLUS_BUILTIN_OR_LOCAL"; };
    :if ($roomMajor > 7) do={ :set roomTlsProfile "ROS_MODERNO_BUILTIN_OR_LOCAL"; };
    :log info ("ROOM ISP v5.0-RC2: RouterOS=" . $roomVersion . ", arquitectura=" . $roomArchitecture . ", TLS=" . $roomTlsProfile);

    # Preflight contra la MISMA Edge Function de enrolamiento. GET no consume el codigo.
    # Primero prueba el trust existente/builtin. Solo si falla instala CA ROOM.
    :local roomHttpsOk false;
    :local roomProbeData "";
    :do {
        :local roomProbe [/tool fetch url=$roomEnrollUrl http-method=get output=user as-value check-certificate=yes-without-crl];
        :set roomProbeData ($roomProbe->"data");
        :if ($roomProbeData = "ROOM_ISP|READY") do={ :set roomHttpsOk true; };
    } on-error={ :set roomHttpsOk false; };
    :if ($roomHttpsOk) do={ :log info "ROOM ISP v5.0-RC2: HTTPS verificado con trust existente/builtin"; };
    # Fallback TLS administrado por ROOM: solo se ejecuta si HTTPS verificado falla.
    # Instala exclusivamente autoridades con prefijo ROOM_ISP_CA_ y no modifica otros certificados.
    :if (!$roomHttpsOk) do={
        :log warning ("ROOM ISP v5.0-RC2: trust actual no valido para Supabase; instalando CA ROOM para perfil " . $roomTlsProfile);
        :foreach roomOldCa in=[/certificate find where name~"^ROOM_ISP_CA_"] do={ /certificate remove $roomOldCa; };
        :foreach roomOldFile in=[/file find where name~"^ROOM_ISP_CA_"] do={ /file remove $roomOldFile; };
        :local roomPem "";
        :local roomCaBase "";
        :local roomCaFile "";
        # ISRG Root X1 | SHA256 96:BC:EC:06:26:49:76:F3:74:60:77:9A:CF:28:C5:A7:CF:E8:A3:C0:AA:E1:1A:8F:FC:EE:05:C0:BD:DF:08:C6
        :set roomCaBase "ROOM_ISP_CA_ISRG_ROOT_X1";
        :set roomCaFile ($roomCaBase . ".txt");
        :set roomPem "-----BEGIN CERTIFICATE-----\r\nMIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw\r\nTzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh\r\ncmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4\r\nWhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu\r\nZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY\r\nMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc\r\nh77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+\r\n0TM8ukj13Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6U\r\nA5/TR5d8mUgjU+g4rk8Kb4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sW\r\nT8KOEUt+zwvo/7V3LvSye0rgTBIlDHCNAymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyH\r\nB5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ4Q7e2RCOFvu396j3x+UC\r\nB5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf1b0SHzUv\r\nKBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWn\r\nOlFuhjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTn\r\njh8BCNAw1FtxNrQHusEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbw\r\nqHyGO0aoSCqI3Haadr8faqU9GY/rOPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CI\r\nrU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV\r\nHRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY9umbbjANBgkq\r\nhkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL\r\nubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ\r\n3BebYhtF8GaV0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KK\r\nNFtY2PwByVS5uCbMiogziUwthDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5\r\nORAzI4JMPJ+GslWYHb4phowim57iaztXOoJwTdwJx4nLCgdNbOhdjsnvzqvHu7Ur\r\nTkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nxe5AW0wdeRlN8NwdC\r\njNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZAJzVc\r\noyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq\r\n4RgqsahDYVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPA\r\nmRGunUHBcnWEvgJBQl9nJEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57d\r\nemyPxgcYxn/eR44/KJ4EBs+lVDR3veyJm+kXQ99b21/+jh5Xos1AnX5iItreGCc=\r\n-----END CERTIFICATE-----\r\n";
        /file print file=$roomCaBase where name="";
        :delay 1s;
        /file set [find where name=$roomCaFile] contents=$roomPem;
        :do { /certificate import file-name=$roomCaFile passphrase=""; } on-error={ :error ("ROOM ISP TLS: no se pudo importar " . $roomCaBase); };
        :delay 1s;
        :foreach roomCa in=[/certificate find where name~$roomCaBase] do={ /certificate set $roomCa trusted=yes; };
        :foreach roomTmp in=[/file find where name=$roomCaFile] do={ /file remove $roomTmp; };
        # ISRG Root X2 | SHA256 69:72:9B:8E:15:A8:6E:FC:17:7A:57:AF:B7:17:1D:FC:64:AD:D2:8C:2F:CA:8C:F1:50:7E:34:45:3C:CB:14:70
        :set roomCaBase "ROOM_ISP_CA_ISRG_ROOT_X2";
        :set roomCaFile ($roomCaBase . ".txt");
        :set roomPem "-----BEGIN CERTIFICATE-----\r\nMIICGzCCAaGgAwIBAgIQQdKd0XLq7qeAwSxs6S+HUjAKBggqhkjOPQQDAzBPMQsw\r\nCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJuZXQgU2VjdXJpdHkgUmVzZWFyY2gg\r\nR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBYMjAeFw0yMDA5MDQwMDAwMDBaFw00\r\nMDA5MTcxNjAwMDBaME8xCzAJBgNVBAYTAlVTMSkwJwYDVQQKEyBJbnRlcm5ldCBT\r\nZWN1cml0eSBSZXNlYXJjaCBHcm91cDEVMBMGA1UEAxMMSVNSRyBSb290IFgyMHYw\r\nEAYHKoZIzj0CAQYFK4EEACIDYgAEzZvVn4CDCuwJSvMWSj5cz3es3mcFDR0HttwW\r\n+1qLFNvicWDEukWVEYmO6gbf9yoWHKS5xcUy4APgHoIYOIvXRdgKam7mAHf7AlF9\r\nItgKbppbd9/w+kHsOdx1ymgHDB/qo0IwQDAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0T\r\nAQH/BAUwAwEB/zAdBgNVHQ4EFgQUfEKWrt5LSDv6kviejM9ti6lyN5UwCgYIKoZI\r\nzj0EAwMDaAAwZQIwe3lORlCEwkSHRhtFcP9Ymd70/aTSVaYgLXTWNLxBo1BfASdW\r\ntL4ndQavEi51mI38AjEAi/V3bNTIZargCyzuFJ0nN6T5U6VR5CmD1/iQMVtCnwr1\r\n/q4AaOeMSQ+2b1tbFfLn\r\n-----END CERTIFICATE-----\r\n";
        /file print file=$roomCaBase where name="";
        :delay 1s;
        /file set [find where name=$roomCaFile] contents=$roomPem;
        :do { /certificate import file-name=$roomCaFile passphrase=""; } on-error={ :error ("ROOM ISP TLS: no se pudo importar " . $roomCaBase); };
        :delay 1s;
        :foreach roomCa in=[/certificate find where name~$roomCaBase] do={ /certificate set $roomCa trusted=yes; };
        :foreach roomTmp in=[/file find where name=$roomCaFile] do={ /file remove $roomTmp; };
        # GTS Root R1 | SHA256 D9:47:43:2A:BD:E7:B7:FA:90:FC:2E:6B:59:10:1B:12:80:E0:E1:C7:E4:E4:0F:A3:C6:88:7F:FF:57:A7:F4:CF
        :set roomCaBase "ROOM_ISP_CA_GTS_ROOT_R1";
        :set roomCaFile ($roomCaBase . ".txt");
        :set roomPem "-----BEGIN CERTIFICATE-----\r\nMIIFVzCCAz+gAwIBAgINAgPlk28xsBNJiGuiFzANBgkqhkiG9w0BAQwFADBHMQsw\r\nCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExMQzEU\r\nMBIGA1UEAxMLR1RTIFJvb3QgUjEwHhcNMTYwNjIyMDAwMDAwWhcNMzYwNjIyMDAw\r\nMDAwWjBHMQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZp\r\nY2VzIExMQzEUMBIGA1UEAxMLR1RTIFJvb3QgUjEwggIiMA0GCSqGSIb3DQEBAQUA\r\nA4ICDwAwggIKAoICAQC2EQKLHuOhd5s73L+UPreVp0A8of2C+X0yBoJx9vaMf/vo\r\n27xqLpeXo4xL+Sv2sfnOhB2x+cWX3u+58qPpvBKJXqeqUqv4IyfLpLGcY9vXmX7w\r\nCl7raKb0xlpHDU0QM+NOsROjyBhsS+z8CZDfnWQpJSMHobTSPS5g4M/SCYe7zUjw\r\nTcLCeoiKu7rPWRnWr4+wB7CeMfGCwcDfLqZtbBkOtdh+JhpFAz2weaSUKK0Pfybl\r\nqAj+lug8aJRT7oM6iCsVlgmy4HqMLnXWnOunVmSPlk9orj2XwoSPwLxAwAtcvfaH\r\nszVsrBhQf4TgTM2S0yDpM7xSma8ytSmzJSq0SPly4cpk9+aCEI3oncKKiPo4Zor8\r\nY/kB+Xj9e1x3+naH+uzfsQ55lVe0vSbv1gHR6xYKu44LtcXFilWr06zqkUspzBmk\r\nMiVOKvFlRNACzqrOSbTqn3yDsEB750Orp2yjj32JgfpMpf/VjsPOS+C12LOORc92\r\nwO1AK/1TD7Cn1TsNsYqiA94xrcx36m97PtbfkSIS5r762DL8EGMUUXLeXdYWk70p\r\naDPvOmbsB4om3xPXV2V4J95eSRQAogB/mqghtqmxlbCluQ0WEdrHbEg8QOB+DVrN\r\nVjzRlwW5y0vtOUucxD/SVRNuJLDWcfr0wbrM7Rv1/oFB2ACYPTrIrnqYNxgFlQID\r\nAQABo0IwQDAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4E\r\nFgQU5K8rJnEaK0gnhS9SZizv8IkTcT4wDQYJKoZIhvcNAQEMBQADggIBAJ+qQibb\r\nC5u+/x6Wki4+omVKapi6Ist9wTrYggoGxval3sBOh2Z5ofmmWJyq+bXmYOfg6LEe\r\nQkEzCzc9zolwFcq1JKjPa7XSQCGYzyI0zzvFIoTgxQ6KfF2I5DUkzps+GlQebtuy\r\nh6f88/qBVRRiClmpIgUxPoLW7ttXNLwzldMXG+gnoot7TiYaelpkttGsN/H9oPM4\r\n7HLwEXWdyzRSjeZ2axfG34arJ45JK3VmgRAhpuo+9K4l/3wV3s6MJT/KYnAK9y8J\r\nZgfIPxz88NtFMN9iiMG1D53Dn0reWVlHxYciNuaCp+0KueIHoI17eko8cdLiA6Ef\r\nMgfdG+RCzgwARWGAtQsgWSl4vflVy2PFPEz0tv/bal8xa5meLMFrUKTX5hgUvYU/\r\nZ6tGn6D/Qqc6f1zLXbBwHSs09dR2CQzreExZBfMzQsNhFRAbd03OIozUhfJFfbdT\r\n6u9AWpQKXCBfTkBdYiJ23//OYb2MI3jSNwLgjt7RETeJ9r/tSQdirpLsQBqvFAnZ\r\n0E6yove+7u7Y/9waLd64NnHi/Hm3lCXRSHNboTXns5lndcEZOitHTtNCjv0xyBZm\r\n2tIMPNuzjsmhDYAPexZ3FL//2wmUspO8IFgV6dtxQ/PeEMMA3KgqlbbC1j+Qa3bb\r\nbP6MvPJwNQzcmRk13NfIRmPVNnGuV/u3gm3c\r\n-----END CERTIFICATE-----\r\n";
        /file print file=$roomCaBase where name="";
        :delay 1s;
        /file set [find where name=$roomCaFile] contents=$roomPem;
        :do { /certificate import file-name=$roomCaFile passphrase=""; } on-error={ :error ("ROOM ISP TLS: no se pudo importar " . $roomCaBase); };
        :delay 1s;
        :foreach roomCa in=[/certificate find where name~$roomCaBase] do={ /certificate set $roomCa trusted=yes; };
        :foreach roomTmp in=[/file find where name=$roomCaFile] do={ /file remove $roomTmp; };
        # GTS Root R2 | SHA256 8D:25:CD:97:22:9D:BF:70:35:6B:DA:4E:B3:CC:73:40:31:E2:4C:F0:0F:AF:CF:D3:2D:C7:6E:B5:84:1C:7E:A8
        :set roomCaBase "ROOM_ISP_CA_GTS_ROOT_R2";
        :set roomCaFile ($roomCaBase . ".txt");
        :set roomPem "-----BEGIN CERTIFICATE-----\r\nMIIFVzCCAz+gAwIBAgINAgPlrsWNBCUaqxElqjANBgkqhkiG9w0BAQwFADBHMQsw\r\nCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExMQzEU\r\nMBIGA1UEAxMLR1RTIFJvb3QgUjIwHhcNMTYwNjIyMDAwMDAwWhcNMzYwNjIyMDAw\r\nMDAwWjBHMQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZp\r\nY2VzIExMQzEUMBIGA1UEAxMLR1RTIFJvb3QgUjIwggIiMA0GCSqGSIb3DQEBAQUA\r\nA4ICDwAwggIKAoICAQDO3v2m++zsFDQ8BwZabFn3GTXd98GdVarTzTukk3LvCvpt\r\nnfbwhYBboUhSnznFt+4orO/LdmgUud+tAWyZH8QiHZ/+cnfgLFuv5AS/T3KgGjSY\r\n6Dlo7JUle3ah5mm5hRm9iYz+re026nO8/4Piy33B0s5Ks40FnotJk9/BW9BuXvAu\r\nMC6C/Pq8tBcKSOWIm8Wba96wyrQD8Nr0kLhlZPdcTK3ofmZemde4wj7I0BOdre7k\r\nRXuJVfeKH2JShBKzwkCX44ofR5GmdFrS+LFjKBC4swm4VndAoiaYecb+3yXuPuWg\r\nf9RhD1FLPD+M2uFwdNjCaKH5wQzpoeJ/u1U8dgbuak7MkogwTZq9TwtImoS1mKPV\r\n+3PBV2HdKFZ1E66HjucMUQkQdYhMvI35ezzUIkgfKtzra7tEscszcTJGr61K8Yzo\r\ndDqs5xoic4DSMPclQsciOzsSrZYuxsN2B6ogtzVJV+mSSeh2FnIxZyuWfoqjx5RW\r\nIr9qS34BIbIjMt/kmkRtWVtd9QCgHJvGeJeNkP+byKq0rxFROV7Z+2et1VsRnTKa\r\nG73VululycslaVNVJ1zgyjbLiGH7HrfQy+4W+9OmTN6SpdTi3/UGVN4unUu0kzCq\r\ngc7dGtxRcw1PcOnlthYhGXmy5okLdWTK1au8CcEYof/UVKGFPP0UJAOyh9OktwID\r\nAQABo0IwQDAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4E\r\nFgQUu//KjiOfT5nK2+JopqUVJxce2Q4wDQYJKoZIhvcNAQEMBQADggIBAB/Kzt3H\r\nvqGf2SdMC9wXmBFqiN495nFWcrKeGk6c1SuYJF2ba3uwM4IJvd8lRuqYnrYb/oM8\r\n0mJhwQTtzuDFycgTE1XnqGOtjHsB/ncw4c5omwX4Eu55MaBBRTUoCnGkJE+M3DyC\r\nB19m3H0Q/gxhswWV7uGugQ+o+MePTagjAiZrHYNSVc61LwDKgEDg4XSsYPWHgJ2u\r\nNmSRXbBoGOqKYcl3qJfEycel/FVL8/B/uWU9J2jQzGv6U53hkRrJXRqWbTKH7QMg\r\nyALOWr7Z6v2yTcQvG99fevX4i8buMTolUVVnjWQye+mew4K6Ki3pHrTgSAai/Gev\r\nHyICc/sgCq+dVEuhzf9gR7A/Xe8bVr2XIZYtCtFenTgCR2y59PYjJbigapordwj6\r\nxLEokCZYCDzifqrXPW+6MYgKBesntaFJ7qBFVHvmJ2WZICGoo7z7GJa7Um8M7YNR\r\nTOlZ4iBgxcJlkoKM8xAfDoqXvneCbT+PHV28SSe9zE8P4c52hgQjxcCMElv924Sg\r\nJPFI/2R80L5cFtHvma3AH/vLrrw4IgYmZNralw4/KBVEqE8AyvCazM90arQ+POuV\r\n7LXTWtiBmelDGDfrs7vRWGJB82bSj6p4lVQgw1oudCvV0b4YacCs1aTPObpRhANl\r\n6WLAYv7YTVWW4tAR+kg0Eeye7QUd5MjWHYbL\r\n-----END CERTIFICATE-----\r\n";
        /file print file=$roomCaBase where name="";
        :delay 1s;
        /file set [find where name=$roomCaFile] contents=$roomPem;
        :do { /certificate import file-name=$roomCaFile passphrase=""; } on-error={ :error ("ROOM ISP TLS: no se pudo importar " . $roomCaBase); };
        :delay 1s;
        :foreach roomCa in=[/certificate find where name~$roomCaBase] do={ /certificate set $roomCa trusted=yes; };
        :foreach roomTmp in=[/file find where name=$roomCaFile] do={ /file remove $roomTmp; };
        # GTS Root R3 | SHA256 34:D8:A7:3E:E2:08:D9:BC:DB:0D:95:65:20:93:4B:4E:40:E6:94:82:59:6E:8B:6F:73:C8:42:6B:01:0A:6F:48
        :set roomCaBase "ROOM_ISP_CA_GTS_ROOT_R3";
        :set roomCaFile ($roomCaBase . ".txt");
        :set roomPem "-----BEGIN CERTIFICATE-----\r\nMIICCTCCAY6gAwIBAgINAgPluILrIPglJ209ZjAKBggqhkjOPQQDAzBHMQswCQYD\r\nVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExMQzEUMBIG\r\nA1UEAxMLR1RTIFJvb3QgUjMwHhcNMTYwNjIyMDAwMDAwWhcNMzYwNjIyMDAwMDAw\r\nWjBHMQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2Vz\r\nIExMQzEUMBIGA1UEAxMLR1RTIFJvb3QgUjMwdjAQBgcqhkjOPQIBBgUrgQQAIgNi\r\nAAQfTzOHMymKoYTey8chWEGJ6ladK0uFxh1MJ7x/JlFyb+Kf1qPKzEUURout736G\r\njOyxfi//qXGdGIRFBEFVbivqJn+7kAHjSxm65FSWRQmx1WyRRK2EE46ajA2ADDL2\r\n4CejQjBAMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQW\r\nBBTB8Sa6oC2uhYHP0/EqEr24Cmf9vDAKBggqhkjOPQQDAwNpADBmAjEA9uEglRR7\r\nVKOQFhG/hMjqb2sXnh5GmCCbn9MN2azTL818+FsuVbu/3ZL3pAzcMeGiAjEA/Jdm\r\nZuVDFhOD3cffL74UOO0BzrEXGhF16b0DjyZ+hOXJYKaV11RZt+cRLInUue4X\r\n-----END CERTIFICATE-----\r\n";
        /file print file=$roomCaBase where name="";
        :delay 1s;
        /file set [find where name=$roomCaFile] contents=$roomPem;
        :do { /certificate import file-name=$roomCaFile passphrase=""; } on-error={ :error ("ROOM ISP TLS: no se pudo importar " . $roomCaBase); };
        :delay 1s;
        :foreach roomCa in=[/certificate find where name~$roomCaBase] do={ /certificate set $roomCa trusted=yes; };
        :foreach roomTmp in=[/file find where name=$roomCaFile] do={ /file remove $roomTmp; };
        # GTS Root R4 | SHA256 34:9D:FA:40:58:C5:E2:63:12:3B:39:8A:E7:95:57:3C:4E:13:13:C8:3F:E6:8F:93:55:6C:D5:E8:03:1B:3C:7D
        :set roomCaBase "ROOM_ISP_CA_GTS_ROOT_R4";
        :set roomCaFile ($roomCaBase . ".txt");
        :set roomPem "-----BEGIN CERTIFICATE-----\r\nMIICCTCCAY6gAwIBAgINAgPlwGjvYxqccpBQUjAKBggqhkjOPQQDAzBHMQswCQYD\r\nVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExMQzEUMBIG\r\nA1UEAxMLR1RTIFJvb3QgUjQwHhcNMTYwNjIyMDAwMDAwWhcNMzYwNjIyMDAwMDAw\r\nWjBHMQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2Vz\r\nIExMQzEUMBIGA1UEAxMLR1RTIFJvb3QgUjQwdjAQBgcqhkjOPQIBBgUrgQQAIgNi\r\nAATzdHOnaItgrkO4NcWBMHtLSZ37wWHO5t5GvWvVYRg1rkDdc/eJkTBa6zzuhXyi\r\nQHY7qca4R9gq55KRanPpsXI5nymfopjTX15YhmUPoYRlBtHci8nHc8iMai/lxKvR\r\nHYqjQjBAMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQW\r\nBBSATNbrdP9JNqPV2Py1PsVq8JQdjDAKBggqhkjOPQQDAwNpADBmAjEA6ED/g94D\r\n9J+uHXqnLrmvT/aDHQ4thQEd0dlq7A/Cr8deVl5c1RxYIigL9zC2L7F8AjEA8GE8\r\np/SgguMh1YQdc4acLa/KNJvxn7kjNuK8YAOdgLOaVsjh4rsUecrNIdSUtUlD\r\n-----END CERTIFICATE-----\r\n";
        /file print file=$roomCaBase where name="";
        :delay 1s;
        /file set [find where name=$roomCaFile] contents=$roomPem;
        :do { /certificate import file-name=$roomCaFile passphrase=""; } on-error={ :error ("ROOM ISP TLS: no se pudo importar " . $roomCaBase); };
        :delay 1s;
        :foreach roomCa in=[/certificate find where name~$roomCaBase] do={ /certificate set $roomCa trusted=yes; };
        :foreach roomTmp in=[/file find where name=$roomCaFile] do={ /file remove $roomTmp; };
        # SSL.com TLS RSA Root CA 2022 | SHA256 8F:AF:7D:2E:2C:B4:70:9B:B8:E0:B3:36:66:BF:75:A5:DD:45:B5:DE:48:0F:8E:A8:D4:BF:E6:BE:BC:17:F2:ED
        :set roomCaBase "ROOM_ISP_CA_SSLCOM_TLS_RSA_2022";
        :set roomCaFile ($roomCaBase . ".txt");
        :set roomPem "-----BEGIN CERTIFICATE-----\r\nMIIFiTCCA3GgAwIBAgIQb77arXO9CEDii02+1PdbkTANBgkqhkiG9w0BAQsFADBO\r\nMQswCQYDVQQGEwJVUzEYMBYGA1UECgwPU1NMIENvcnBvcmF0aW9uMSUwIwYDVQQD\r\nDBxTU0wuY29tIFRMUyBSU0EgUm9vdCBDQSAyMDIyMB4XDTIyMDgyNTE2MzQyMloX\r\nDTQ2MDgxOTE2MzQyMVowTjELMAkGA1UEBhMCVVMxGDAWBgNVBAoMD1NTTCBDb3Jw\r\nb3JhdGlvbjElMCMGA1UEAwwcU1NMLmNvbSBUTFMgUlNBIFJvb3QgQ0EgMjAyMjCC\r\nAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANCkCXJPQIgSYT41I57u9nTP\r\nL3tYPc48DRAokC+X94xI2KDYJbFMsBFMF3NQ0CJKY7uB0ylu1bUJPiYYf7ISf5OY\r\nt6/wNr/y7hienDtSxUcZXXTzZGbVXcdotL8bHAajvI9AI7YexoS9UcQbOcGV0ins\r\nS657Lb85/bRi3pZ7QcacoOAGcvvwB5cJOYF0r/c0WRFXCsJbwST0MXMwgsadugL3\r\nPnxEX4MN8/HdIGkWCVDi1FW24IBydm5MR7d1VVm0U3TZlMZBrViKMWYPHqIbKUBO\r\nL9975hYsLfy/7PO0+r4Y9ptJ1O4Fbtk085zx7AGL0SDGD6C1vBdOSHtRwvzpXGk3\r\nR2azaPgVKPC506QVzFpPulJwoxJF3ca6TvvC0PeoUidtbnm1jPx7jMEWTO6Af77w\r\ndr5BUxIzrlo4QqvXDz5BjXYHMtWrifZOZ9mxQnUjbvPNQrL8VfVThxc7wDNY8VLS\r\n+YCk8OjwO4s4zKTGkH8PnP2L0aPP2oOnaclQNtVcBdIKQXTbYxE3waWglksejBYS\r\nd66UNHsef8JmAOSqg+qKkK3ONkRN0VHpvB/zagX9wHQfJRlAUW7qglFA35u5CCoG\r\nAtUjHBPW6dvbxrB6y3snm/vg1UYk7RBLY0ulBY+6uB0rpvqR4pJSvezrZ5dtmi2f\r\ngTIFZzL7SAg/2SW4BCUvAgMBAAGjYzBhMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0j\r\nBBgwFoAU+y437uOEeicuzRk1sTN8/9REQrkwHQYDVR0OBBYEFPsuN+7jhHonLs0Z\r\nNbEzfP/UREK5MA4GA1UdDwEB/wQEAwIBhjANBgkqhkiG9w0BAQsFAAOCAgEAjYlt\r\nhEUY8U+zoO9opMAdrDC8Z2awms22qyIZZtM7QbUQnRC6cm4pJCAcAZli05bg4vsM\r\nQtfhWsSWTVTNj8pDU/0quOr4ZcoBwq1gaAafORpR2eCNJvkLTqVTJXojpBzOCBvf\r\nR4iyrT7gJ4eLSYwfqUdYe5byiB0YrrPRpgqU+tvT5TgKa3kSM/tKWTcWQA673vWJ\r\nDPFs0/dRa1419dvAJuoSc06pkZCmF8NsLzjUo3KUQyxi4U5cMj29TH0ZR6LDSeeW\r\nP4+a0zvkEdiLA9z2tmBVGKaBUfPhqBVq6+AL8BQx1rmMRTqoENjwuSfr98t67wVy\r\nlrXEj5ZzxOhWc5y8aVFjvO9nHEMaX3cZHxj4HCUp+UmZKbaSPaKDN7EgkaibMOlq\r\nbLQjk2UEqxHzDh1TJElTHaE/nUiSEeJ9DU/1172iWD54nR4fK/4huxoTtrEoZP2w\r\nAgDHbICivRZQIA9ygV/MlP+7mea6kMvq+cYMwq7FGc4zoWtcu358NFcXrfA/rs3q\r\nr5nsLFR+jM4uElZI7xc7P0peYNLcdDa8pUNjyw9bowJWCZ4kLOGGgYz+qxcs+sji\r\nMho6/4UIyYOf8kpIEFR3N+2ivEC+5BB09+Rbu7nzifmPQdjH5FCQNYA+HLhNkNPU\r\n98OwoX6EyneSMSy4kLGCenROmxMmtNVQZlR4rmA=\r\n-----END CERTIFICATE-----\r\n";
        /file print file=$roomCaBase where name="";
        :delay 1s;
        /file set [find where name=$roomCaFile] contents=$roomPem;
        :do { /certificate import file-name=$roomCaFile passphrase=""; } on-error={ :error ("ROOM ISP TLS: no se pudo importar " . $roomCaBase); };
        :delay 1s;
        :foreach roomCa in=[/certificate find where name~$roomCaBase] do={ /certificate set $roomCa trusted=yes; };
        :foreach roomTmp in=[/file find where name=$roomCaFile] do={ /file remove $roomTmp; };
        # SSL.com TLS ECC Root CA 2022 | SHA256 C3:2F:FD:9F:46:F9:36:D1:6C:36:73:99:09:59:43:4B:9A:D6:0A:AF:BB:9E:7C:F3:36:54:F1:44:CC:1B:A1:43
        :set roomCaBase "ROOM_ISP_CA_SSLCOM_TLS_ECC_2022";
        :set roomCaFile ($roomCaBase . ".txt");
        :set roomPem "-----BEGIN CERTIFICATE-----\r\nMIICOjCCAcCgAwIBAgIQFAP1q/s3ixdAW+JDsqXRxDAKBggqhkjOPQQDAzBOMQsw\r\nCQYDVQQGEwJVUzEYMBYGA1UECgwPU1NMIENvcnBvcmF0aW9uMSUwIwYDVQQDDBxT\r\nU0wuY29tIFRMUyBFQ0MgUm9vdCBDQSAyMDIyMB4XDTIyMDgyNTE2MzM0OFoXDTQ2\r\nMDgxOTE2MzM0N1owTjELMAkGA1UEBhMCVVMxGDAWBgNVBAoMD1NTTCBDb3Jwb3Jh\r\ndGlvbjElMCMGA1UEAwwcU1NMLmNvbSBUTFMgRUNDIFJvb3QgQ0EgMjAyMjB2MBAG\r\nByqGSM49AgEGBSuBBAAiA2IABEUpNXP6wrgjzhR9qLFNoFs27iosU8NgCTWyJGYm\r\nacCzldZdkkAZDsalE3D07xJRKF3nzL35PIXBz5SQySvOkkJYWWf9lCcQZIxPBLFN\r\nSeR7T5v15wj4A4j3p8OSSxlUgaNjMGEwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSME\r\nGDAWgBSJjy+j6CugFFR781a4Jl9nOAuc0DAdBgNVHQ4EFgQUiY8vo+groBRUe/NW\r\nuCZfZzgLnNAwDgYDVR0PAQH/BAQDAgGGMAoGCCqGSM49BAMDA2gAMGUCMFXjIlbp\r\n15IkWE8elDIPDAI2wv2sdDJO4fscgIijzPvX6yv/N33w7deedWo1dlJF4AIxAMeN\r\nb0Igj762TVntd00pxCAgRWSGOlDGxK0tk/UYfXLtqc/ErFc2KAhl3zx5Zn6g6g==\r\n-----END CERTIFICATE-----\r\n";
        /file print file=$roomCaBase where name="";
        :delay 1s;
        /file set [find where name=$roomCaFile] contents=$roomPem;
        :do { /certificate import file-name=$roomCaFile passphrase=""; } on-error={ :error ("ROOM ISP TLS: no se pudo importar " . $roomCaBase); };
        :delay 1s;
        :foreach roomCa in=[/certificate find where name~$roomCaBase] do={ /certificate set $roomCa trusted=yes; };
        :foreach roomTmp in=[/file find where name=$roomCaFile] do={ /file remove $roomTmp; };
        # SSL.com Root Certification Authority RSA | SHA256 85:66:6A:56:2E:E0:BE:5C:E9:25:C1:D8:89:0A:6F:76:A8:7E:C1:6D:4D:7D:5F:29:EA:74:19:CF:20:12:3B:69
        :set roomCaBase "ROOM_ISP_CA_SSLCOM_ROOT_RSA";
        :set roomCaFile ($roomCaBase . ".txt");
        :set roomPem "-----BEGIN CERTIFICATE-----\r\nMIIF3TCCA8WgAwIBAgIIeyyb0xaAMpkwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UE\r\nBhMCVVMxDjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3VzdG9uMRgwFgYDVQQK\r\nDA9TU0wgQ29ycG9yYXRpb24xMTAvBgNVBAMMKFNTTC5jb20gUm9vdCBDZXJ0aWZp\r\nY2F0aW9uIEF1dGhvcml0eSBSU0EwHhcNMTYwMjEyMTczOTM5WhcNNDEwMjEyMTcz\r\nOTM5WjB8MQswCQYDVQQGEwJVUzEOMAwGA1UECAwFVGV4YXMxEDAOBgNVBAcMB0hv\r\ndXN0b24xGDAWBgNVBAoMD1NTTCBDb3Jwb3JhdGlvbjExMC8GA1UEAwwoU1NMLmNv\r\nbSBSb290IENlcnRpZmljYXRpb24gQXV0aG9yaXR5IFJTQTCCAiIwDQYJKoZIhvcN\r\nAQEBBQADggIPADCCAgoCggIBAPkP3aMrfcvQKv7sZ4Wm5y4bunfh4/WvpOz6Sl2R\r\nxFdHaxh3a3by/ZPkPQ/CFp4LZsNWlJ4Xg4XOVu/yFv0AYvUiCVToZRdOQbngT0aX\r\nqhvIuG5iXmmxX9sqAn78bMrzQdjt0Oj8P2FI7bADFB0QDksZ4LtO7IZl/zbzXmcC\r\nC52GVWH9ejjt/uIZALdvoVBidXQ8oPrIJZK0bnoix/geoeOy3ZExqysdBP+lSgQ3\r\n6YWkMyv94tZVNHwZpEpox7Ko07fKoZOI68GXvIz5HdkihCR0xwQ9aqkpk8zruFvh\r\n/l8lqjRYyMEjVJ0bmBHDOJx+PYZspQ9AhnwC9FwCTyjLrnGfDzrIM/4RJTXq/LrF\r\nYD3ZfBjVsqnTdXgDciLKOsMf7yzlLqn6niy2UUb9rwPW6mBo6oUWNmuF6R7As93E\r\nJNyAKoFBbZQ+yODJgUEAnl6/f8UImKIYLEJAs/lvOCdLToD0PYFH4Ih86hzOtXVc\r\nUS4cK38acijnALXRdMbX5J+tB5O2UzU1/Dfkw/ZdFr4hc96SCvigY2q8lpJqPvi8\r\nZVWb3vUNiSYE/CUapiVpy8JtynziWV+XrOvvLsi81xtZPCvM8hnIk2snYxnP/Okm\r\n+Mpxm3+T/jRnhE6Z6/yzeAkzcLpmpnbtG3PrGqUNxCITIJRWCk4sbE6x/c+cCbqi\r\nM+2HAgMBAAGjYzBhMB0GA1UdDgQWBBTdBAkHovV6fVJTEpKV7jiAJQ2mWTAPBgNV\r\nHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFN0ECQei9Xp9UlMSkpXuOIAlDaZZMA4G\r\nA1UdDwEB/wQEAwIBhjANBgkqhkiG9w0BAQsFAAOCAgEAIBgRlCn7Jp0cHh5wYfGV\r\ncpNxJK1ok1iOMq8bs3AD/CUrdIWQPXhq9LmLpZc7tRiRux6n+UBbkflVma8eEdBc\r\nHadm47GUBwwyOabqG7B52B2ccETjit3E+ZUfijhDPwGFpUenPUayvOUiaPd7nNgs\r\nPgohyC0zrL/FgZkxdMF1ccW+sfAjRfSda/wZY52jvATGGAslu1OJD7OAUN5F7kR/\r\nq5R4ZJjT9ijdh9hwZXT7DrkT66cPYakylszeu+1jTBi7qUD3oFRuIIhxdRjqerQ0\r\ncuAjJ3dctpDqhiVAq+8zD8ufgr6iIPv2tS0a5sKFsXQP+8hlAqRSAUfdSSLBv9jr\r\na6x+3uxjMxW3IwiPxg+NQVrdjsW5j+VFP3jbutIbQLH+cU0/4IGiul607BXgk90I\r\nH37hVZkLId6Tngr75qNJvTYw/ud3sqB1l7UtgYgXZSD32pAAn8lSzDLKNXz1PQ/Y\r\nK9f1JmzJBjSWFupwWRoyeXkLtoh/D1JIPb9s2KJELtFOt3JY04kTlf5Eq/jXixtu\r\nnLwsoFvVagCvXzfh1foQC5ichucmj87w7G6KVwuA406ywKBjYZC6VWg3dGq2ktuf\r\noYYitmUnDuy2n0Jg5GfCtdpBC8TTi2EbvPofkSvXRAdeuims2cXp71NIWuuA8ShY\r\nIc2wBlX7Jz9TkHCpBB5XJ7k=\r\n-----END CERTIFICATE-----\r\n";
        /file print file=$roomCaBase where name="";
        :delay 1s;
        /file set [find where name=$roomCaFile] contents=$roomPem;
        :do { /certificate import file-name=$roomCaFile passphrase=""; } on-error={ :error ("ROOM ISP TLS: no se pudo importar " . $roomCaBase); };
        :delay 1s;
        :foreach roomCa in=[/certificate find where name~$roomCaBase] do={ /certificate set $roomCa trusted=yes; };
        :foreach roomTmp in=[/file find where name=$roomCaFile] do={ /file remove $roomTmp; };
        # SSL.com Root Certification Authority ECC | SHA256 34:17:BB:06:CC:60:07:DA:1B:96:1C:92:0B:8A:B4:CE:3F:AD:82:0E:4A:A3:0B:9A:CB:C4:A7:4E:BD:CE:BC:65
        :set roomCaBase "ROOM_ISP_CA_SSLCOM_ROOT_ECC";
        :set roomCaFile ($roomCaBase . ".txt");
        :set roomPem "-----BEGIN CERTIFICATE-----\r\nMIICjTCCAhSgAwIBAgIIdebfy8FoW6gwCgYIKoZIzj0EAwIwfDELMAkGA1UEBhMC\r\nVVMxDjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3VzdG9uMRgwFgYDVQQKDA9T\r\nU0wgQ29ycG9yYXRpb24xMTAvBgNVBAMMKFNTTC5jb20gUm9vdCBDZXJ0aWZpY2F0\r\naW9uIEF1dGhvcml0eSBFQ0MwHhcNMTYwMjEyMTgxNDAzWhcNNDEwMjEyMTgxNDAz\r\nWjB8MQswCQYDVQQGEwJVUzEOMAwGA1UECAwFVGV4YXMxEDAOBgNVBAcMB0hvdXN0\r\nb24xGDAWBgNVBAoMD1NTTCBDb3Jwb3JhdGlvbjExMC8GA1UEAwwoU1NMLmNvbSBS\r\nb290IENlcnRpZmljYXRpb24gQXV0aG9yaXR5IEVDQzB2MBAGByqGSM49AgEGBSuB\r\nBAAiA2IABEVuqVDEpiM2nl8ojRfLliJkP9x6jh3MCLOicSS6jkm5BBtHllirLZXI\r\n7Z4INcgn64mMU1jrYor+8FsPazFSY0E7ic3s7LaNGdM0B9y7xgZ/wkWV7Mt/qCPg\r\nCemB+vNH06NjMGEwHQYDVR0OBBYEFILRhXMw5zUE044CkvvlpNHEIejNMA8GA1Ud\r\nEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUgtGFczDnNQTTjgKS++Wk0cQh6M0wDgYD\r\nVR0PAQH/BAQDAgGGMAoGCCqGSM49BAMCA2cAMGQCMG/n61kRpGDPYbCWe+0F+S8T\r\nkdzt5fxQaxFGRrMcIQBiu77D5+jNB5n5DQtdcj7EqgIwH7y6C+IwJPt8bYBVCpk+\r\ngA0z5Wajs6O7pdWLjwkspl1+4vAHCGht0nxpbl/f5Wpl\r\n-----END CERTIFICATE-----\r\n";
        /file print file=$roomCaBase where name="";
        :delay 1s;
        /file set [find where name=$roomCaFile] contents=$roomPem;
        :do { /certificate import file-name=$roomCaFile passphrase=""; } on-error={ :error ("ROOM ISP TLS: no se pudo importar " . $roomCaBase); };
        :delay 1s;
        :foreach roomCa in=[/certificate find where name~$roomCaBase] do={ /certificate set $roomCa trusted=yes; };
        :foreach roomTmp in=[/file find where name=$roomCaFile] do={ /file remove $roomTmp; };
        :set roomHttpsOk false;
        :set roomProbeData "";
        :do {
            :local roomProbe [/tool fetch url=$roomEnrollUrl http-method=get output=user as-value check-certificate=yes-without-crl];
            :set roomProbeData ($roomProbe->"data");
            :if ($roomProbeData = "ROOM_ISP|READY") do={ :set roomHttpsOk true; };
        } on-error={ :set roomHttpsOk false; };
        :if (!$roomHttpsOk) do={ :error "ROOM ISP TLS: HTTPS verificado fallo aun despues de instalar CA ROOM"; };
        :log info "ROOM ISP v5.0-RC2: CA ROOM instaladas y HTTPS verificado";
    };
    :log info "ROOM ISP v5.0-RC2: preflight TLS OK; iniciando enrolamiento";
    :local roomPppoe [/ppp secret print count-only where service=pppoe];
    :local roomDhcp [/ip dhcp-server lease print count-only];
    :local roomHotspot [/ip hotspot user print count-only];
    :local roomQueues [/queue simple print count-only];
    :local roomBody ("{\"protocol\":4,\"connector_version\":\"5.0-RC1\",\"enrollment_code\":\"" . $roomEnrollCode . "\",\"device\":{\"identity\":\"" . $roomIdentity . "\",\"routeros_version\":\"" . $roomVersion . "\",\"architecture\":\"" . $roomArchitecture . "\",\"model\":\"" . $roomModel . "\",\"software_id\":\"" . $roomSoftwareId . "\"},\"capabilities\":{\"pppoe\":" . $roomPppoe . ",\"dhcp\":" . $roomDhcp . ",\"hotspot\":" . $roomHotspot . ",\"simple_queues\":" . $roomQueues . "}}");

    :local roomEnrollment;
    :log info "ROOM ISP v5.0-RC2: contactando backend";
    :do { :set roomEnrollment [/tool fetch url=$roomEnrollUrl http-method=post http-header-field="Content-Type:application/json" http-data=$roomBody output=user as-value check-certificate=yes-without-crl]; } on-error={ :error "ROOM ISP enrollment failed"; };
    :local roomResponse ($roomEnrollment->"data");
    :if ([:pick $roomResponse 0 3] != "OK|") do={ :log warning ("ROOM ISP v5.0-RC2: enrolamiento rechazado: " . $roomResponse); :error "ROOM ISP enrollment rejected"; };
    :log info "ROOM ISP v5.0-RC2: enrolamiento aceptado";
    :local roomRest [:pick $roomResponse 3 [:len $roomResponse]]; :local roomP1 [:find $roomRest "|"]; :local roomRouterId [:pick $roomRest 0 $roomP1];
    :set roomRest [:pick $roomRest ($roomP1 + 1) [:len $roomRest]]; :local roomP2 [:find $roomRest "|"]; :local roomAgentToken [:pick $roomRest 0 $roomP2];
    :local roomPollMinutes [:tonum [:pick $roomRest ($roomP2 + 1) [:len $roomRest]]]; :if (($roomPollMinutes < 5) || ($roomPollMinutes > 60)) do={ :set roomPollMinutes 5; };
    :if (([:len $roomRouterId] < 20) || ([:len $roomAgentToken] < 32)) do={ :error "ROOM ISP: respuesta incompleta"; };

    # Limpieza idempotente: SOLO después de que el backend aceptó el enrolamiento.
    # Las CA ROOM_ISP_CA_* se conservan porque RouterOS 6/7 antiguos las necesitan para los polls HTTPS.
    # Si había una instalación vieja o incompleta, deja exactamente una instalación ROOM ISP.
    :log info "ROOM ISP v5.0-RC2: limpiando instalacion ROOM ISP anterior";
    :foreach roomItem in=[/system scheduler find where name~"^ROOM_ISP_"] do={ /system scheduler disable $roomItem; };
    :foreach roomItem in=[/system scheduler find where name~"^ROOM_ISP_"] do={ /system scheduler remove $roomItem; };
    :foreach roomItem in=[/system script find where name~"^ROOM_ISP_"] do={ /system script remove $roomItem; };

    # Elimina solo la regla firewall propiedad de ROOM ISP y la crea una sola vez.
    # NO elimina usuarios PPPoE, perfiles, colas ni leases existentes.
    :foreach roomRule in=[/ip firewall filter find where comment="ROOM ISP - suspension"] do={ /ip firewall filter remove $roomRule; };
    /ip firewall filter add chain=forward src-address-list=ROOM_ISP_SUSPENDED action=drop place-before=0 comment="ROOM ISP - suspension";

    :local roomStateSource (":global roomIspRouterId \"" . $roomRouterId . "\";\r\n:global roomIspAgentToken \"" . $roomAgentToken . "\";\r\n:global roomIspAgentUrl \"" . $roomAgentUrl . "\";\r\n:global roomIspProtocol 4;\r\n:global roomIspTlsProfile \"" . $roomTlsProfile . "\";");
    /system script add name=ROOM_ISP_STATE comment="ROOM ISP v5.0-RC2 - credencial privada" policy=read source=$roomStateSource;

    /system script add name=ROOM_ISP_AGENT comment="ROOM ISP v5.0-RC2 - control de acceso y cobros" policy=read,write,test source={
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

    /system script add name=ROOM_ISP_INVENTORY comment="ROOM ISP v5.0-RC2 - inventario por lotes sin passwords" policy=read,test source={
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
    :foreach roomSched in=[/system scheduler find where name="ROOM_ISP_AGENT_SCHED"] do={ /system scheduler remove $roomSched; };
    :foreach roomSched in=[/system scheduler find where name="ROOM_ISP_INVENTORY_SCHED"] do={ /system scheduler remove $roomSched; };
    /system scheduler add name=ROOM_ISP_AGENT_SCHED interval=$roomPollInterval start-time=startup on-event="/system script run ROOM_ISP_AGENT" policy=read,write,test comment="ROOM ISP v5.0-RC2 - poll";
    /system scheduler add name=ROOM_ISP_INVENTORY_SCHED interval=1d start-time=00:17:00 on-event="/system script run ROOM_ISP_INVENTORY" policy=read,test comment="ROOM ISP v5.0-RC2 - inventario diario";
    /system script run ROOM_ISP_AGENT;
    /system script run ROOM_ISP_INVENTORY;
    :log info ("ROOM ISP v5.0-RC2: INSTALACION COMPLETA; poll=" . $roomPollInterval . ", inventario=1d");
}
