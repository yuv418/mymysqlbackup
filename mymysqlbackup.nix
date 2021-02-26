{ config, lib, pkgs, ... }:

let
  mcfg = config.services.mymysqlbackup;
  defaultUser = "mysqlbackup";
in with lib; {
  options = {
    services.mymysqlbackup = {
      enable = mkEnableOption "My MySQL backups";

      calendar = mkOption {
        type = types.str;
        default = "00:00:00";
        description = ''
          SystemD calendar time to run service
        '';
      };

      user = mkOption {
      type = types.str;
        default = config.services.mysql.user;
        description = "User to run service as ";
      };

      dir = mkOption {
        type = types.str;
        default = "mysqlbackup";
      };

      dbs = mkOption {
        default = [];
        description = "Databases to backup (list)";
      };
    };
  };

  config = mkIf (mcfg.enable) {

    users.users.${mcfg.user} = mkIf (mcfg.user != config.services.mysql.user) {
      isSystemUser = true;
      createHome = false;
      home = mcfg.dir;
      group = "nogroup";
    };

    services.mysql.ensureUsers = [{
      name = mcfg.user;
      ensurePermissions = with lib;
        let
          privs = "select, show view, trigger, lock tables";
          grant = db: nameValuePair "${db}.*" privs;
        in
          listToAttrs (map grant mcfg.dbs);
    }];

    systemd = {
      timers.mymysqlbackup = {
        description = "mysql backup";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = mcfg.calendar;
          AccuracySec = "5m";
          Unit = "mymysqlbackup.service";
        };
      };

      tmpfiles.rules = [
        "d ${mcfg.dir} 0750 ${mcfg.user} ${config.services.mysql.group} - -"
      ];

      services.mymysqlbackup = {
        description = "Service to back up mysql DBs for restoration if NixOS gets rebuilt";
        enable = true;
        environment = let
          mysql = pkgs.mysql;
        in {
          ODIR = mcfg.dir;
          DBS = concatStringsSep "," mcfg.dbs;
          MYSQLDUMP_PATH = "${mysql}/bin/mysqldump";
        };
        unitConfig = {
          DefaultDependencies = "no";
        };
        serviceConfig = {
          Type = "oneshot";
          User = mcfg.user;
          ExecStart = let
            python = pkgs.python3;
            backup_script = ./backup.py;
          in
            "${python.interpreter} ${backup_script}";
        };
        wantedBy = [ "shutdown.target" ];
        before = [ "shutdown.target" ];
      };
    };
  };

}

