# nix-darwin module: Dia auto-installs Matt's extensions through Chromium's ExtensionSettings policy.
# (Was arc-policy.nix for ~2 hours on 2026-09-12; Matt switched the target browser from Arc to Dia.)
# Chromium only honours install policies at MANDATORY level, which on macOS means the plist must live
# in /Library/Managed Preferences (root-owned) - a user-level `defaults write` is silently ignored.
# nix-darwin activation runs as root, so this rides along with Matt's normal `rebuild`.
# installation_mode "normal_installed" = installed automatically but Matt can still disable/remove.
# Dia says it supports "standard Chromium enterprise policies"; the managed-preferences domain is
# inferred from its bundle id and is verified at dia://policy after the rebuild. Drop this file into
# modules/darwin/ and import it from modules/darwin/default.nix.
{
  lib,
  pkgs,
  ...
}: let
  cws = "https://clients2.google.com/service/update2/crx";
  ids = {
    bitwarden = "nngceckbapebfimnlniiiahkandclblb";
    ublock-origin-lite = "ddkjiahejlhfcafbddmgiahcphecmpfh"; # full uBO is MV2, dead in Chromium
    vimium = "dbepggeogbaibhgnhhndojpepiihcmeb";
    sponsorblock = "mnjggcdmjocbbbhaepdhchncahnbgone";
    video-speed-controller = "nffaoalbilbmmfgbnbgppjihopabppdk";
    grammarly = "kbfnbcaeplbcioakkpcpgfkobkghlhen";
    news-feed-eradicator = "fjcldmjmjhkklehbacihaiopjklihlgg";
    unhook = "khncfooichmfjbepaaaebmommgaepoid";
    whatfont = "jabopobgcpjmedljpbcaablpmlmfcogm";
    google-dictionary = "mgijmajocgfcbeboacabfgobmjgjcoja"; # Dictionary Anywhere was delisted from the Chrome Web Store (2026-09-13)
    skip-silence = "fhdmkhbefcbhakffdihhceaklaigdllh";
    video-downloadhelper = "lmjnegcaeklhafolokijcfjliaokphfk"; # cannot download YouTube on Chromium
    get-cookies-txt-locally = "cclelndahbckbenkjhflpdbgdldlbecc";
    curius = "fbpnbdifockifjiimogdjndhpmmfgjkl";
    phantombuster = "mdlnjfcpdiaclglfbdkbleiamdafilil";
    simplify-copilot = "pbanhockgagggenencehbnadejlgchfc";
    youtube-summary-glasp = "nmmicjeknamkfloonkhhcjmomieiodli";
    recall = "ldbooahljamnocpaahaidnmlgfklbben";
    duckduckgo = "bkdgflcldnnnapblkhphbgpggdiikppg";
  };
  settings = lib.mapAttrs' (_: id:
    lib.nameValuePair id {
      installation_mode = "normal_installed";
      update_url = cws;
    })
  ids;
  # Default search engine = DuckDuckGo, as it was in Zen. Writing
  # default_search_provider_data into Preferences was discarded by Dia on
  # its next start (2026-09-12), so the engine is set by policy instead,
  # which Chromium applies on every launch.
  #
  # 2026-09-15: these keys used to live in the MANDATORY plist below, which
  # locked the engine — the picker in Dia's settings was greyed out as
  # "managed". That afternoon the upstream network started blackholing
  # 52.250.42.0/24, the prefix EVERY duckduckgo.com hostname resolves to from
  # here (duckduckgo.com, lite., html., start., noai., duck.com all ->
  # 52.250.42.157; TCP 80 and 443 both time out, while the same IP answers in
  # ~150 ms from DE/FR/PL/RU, and DDG's other endpoint 52.149.246.39 answers
  # 200 from this Mac). Every new-tab search errored and Matt could not switch
  # engines to get around it, so the browser looked broken.
  #
  # Chromium's macOS policy loader calls CFPreferencesAppValueIsForced(): a key
  # in /Library/Managed Preferences is FORCED (mandatory, locks the UI), the
  # same key in the user's own domain is not, and loads as RECOMMENDED. So the
  # DefaultSearchProvider* keys move to CustomUserPreferences: DuckDuckGo is
  # still the out-of-box default, and Matt can pick another engine in Settings
  # the moment one is unreachable. Keep them out of the mandatory plist.
  searchProvider = {
    DefaultSearchProviderEnabled = true;
    DefaultSearchProviderName = "DuckDuckGo";
    DefaultSearchProviderKeyword = "duckduckgo.com";
    DefaultSearchProviderSearchURL = "https://duckduckgo.com/?q={searchTerms}";
    DefaultSearchProviderSuggestURL = "https://duckduckgo.com/ac/?q={searchTerms}&type=list";
    DefaultSearchProviderIconURL = "https://duckduckgo.com/favicon.ico";
  };
  plist = pkgs.writeText "company.thebrowser.dia.plist" (lib.generators.toPlist {escape = true;} {
    # ExtensionSettings is mandatory-only by design: Chromium ignores install
    # modes at the recommended level, so this one stays in the managed plist.
    ExtensionSettings = settings;
  });
in {
  system.defaults.CustomUserPreferences."company.thebrowser.dia" = searchProvider;

  # postActivation, not a custom name: nix-darwin runs only its fixed hooks
  # (preActivation / extraActivation / postActivation); a custom-named
  # activationScripts entry is silently never executed (2026-09-12: the
  # 19:22 switch produced a system with no trace of this policy).
  system.activationScripts.postActivation.text = ''
    /bin/mkdir -p "/Library/Managed Preferences"
    /bin/cp ${plist} "/Library/Managed Preferences/company.thebrowser.dia.plist"
    /usr/sbin/chown root:wheel "/Library/Managed Preferences/company.thebrowser.dia.plist"
    /bin/chmod 644 "/Library/Managed Preferences/company.thebrowser.dia.plist"
    /usr/bin/killall cfprefsd 2>/dev/null || true
  '';
}
