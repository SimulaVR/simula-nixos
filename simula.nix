# ▄▀▀ ▀ █▄░▄█ █░█ █░░ ▄▀▄ ▐▌░▐▌ █▀▀▄     █▄░█ ▀ █░█ ▄▀▄ ▄▀▀     ▄▀ ▄▀▄ █▄░█ █▀ ▀ ▄▀▀░ 
# ░▀▄ █ █░█░█ █░█ █░▄ █▀█ ░▀▄▀░ █▐█▀     █░▀█ █ ▄▀▄ █░█ ░▀▄     █░ █░█ █░▀█ █▀ █ █░▀▌ 
# ▀▀░ ▀ ▀░░░▀ ░▀░ ▀▀▀ ▀░▀ ░░▀░░ ▀░▀▀     ▀░░▀ ▀ ▀░▀ ░▀░ ▀▀░     ░▀ ░▀░ ▀░░▀ ▀░ ▀ ▀▀▀░ 

# NixOS settings for the upcoming Simula One (https://simulavr.com)
{ config, pkgs, lib, ... }:

let
  # Fetch Simula source code from GitHub
  simulaSrc = pkgs.fetchFromGitHub {
    owner = "SimulaVR";
    repo = "Simula";
    rev = "f1690c513b33d8238f213de944f44c273ec0c513";
    sha256 = "1kcyak663lnyqfy6s8ym1ybm7kwslw9vy9ddqzjnx125bi31rb63";
    fetchSubmodules = true;
  };

  # Build the Simula package
  simula = pkgs.callPackage "${simulaSrc}/Simula.nix" {
    onNixOS = true;
    devBuild = false;
    profileBuild = false;
    externalSrc = simulaSrc;
  };
in
{
  # Provides necessary packages for interacting with Simula launch script
  environment.systemPackages = with pkgs; [
     simula
     xorg.xrandr
     read-edid
  ];

  # Ensures that tracking devices can set their own priority
  security.wrappers = {
    simula-monado-service = {
      source = "${simula}/bin/simula-monado-service";
      capabilities = "cap_sys_nice+ep";
      owner = "simula";
      group = "users";
    };
  };

  # Add the 'simula' user and grant appropriate permissions
  nix.settings.trusted-users = [ "root" "simula" ];

  users.extraUsers.simula = {
    isNormalUser = true;
    home = "/home/simula";
    extraGroups = [ "wheel" "networkmanager" "video" "tty" ];
  };

  # Include udev rules for Simula tracking devices (just the Xvisio XR50 for now)
  services.udev.extraRules = ''
    # XVISIO SEERSENSE XR50 RULES
    SUBSYSTEM=="usb", ATTR{idVendor}=="040e", MODE="0666", GROUP="plugdev"
  '';

  # Provides optical transforms for Simula One optics
  environment.etc."simula/simula_monado_config.json".text = ''
    {
      "display_distortion": {
        "left_eye": {
          "half_fov": 0.9,
          "display_size_mm_x": 51.7752,
          "display_size_mm_y": 51.7752,
          "params_red": {
            "k1": 0.022474564980657766,
            "k3": 6.426774232E-6,
            "k5": 1.557249471935154E-8,
            "k7": 3.456308599003131E-11,
            "k9": -3.9098738307993384E-15
          },
          "params_green": {
            "k1": 0.022474564980657766,
            "k3": 7.140860258225189E-6,
            "k5": 1.557249471935154E-8,
            "k7": 3.456308599003131E-11,
            "k9": -3.9098738307993384E-15
          },
          "params_blue": {
            "k1": 0.022474564980657766,
            "k3": 7.934289176E-6,
            "k5": 1.557249471935154E-8,
            "k7": 3.456308599003131E-11,
            "k9": -3.9098738307993384E-15
          }
        },
        "right_eye": {
          "half_fov": 0.9,
          "display_size_mm_x": 51.7752,
          "display_size_mm_y": 51.7752,
          "params_red": {
            "k1": 0.022474564980657766,
            "k3": 6.426774232E-6,
            "k5": 1.557249471935154E-8,
            "k7": 3.456308599003131E-11,
            "k9": -3.9098738307993384E-15
          },
          "params_green": {
            "k1": 0.022474564980657766,
            "k3": 7.140860258225189E-6,
            "k5": 1.557249471935154E-8,
            "k7": 3.456308599003131E-11,
            "k9": -3.9098738307993384E-15
          },
          "params_blue": {
            "k1": 0.022474564980657766,
            "k3": 7.934289176E-6,
            "k5": 1.557249471935154E-8,
            "k7": 3.456308599003131E-11,
            "k9": -3.9098738307993384E-15
          }
        }
      }
    }
  '';

  # Launch monado + Simula's VR window manager on boot
  services.xserver = {
    enable = true;
    autorun = true;
    displayManager.lightdm.enable = false;
    displayManager.startx.enable = false;
    displayManager.autoLogin.enable = true;
    displayManager.autoLogin.user = "simula";
    displayManager.defaultSession = "simula-session";
    desktopManager.session = [
      {
        name = "simula-session";
        start = ''
          #!${pkgs.bash}/bin/bash

          # Set up logging
          exec >~/.xsession-errors 2>&1

          cd ~

          echo "Checking for Simula One VR displays..."
          checkForDisplays() {
            local found_displays=()
            local exit_code=0

            # Load up the `found_displays` array with any detected displays
            for output in /sys/class/drm/*/status; do
              if grep -q "^connected$" "$output"; then
                display_name="''${output%/status}"
                display_name="''${display_name#/sys/class/drm/}"
                found_displays+=("$display_name")

                edid_file="''${output%status}edid"
                if [ -f "$edid_file" ]; then
                  edid_model=$(${pkgs.read-edid}/bin/parse-edid < "$edid_file" 2> /dev/null | sed -n 's/.*VendorName *"\(.*\)".*/\1/p')
                  if [ -n "$edid_model" ]; then
                    found_displays+=("$edid_model")
                  fi
                fi
              fi
            done

            if [ $# -eq 0 ]; then
              echo "Found displays:"
              for display in "''${found_displays[@]}"; do
                echo "  - $display"
              done
              return 0
            fi

            if [[ " ''${found_displays[*]} " == *" $1 "* ]]; then
              echo "$1 display found."
            else
              echo "ERROR: $1 monitor not connected or found."
              exit_code=1
            fi

            return $exit_code
          }

          # List available displays, and check if Simula's VR displays are detected
          checkForDisplays
          checkForDisplays "SVR"

          echo "Setting xrandr modes for Simula One displays..."
          ${pkgs.xorg.xrandr}/bin/xrandr --newmode 1280x720_60.00 74.48 1280 1336 1472 1664 720 721 724 746 -HSync +Vsync
          ${pkgs.xorg.xrandr}/bin/xrandr --addmode DVI-I-1-1 1280x720_60.00
          ${pkgs.xorg.xrandr}/bin/xrandr --output DVI-I-1-1 --mode 1280x720_60.00
          ${pkgs.xorg.xrandr}/bin/xrandr --output DP-2 --off
          ${pkgs.xorg.xrandr}/bin/xrandr --output DP-1 --off

          echo "Launching Monado..."
          rm /run/user/$(id -u)/monado_comp_ipc || true
          XRT_NO_STDIN=1 ${simula}/bin/simula-monado-service &

          echo "Waiting for Monado to be ready..."
          until [ -e /run/user/$(id -u)/monado_comp_ipc ]; do sleep 0.1; done

          echo "Launching Simula..."
          exec ${simula}/bin/simula
        '';
      }
    ];
  };
}
