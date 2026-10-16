# shellcheck shell=bash
# Desktop apps, Android Studio + SDK, Xcode.

APPS_PICKED=""; APPS_ASKED=""
q_apps() {
  [ -n "$APPS_ASKED" ] && return 0
  local labels=() pre="" a lbl
  for a in "${APPS[@]}"; do
    lbl=${a%%|*}; labels+=("$lbl")
    [ "${a##*|}" = 1 ] && pre="$pre${pre:+,}$lbl"
  done
  APPS_PICKED=$(choose_many "Desktop apps" "$pre" "${labels[@]}")
  APPS_ASKED=1
}

# mas_install <id> <label>  → 0 on success
mas_install() {
  local id=$1 label=$2
  have mas || brew_formula mas
  run "App Store: $label" mas install "$id" && return 0
  run "App Store (with sudo): $label" sudo mas install "$id" && return 0
  run "App Store (first download): $label" mas purchase "$id" && return 0
  return 1
}

step_apps() {
  q_apps
  local a lbl method id app rc=0
  for a in "${APPS[@]}"; do
    IFS='|' read -r lbl method id app _ <<<"$a"
    case "$APPS_PICKED" in *"$lbl"*) ;; *) continue ;; esac
    if [ -d "/Applications/$app.app" ] || [ -d "$HOME/Applications/$app.app" ]; then
      ok "$lbl already installed"; record_skip "$lbl (already installed)"; continue
    fi
    case "$method" in
      cask)
        if brew_cask "$id" "$app"; then record_ok "$lbl"; else record_fail "$lbl (brew cask $id)"; rc=1; fi ;;
      mas)
        if [ -n "${DRY_RUN:-}" ]; then info "(dry-run) would install $lbl from the App Store"; continue; fi
        if mas_install "$id" "$lbl"; then record_ok "$lbl"
        else
          open "macappstore://apps.apple.com/app/id$id" 2>/dev/null
          record_manual "$lbl — App Store page opened: https://apps.apple.com/app/id$id"
        fi ;;
      manual)
        record_manual "$lbl — $id" ;;
    esac
  done
  return $rc
}

# ── Android ──────────────────────────────────────────────────────────────────
ANDROID_STUDIO=""; ANDROID_SDK=""; ANDROID_EMULATOR=""; ANDROID_ASKED=""
q_android() {
  [ -n "$ANDROID_ASKED" ] && return 0
  ANDROID_ASKED=1
  if ! ask_yn "Install Android Studio?" y; then ANDROID_STUDIO=no; else ANDROID_STUDIO=yes; fi
  if ask_yn "Install the Android SDK (platform-tools, build-tools, API levels — you pick the versions later) + JDK 17?" y; then
    ANDROID_SDK=yes
    ask_yn "Also create an Android emulator (AVD) for the newest API level you pick?" n && ANDROID_EMULATOR=yes
  fi
}

android_java_home() {
  /usr/libexec/java_home -v 17 2>/dev/null && return
  [ -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ] && echo "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
}

step_android() {
  q_android
  local rc=0
  if [ "$ANDROID_STUDIO" = yes ]; then
    if brew_cask android-studio "Android Studio"; then record_ok "Android Studio"; else record_fail "Android Studio"; rc=1; fi
  fi
  if [ "$ANDROID_SDK" != yes ]; then
    [ "$ANDROID_STUDIO" != yes ] && record_skip "Android (not selected)"
    return $rc
  fi

  brew_cask temurin@17 || rc=1
  brew_cask android-commandlinetools || { record_fail "Android command line tools"; return 1; }
  [ -n "${DRY_RUN:-}" ] && { info "(dry-run) would ask for API levels and install the SDK packages"; return 0; }

  export ANDROID_HOME="$HOME/Library/Android/sdk"
  mkdir -p "$ANDROID_HOME"
  JAVA_HOME=$(android_java_home); export JAVA_HOME
  [ -n "$JAVA_HOME" ] || { err "No JDK 17 found for sdkmanager"; return 1; }
  local sdkm; sdkm=$(command -v sdkmanager)
  [ -n "$sdkm" ] || { err "sdkmanager not found"; return 1; }
  sdk() { "$sdkm" --sdk_root="$ANDROID_HOME" "$@"; }

  run "Accept Android SDK licenses" bash -c "yes | '$sdkm' --sdk_root='$ANDROID_HOME' --licenses" || true
  info "Fetching the list of available Android API levels…"
  # Package ids: older sdkmanager prints "platforms;android-36", v23+ prints "platforms/android-36".
  # Normalise to ";" for parsing and convert back to whatever this sdkmanager uses when installing.
  local raw list sep=";"
  raw=$(sdk --list 2>/dev/null)
  printf '%s\n' "$raw" | grep -q 'platforms/android-' && sep="/"
  list=$(printf '%s\n' "$raw" | awk '{print $1}' | tr '/' ';')
  local apis=()
  lines_to_array apis <<<"$(printf '%s\n' "$list" | awk '{print $1}' | sed -n 's/^platforms;android-\([0-9][0-9.]*\)$/\1/p' | sort -t. -k1,1nr -k2,2nr | awk '!seen[$0]++' | head -12)"
  if [ ${#apis[@]} -eq 0 ]; then err "Could not read the SDK package list"; return 1; fi

  local picked=() pre="${apis[0]}"
  [ ${#apis[@]} -gt 1 ] && pre="$pre,${apis[1]}"
  lines_to_array picked <<<"$(choose_many "Android API levels (platforms) to install" "$pre" "${apis[@]}")"

  local pkgs=("platform-tools" "emulator" "cmdline-tools;latest") api major bt
  for api in "${picked[@]}"; do
    pkgs+=("platforms;android-$api")
    major=${api%%.*}
    bt=$(printf '%s\n' "$list" | awk '{print $1}' | sed -n "s/^build-tools;\($major\.[0-9.]*\)$/\1/p" | sort -t. -k2,2nr -k3,3nr | head -1)
    [ -n "$bt" ] && pkgs+=("build-tools;$bt")
  done
  local newest="${picked[0]:-}" img=""
  if [ "$ANDROID_EMULATOR" = yes ] && [ -n "$newest" ]; then
    img=$(printf '%s\n' "$list" | awk '{print $1}' | grep -E "^system-images;android-$newest;google_apis_playstore;arm64-v8a$" | head -1)
    [ -z "$img" ] && img=$(printf '%s\n' "$list" | awk '{print $1}' | grep -E "^system-images;android-$newest;google_apis;arm64-v8a$" | head -1)
    [ -n "$img" ] && pkgs+=("$img")
  fi

  # De-duplicate (two API levels can share build-tools)
  local uniq=() p
  for p in "${pkgs[@]}"; do case " ${uniq[*]} " in *" $p "*) ;; *) uniq+=("$p") ;; esac; done

  if [ "$sep" = "/" ]; then
    local i; for i in "${!uniq[@]}"; do uniq[$i]=$(printf '%s' "${uniq[$i]}" | tr ';' '/'); done
  fi
  run "Installing SDK packages: ${uniq[*]}" bash -c "yes | '$sdkm' --sdk_root='$ANDROID_HOME' $(printf "'%s' " "${uniq[@]}")" || rc=1

  if [ -n "$img" ]; then
    local avdm="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" avd="Pixel_API_${newest%%.*}"
    [ -x "$avdm" ] || avdm=$(command -v avdmanager)
    if "$avdm" list avd 2>/dev/null | grep -q "Name: $avd$"; then ok "Emulator $avd already exists"
    else
      run "Create emulator $avd" bash -c "echo no | '$avdm' create avd -n '$avd' -k '$(printf '%s' "$img" | tr '/' ';')' -d pixel_8" || rc=1
    fi
  fi
  [ $rc -eq 0 ] && record_ok "Android SDK (API ${picked[*]}) at $ANDROID_HOME + JDK 17"
  return $rc
}

# ── Xcode ────────────────────────────────────────────────────────────────────
XCODE_SIM=""; XCODE_ASKED=""
q_xcode() {
  [ -n "$XCODE_ASKED" ] && return 0
  XCODE_ASKED=1
  if [ ! -d /Applications/Xcode.app ]; then
    info "Xcode is installed from the Mac App Store. Sign in to the App Store app now if you haven't (it is ~10 GB)."
    open -g -a "App Store" 2>/dev/null
  fi
  ask_yn "After Xcode, also download the iOS Simulator runtime (~8 GB)?" y && XCODE_SIM=yes
}

step_xcode() {
  q_xcode
  local rc=0
  if [ -d /Applications/Xcode.app ]; then
    ok "Xcode already installed"
  elif [ -n "${DRY_RUN:-}" ]; then
    info "(dry-run) would install Xcode from the App Store"; return 0
  elif ! mas_install "$XCODE_MAS_ID" "Xcode (large download, be patient)"; then
    open "macappstore://apps.apple.com/app/id$XCODE_MAS_ID" 2>/dev/null
    record_manual "Xcode — App Store page opened (https://apps.apple.com/app/id$XCODE_MAS_ID). After installing, re-run: ./boot.sh --only xcode"
    return 0
  fi
  [ -n "${DRY_RUN:-}" ] && return 0

  run "Select Xcode for command line tools" sudo xcode-select -s /Applications/Xcode.app/Contents/Developer || rc=1
  run "Accept Xcode license" sudo xcodebuild -license accept || rc=1
  run "Xcode first launch (installs extra components)" sudo xcodebuild -runFirstLaunch || rc=1
  if [ "$XCODE_SIM" = yes ]; then
    if xcrun simctl list runtimes 2>/dev/null | grep -q '^iOS'; then ok "iOS Simulator runtime already installed"
    else run "Download iOS Simulator runtime" xcodebuild -downloadPlatform iOS || rc=1; fi
  fi
  [ $rc -eq 0 ] && record_ok "Xcode + command line tools"
  return $rc
}
