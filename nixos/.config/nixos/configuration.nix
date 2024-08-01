# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ inputs, config, pkgs, system, ... }:
let
overlays = import ./overlays.nix;


# Custom scripts


in 

{
nixpkgs.config.allowUnfree = true;
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      inputs.home-manager.nixosModules.home-manager
      inputs.nix-colors.homeManagerModules.default

    ];

    home-manager = {
    backupFileExtension = "backup";
      extraSpecialArgs = {
        inherit inputs;
      };
      users = {
        matth = import ./home-manager/home.nix;
      };
      
      # services = {
      #   activitywatch = {
      #     enable = true;
      #     };
      #
      #   };
          

          };
    boot.initrd.kernelModules = [ "amdgpu" ];
    programs.nix-ld.enable = true;
    programs.nix-ld.libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib 
    ];

  # nixpkgs.overlays = [ overlays ];

# users.users.eve.isNormalUser = true;
# home-manager.users.eve = { pkgs, ... }: {
#   home.packages = [ pkgs.atool pkgs.httpie ];
#   programs.bash.enable = true;
#
#   # The state version is required and should stay at the version you
#   # originally installed.
#   home.stateVersion = "23.11";

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
# software dev essentials

# (import ./home-manager/source-nix-files-after-cd.nix {inherit pkgs; })

pkgs.python311
bat
chromedriver
  # wireplumber
  wget
git
nodePackages.npm
nodejs_22

# hardware stuff

ntfs3g
pika-backup
helvetica-neue-lt-std
# terminal stuff
neovim
alacritty
stow
fish
oh-my-fish
tmux
lsd
zoxide
fzf
thefuck
yazi
btop
hyprshade
grimblast
### data collection stuff
aw-watcher-afk
aw-watcher-window
activitywatch
nix-index

### user stuff
# code
zoom
# cura
syncthing
obs-studio
libreoffice
brave
gimp
discord
slack
# mailspring
thunderbird
nautilus
slack
anki
obsidian
zathura
neomutt
feh
texliveFull
qgroundcontrol

### hpyrland window manager
wlroots
wl-gammactl
# (stablePkgs.wireplumber)
# stablePkgs.waybar
# redshift-wayland
waybar
gammastep
swww
rofi-wayland
networkmanagerapplet
mako
hyprpicker
# hyprlock
# hyprcursor
# xdg-desktop-portal-hyprland
#libsForQt5.qt5.qt5wayland
qt6.qtwayland
pamixer
brightnessctl
dunst
swaylock
# bluez
# blueman
# bluez-tools
pavucontrol
wl-clipboard
jq
swappy
slurp
wlogout
cliphist
libnotify
mono

parallel
imagemagick
ffmpegthumbs
kde-cli-tools
polkit-kde-agent
nwg-look
qt6Packages.qtstyleplugin-kvantum
starship
envsubst
wlr-randr
# 
ddcutil
killall
libsForQt5.qtstyleplugin-kvantum
powertop
zip
unzip

libstdcxx5


####  CODING
 # c compiler
 gcc
 clang
 glib
 glibc
 gdb
 valgrind
 cmake
libxcrypt
clang-tools
nss
postgresql
libpqxx



stylua
# nodePackages.pyright
vimPlugins.nvchad
vimPlugins.nvchad-ui



gnumake42
glibcLocales
gh

 # rust
cargo


# virtual machine
openconnect_openssl


 # sort later
# stablePkgs.stack
# stablePkgs.haskellPackages.ghc
# stablePkgs.haskellPackages.ghcup
# ghc
# haskell.compiler.ghc942
# haskellPackages.ghcWithPackages 

neofetch
morgen
ripgrep
# python packages

      # python-pkgs.pandas
      # python-pkgs.requests
      # python-pkgs.torch
      # python-pkgs.matplotlib
      # python-pkgs.pillow
      # python-pkgs.torchvision
      # python-pkgs.scikit-image
      # python-pkgs.scipy
      # python-pkgs.numpy

jupyter



ninja

  ];
  security.pam.services.swaylock = {};
# programs.neovim = {
#   enable = true;
#   configure = {
#     packages.myVimPackage = with pkgs.vimPlugins; [ 
#       # Add your desired plugins here
#       vim-nix
#       pynvim
#     ];
#     customRC = ''
#       let g:python3_host_prog = "${pkgs.python3}/bin/python"
#     '';
#   };
# };

    nixpkgs.config.permittedInsecurePackages = [
      "electron-25.9.0"
    ];

  nixpkgs.config.allowBroken = true; 
   
services.dbus.packages = [
  pkgs.dbus.out
  config.system.path
];


############################## POWER MANAGEMENT ############################## 
############################## POWER MANAGEMENT ############################## 
############################## POWER MANAGEMENT ############################## 
############################## POWER MANAGEMENT ############################## 
############################## POWER MANAGEMENT ############################## 
############################## POWER MANAGEMENT ############################## 

services.tlp = {
      enable = true;
      settings = {
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

        CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

        CPU_MIN_PERF_ON_AC = 0;
        CPU_MAX_PERF_ON_AC = 100;
        CPU_MIN_PERF_ON_BAT = 0;
        CPU_MAX_PERF_ON_BAT = 20;

       #Optional helps save long term battery health
       START_CHARGE_THRESH_BAT0 = 40; # 40 and bellow it starts to charge
       STOP_CHARGE_THRESH_BAT0 = 80; # 80 and above it stops charging


      USB_AUTOSUSPEND = 0;
      RESTORE_DEVICE_STATE_ON_STARTUP = 1;

      };
};
  # services.auto-cpufreq.enable = true;
  # services.auto-cpufreq.settings = {
  #   battery = {
  #      governor = "powersave";
  #      turbo = "never";
  #   };
  #   charger = {
  #      governor = "performance";
  #      turbo = "auto";
  #   };
  # };


  boot.kernelParams = [ "usbcore.autosuspend=-1" ];

  services.power-profiles-daemon.enable = false;
  powerManagement.powertop.enable = true;



############################## STUFF I HAVEN'T TOUCHED ############################## 
############################## STUFF I HAVEN'T TOUCHED ############################## 
############################## STUFF I HAVEN'T TOUCHED ############################## 
############################## STUFF I HAVEN'T TOUCHED ############################## 
############################## STUFF I HAVEN'T TOUCHED ############################## 

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader = {

    timeout = 1;
  };
  services.blueman.enable = true;
  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://ubser:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";
  hardware.pulseaudio.enable = false;

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
services.xserver.enable = true;
# services.xserver.desktopManager.gnome.enable = true;
services.displayManager.sddm.enable = true;
  #services.xserver.displayManager.sddm.settings = {
	#Autologin = {
	#Session = "hyprland.desktop";
	#User = "matth";
	#};
#
  #};
#  services.xserver.displayManager.session = "hyprland.desktop";

  services.xserver.desktopManager.gnome.enable = true;
  #services.xserver.desktopManager.plasma5.enable = true;

services.xserver = {
  xkb.layout = "us,ru";  # Change "us" to your default layout if different
  xkb.options = "grp:alt_shift_toggle";  # This allows switching between layouts using Alt+Shift
};

  # Enable CUPS to print documents.
  services.printing.enable = true;


  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput = {
    enable = true;
    touchpad.naturalScrolling = false;
  };
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.matth = {
    isNormalUser = true;
    description = "Matt Handzel";
    extraGroups = [ "networkmanager" "wheel" "adbusers"];
    packages = with pkgs; [
      firefox
      kate
    #  thunderbird
    ];
  shell = pkgs.fish;
  };
  


  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = false;
  services.displayManager.autoLogin.user = "matth";

 services.fprintd.enable = true; 
services.fprintd.tod.enable = true;
services.fprintd.tod.driver = pkgs.libfprint-2-tod1-goodix;
  

  
xdg.portal.enable = true;
# xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

security.rtkit.enable = true;
services.pipewire = {
  enable = true;
  alsa.enable = true;
  alsa.support32Bit = true;
  pulse.enable = true;
  jack.enable = true;
};

programs.fish = {
	enable = true;

};
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };
programs.hyprland = {
  enable = true;
  xwayland.enable = true;
};

environment.sessionVariables = {
#  If your cursor becomes invisible
  WLR_NO_HARDWARE_CURSORS = "1";
  # Hint electron apps to use wayland
  NIXOS_OZONE_WL = "1";
};

hardware = {
   # Opengl
    graphics.enable = true;

   # Most wayland compositors need this
    nvidia.modesetting.enable = true;
};


  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?

# Emojis!
  i18n.inputMethod = {
      enable = true;
      type = "ibus";
      ibus.engines = with pkgs.ibus-engines; [ /* any engine you want, for example */ anthy ];
    };
nix.settings.experimental-features = [ "nix-command" "flakes"];


# Make some commands not need to take sudo
security.sudo.wheelNeedsPassword = false; # This allows users in the 'wheel' group to run any command with sudo without a password.
  
  security.sudo.extraRules = [
    {
      users = [ "matth" ]; # Replace with your actual username
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-rebuild"; 
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];


}
