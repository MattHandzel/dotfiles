{pkgs, ...}: let
  # Keeps BLE keyboards (TOTEM, Corne) actually usable across suspend/resume.
  #
  # The trap this exists to escape: after resume BlueZ routinely holds a
  # HALF-DEAD LE link. It reports `Connected: yes`, but the link never gets
  # encrypted, so every GATT read against the HID service fails ("unlikely
  # error" from hog-lib) and **no /dev/input node is ever created**. The
  # keyboard is silently dead while bluetoothctl swears it is connected. The
  # previous version of this script trusted `Connected: yes` and skipped such
  # devices, which is precisely why the keyboard never came back.
  #
  # So the only honest success signal is: does an HID input node exist for this
  # device? Everything below is driven off that, escalating as needed. A plain
  # disconnect/reconnect is often NOT enough — BlueZ wedges the pending connect
  # with org.bluez.Error.InProgress and only a bluetoothd restart clears it.
  btKeyboardReconnect = pkgs.writeShellScript "bt-keyboard-reconnect" ''
    export PATH=${pkgs.bluez}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:${pkgs.gawk}/bin:${pkgs.systemd}/bin:${pkgs.coreutils}/bin:$PATH

    # BlueZ names the HID node "<device name> Keyboard". Its presence means the
    # HoG profile actually attached, i.e. the keyboard can really type.
    has_input_node() { grep -qi "Name=\"$1" /proc/bus/input/devices; }

    wait_powered() {
      for _ in $(seq 1 15); do
        bluetoothctl show | grep -q "Powered: yes" && return 0
        sleep 1
      done
      return 1
    }

    settle() { # give BlueZ time to attach HoG and create the node
      for _ in $(seq 1 6); do
        has_input_node "$1" && return 0
        sleep 2
      done
      return 1
    }

    # Restarting bluetoothd drops every BT device (headphones included), so it
    # is a last resort, and rate-limited so a permanently-absent keyboard can
    # never put us in a restart loop.
    RESTART_STAMP=/run/bt-keyboard-reconnect.last-restart
    may_restart_bluetoothd() {
      local now last
      now=$(date +%s)
      last=$(cat "$RESTART_STAMP" 2>/dev/null || echo 0)
      [ $((now - last)) -lt 300 ] && return 1
      echo "$now" > "$RESTART_STAMP"
      return 0
    }

    wait_powered || { echo "adapter never powered on"; exit 0; }

    for mac in $(bluetoothctl devices Paired | awk '{print $2}'); do
      info=$(bluetoothctl info "$mac" </dev/null)
      echo "$info" | grep -q "Icon: input-keyboard" || continue
      name=$(echo "$info" | sed -n 's/^[[:space:]]*Name: //p')

      if has_input_node "$name"; then
        echo "ok: $name is attached and usable"
        continue
      fi

      # Connected-but-no-input-node is the pathological state; a device that is
      # simply away/off is not, and must not be touched AT ALL. Chasing an
      # absent BLE keyboard with disconnect/connect every 2 minutes (measured:
      # 1750 attempts, 0 recoveries in the week to 2026-08-31) keeps the radio
      # in an LE create-connection loop — the same contention class as the
      # ReconnectAttempts paging bug below — and fights BlueZ's own passive
      # reconnect arming (bonded+trusted devices sit in the kernel LE accept
      # list; the KEYBOARD initiates reconnection by advertising, the host only
      # needs to listen). Absent device ⇒ hands off, let the accept list work.
      was_connected=no
      echo "$info" | grep -q "Connected: yes" && was_connected=yes
      if [ "$was_connected" = no ]; then
        echo "absent: $name is not connected (leaving reconnection to the LE accept list)"
        continue
      fi
      echo "$name ($mac): connected but no HID input node — repairing"

      wedged=no
      for _ in 1 2; do
        bluetoothctl disconnect "$mac" </dev/null >/dev/null 2>&1 || true
        sleep 2
        out=$(bluetoothctl connect "$mac" </dev/null 2>&1 || true)
        echo "$out" | grep -q "InProgress" && wedged=yes
        settle "$name" && break
      done

      if has_input_node "$name"; then
        echo "recovered: $name"
        continue
      fi

      # Only a wedged BlueZ, or a link it insists is connected while dead,
      # justifies restarting the daemon. An absent keyboard just gives up.
      if { [ "$wedged" = yes ] || [ "$was_connected" = yes ]; } && may_restart_bluetoothd; then
        echo "BlueZ is wedged; restarting bluetoothd to clear it"
        systemctl restart bluetooth
        wait_powered
        for _ in $(seq 1 10); do
          has_input_node "$name" && break
          bluetoothctl connect "$mac" </dev/null >/dev/null 2>&1 || true
          sleep 3
        done
      fi

      if has_input_node "$name"; then
        echo "recovered: $name"
      else
        echo "FAILED to bring up $name (asleep, out of range, or flat battery?)"
      fi
    done
  '';

  # Make autoconnect work "forever": BlueZ only auto-accepts an incoming page
  # from a device marked `Trusted: yes` (and with Policy.ReconnectAttempts=0 the
  # host won't chase anything itself), so an UNtrusted paired headset only ever
  # connects via a manual `bluetoothctl connect`. Trust state is imperative
  # pairing data in /var/lib/bluetooth and can't be expressed declaratively —
  # so instead we declaratively guarantee that every paired device becomes
  # trusted. Any device Matt ever pairs is auto-trusted within one timer tick;
  # nothing manual is ever required again.
  btTrustPaired = pkgs.writeShellScript "bt-trust-paired" ''
    export PATH=${pkgs.bluez}/bin:${pkgs.gawk}/bin:${pkgs.gnugrep}/bin:${pkgs.coreutils}/bin:$PATH
    for mac in $(bluetoothctl devices Paired | awk '{print $2}'); do
      bluetoothctl info "$mac" </dev/null 2>/dev/null | grep -q "Trusted: yes" && continue
      bluetoothctl trust "$mac" </dev/null >/dev/null 2>&1 || true
      echo "auto-trusted $mac"
    done
  '';
  # Low-battery warning for BLE keyboards. A flat TOTEM radiates NOTHING — it
  # presents as "Bluetooth is broken" (2026-08-31: 19 days of dead silence were
  # a dead battery, not pairing). The keyboard reports charge over the BLE
  # Battery Service, so warn while it can still speak. At most one notification
  # per device per 6h.
  btKeyboardBatteryWarn = pkgs.writeShellScript "bt-keyboard-battery-warn" ''
    export PATH=${pkgs.bluez}/bin:${pkgs.libnotify}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:${pkgs.gawk}/bin:${pkgs.coreutils}/bin:$PATH
    for mac in $(bluetoothctl devices Paired | awk '{print $2}'); do
      info=$(bluetoothctl info "$mac" </dev/null 2>/dev/null)
      echo "$info" | grep -q "Icon: input-keyboard" || continue
      echo "$info" | grep -q "Connected: yes" || continue
      pct=$(echo "$info" | sed -n 's/.*Battery Percentage:.*(\([0-9]*\)).*/\1/p')
      [ -n "$pct" ] || continue
      [ "$pct" -le 15 ] || continue
      name=$(echo "$info" | sed -n 's/^[[:space:]]*Name: //p')
      stamp="''${XDG_RUNTIME_DIR:-/tmp}/bt-battery-warned-''${mac//:/_}"
      now=$(date +%s); last=$(cat "$stamp" 2>/dev/null || echo 0)
      [ $((now - last)) -lt 21600 ] && continue
      echo "$now" > "$stamp"
      notify-send -u normal "🪫 $name battery at $pct%" \
        "Charge it soon — a flat board looks like broken Bluetooth."
    done
  '';
  # The audio twin of the keyboard wedge above (diagnosed 2026-08-13, EarFun
  # Air Pro 4): dual-mode earbuds reconnect after suspend/resume with only the
  # LE bearer up (Fast Pair / battery / vendor GATT). BlueZ reports
  # `Connected: yes`, but no A2DP transport exists, so PipeWire never creates a
  # bluez_output sink and the buds are silent. A plain
  # `bluetoothctl disconnect+connect` just reuses the LE bearer; the only thing
  # that repairs it is ConnectProfile on the A2DP Audio Sink UUID, which forces
  # the BR/EDR audio link up.
  #
  # As with the keyboards, the honest success signal is NOT `Connected: yes` —
  # it is "a bluez_output node exists in PipeWire for this device".
  btAudioTransportWatchdog = pkgs.writeShellScript "bt-audio-transport-watchdog" ''
    export PATH=${pkgs.bluez}/bin:${pkgs.pipewire}/bin:${pkgs.systemd}/bin:${pkgs.gnugrep}/bin:${pkgs.gawk}/bin:${pkgs.coreutils}/bin:$PATH

    A2DP_SINK_UUID=0000110b-0000-1000-8000-00805f9b34fb

    # No PipeWire session (logged out, pipewire restarting) — nothing to judge.
    pw-cli info 0 >/dev/null 2>&1 || exit 0

    has_sink() { pw-cli ls Node 2>/dev/null | grep -q "bluez_output.$1"; }

    for mac in $(bluetoothctl devices Connected </dev/null | awk '{print $2}'); do
      info=$(bluetoothctl info "$mac" </dev/null)
      echo "$info" | grep -q "UUID: Audio Sink" || continue
      name=$(echo "$info" | sed -n 's/^[[:space:]]*Name: //p')
      macu=''${mac//:/_}

      has_sink "$macu" && continue

      # Grace period: a device that connected seconds ago may still be mid
      # profile setup. Only intervene if the sink stays absent.
      sleep 5
      has_sink "$macu" && continue

      echo "$name ($mac): connected but no PipeWire sink — forcing A2DP up"
      busctl call org.bluez "/org/bluez/hci0/dev_$macu" \
        org.bluez.Device1 ConnectProfile s "$A2DP_SINK_UUID" 2>&1 || true

      for _ in $(seq 1 5); do
        sleep 2
        if has_sink "$macu"; then
          echo "recovered: $name has an audio sink"
          continue 2
        fi
      done
      echo "FAILED to bring up A2DP for $name (will retry next tick)"
    done
  '';
in {
  services.blueman = {
    enable = true;
  };

  # Repair audio devices that connect LE-only (see script comment above). Runs
  # in the user session because the success signal lives in the user's
  # PipeWire; BlueZ D-Bus calls work fine from there.
  systemd.user.services.bt-audio-transport-watchdog = {
    description = "Force A2DP up for BT audio devices stuck on an LE-only link";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${btAudioTransportWatchdog}";
    };
  };

  # Warn before a BLE keyboard's battery dies silently (see script comment).
  # User session because notify-send needs the session bus.
  systemd.user.services.bt-keyboard-battery-warn = {
    description = "Warn when a connected BLE keyboard is low on battery";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${btKeyboardBatteryWarn}";
    };
  };

  systemd.user.timers.bt-keyboard-battery-warn = {
    description = "Periodically check BLE keyboard battery levels";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnStartupSec = "3min";
      OnUnitActiveSec = "30min";
      Unit = "bt-keyboard-battery-warn.service";
    };
  };

  systemd.user.timers.bt-audio-transport-watchdog = {
    description = "Periodically verify connected BT audio devices have a sink";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnStartupSec = "1min";
      OnUnitActiveSec = "1min";
      Unit = "bt-audio-transport-watchdog.service";
    };
  };

  # Reconnect Bluetooth keyboards after resume (see script comment above).
  systemd.services.bt-keyboard-reconnect = {
    description = "Reconnect Bluetooth keyboards after resume";
    wantedBy = ["post-resume.target"];
    after = ["post-resume.target" "bluetooth.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${btKeyboardReconnect}";
    };
  };

  # The half-dead-link wedge is not exclusive to resume (a BT dropout can leave
  # the same connected-but-no-input-node state), and the script is a no-op when
  # every keyboard is healthy, so it is cheap to just keep checking.
  systemd.timers.bt-keyboard-reconnect = {
    description = "Periodically verify BLE keyboards are actually usable";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "2min";
      Unit = "bt-keyboard-reconnect.service";
    };
  };

  # Auto-trust every paired device so it will autoconnect (see script comment).
  systemd.services.bt-trust-paired = {
    description = "Trust all paired Bluetooth devices so they autoconnect";
    after = ["bluetooth.service"];
    wants = ["bluetooth.service"];
    wantedBy = ["bluetooth.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${btTrustPaired}";
    };
  };

  # Catch devices paired after boot (a fresh pairing) without any manual step.
  systemd.timers.bt-trust-paired = {
    description = "Periodically trust newly paired Bluetooth devices";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "3min";
      Unit = "bt-trust-paired.service";
    };
  };

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Auto-connect trusted devices on boot/resume. NOTE: do NOT set
  # `Experimental = true` here — it enables BlueZ LE Audio, which makes the
  # EarFun buds connect over LE (no A2DP transport ⇒ no PipeWire sink ⇒
  # "connected but silent"). Keeping it off makes classic A2DP the norm, but
  # does NOT guarantee it: the buds can still reconnect LE-only after resume
  # (seen 2026-08-13); bt-audio-transport-watchdog repairs that case.
  hardware.bluetooth.settings = {
    General = {
      FastConnectable = true;
      JustWorksRepairing = "always";
    };
    Policy = {
      AutoEnable = true;

      # THIS is what kept killing the TOTEM (diagnosed 2026-07-14). BlueZ's
      # policy plugin re-pages trusted-but-absent audio devices forever — the
      # Mentra glasses and three sets of headphones were being paged every 60s,
      # each logging "Host is down". A BR/EDR page against a device that is
      # simply switched off monopolises the radio for seconds at a time, and the
      # TOTEM's LE supervision timeout is only 4s, so the keyboard's link
      # starved and dropped every ~44s — connected, then dead, forever.
      #
      # Measured: 6 keyboard drops / 5 min with this on, 0 with it off.
      #
      # Setting this to 0 only stops the HOST from chasing devices that aren't
      # there. Headphones still auto-connect normally, because they page the
      # host themselves when powered on — so nothing is lost by not hunting for
      # hardware that is off.
      #
      # CAVEAT: auto-connect only works for devices marked `Trusted: yes` — BlueZ
      # will not auto-accept an incoming page from an untrusted device, so with
      # ReconnectAttempts=0 an untrusted headset only ever connects via a manual
      # `bluetoothctl connect`. Trust state lives in /var/lib/bluetooth (imperative,
      # not expressible here); trust a headset once with `bluetoothctl trust <mac>`.
      ReconnectAttempts = 0;
    };
  };

  # adding headset button controls
  systemd.user.services.mpris-proxy = {
    description = "Mpris proxy";
    after = ["network.target" "sound.target"];
    wantedBy = ["default.target"];
    serviceConfig.ExecStart = "${pkgs.bluez}/bin/mpris-proxy";
  };

  # systemd.user.services.my-user-task = {
  #   enable = true;
  #   description = "My daily task notification";
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "notify-send -t 2000 -u normal -i dialog-information \"Daily task 📅!\" \"\"";
  #   };
  #   wantedBy = ["default.target"];
  # };

  systemd.user.timers.my-user-task = {
    enable = true;
    description = "Run my daily task";
    timerConfig = {
      OnCalendar = "13:47";
      Unit = "my-user-task.service";
    };
    wantedBy = ["timers.target"];
  };
}
