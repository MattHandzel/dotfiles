# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
# software dev essentials
  wget
git
nodePackages.npm
nodejs_21

# hardware stuff

ntfs3g
pika-backup

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

### user stuff
# code
brave
gimp
discord
slack
# mailspring
thunderbird
gnome.nautilus
slack
spotify
anki
obsidian
zathura
neomutt


### hpyrland window manager
waybar
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
bluez
blueman
bluez-tools
python3
pavucontrol
wl-clipboard
jq
swappy
slurp
wlogout
cliphist
libnotify

parallel
imagemagick
ffmpegthumbs
kde-cli-tools
polkit-kde-agent
nwg-look
qt6Packages.qtstyleplugin-kvantum
starship
envsubst
# 
ddcutil
killall
libsForQt5.qtstyleplugin-kvantum

unzip

 # c compiler
 gcc
 clang
 glib
 gdb
 valgrind
 cmake

gnumake42


   # rust
  cargo



 # sort later
neofetch
python311Packages.pip
    rustup # rustup

  ];
              nixpkgs.config.permittedInsecurePackages = [
                "electron-25.9.0"
              ];


  #services.gnome3.enable = true;

  hardware.bluetooth.enable = true;
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
boot.loader = {

timeout = 1;
};
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
services.xserver.displayManager.sddm.enable = true;
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

  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;


  # Enable touchpad support (enabled default in most desktopManager).
  services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.matth = {
    isNormalUser = true;
    description = "Matt Handzel";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      firefox
      kate
    #  thunderbird
    ];
 #  shell = pkgs.fish;
  };

  # Enable automatic login for the user.
  services.xserver.displayManager.autoLogin.enable = false;
  services.xserver.displayManager.autoLogin.user = "matth";

 services.fprintd.enable = true; 
services.fprintd.tod.enable = true;
services.fprintd.tod.driver = pkgs.libfprint-2-tod1-goodix;
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  
xdg.portal.enable = true;
# xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

sound.enable = true;
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
  enableNvidiaPatches = true;
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
    opengl.enable = true;

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

nix.settings.experimental-features = [ "nix-command" "flakes"];

}
