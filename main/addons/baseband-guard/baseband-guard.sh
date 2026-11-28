BBG_REPO="https://github.com/vc-teahouse/Baseband-guard"
BBG_LSM="landlock,lockdown,yama,loadpin,safesetid,selinux,smack,tomoyo,apparmor,bpf,baseband_guard"
REQUIRED=(BBG "LSM=\"$BBG_LSM\"")
PROBES=("BBG -")

addon_apply() {
  local ksrc="$1" work="$2"
  [[ -d "$ksrc/security" ]] || { echo "baseband-guard: $ksrc/security missing" >&2; return 1; }
  rm -rf "$ksrc/Baseband-guard"
  git clone -q "$BBG_REPO" "$ksrc/Baseband-guard" || { echo "baseband-guard: clone failed" >&2; return 1; }
  git -C "$ksrc/Baseband-guard" checkout -q main || { echo "baseband-guard: no main branch" >&2; return 1; }
  [[ -f "$ksrc/Baseband-guard/setup.sh" && -f "$ksrc/Baseband-guard/Kconfig" ]] || { echo "baseband-guard: upstream layout changed" >&2; return 1; }
  # the trailing CONFIG_LSM hint in setup.sh needs gawk and may exit non-zero; the hooks are verified below instead
  (cd "$ksrc" && sh Baseband-guard/setup.sh >"$work/setup.log" 2>&1) || true
  grep -q '^\[+\] Done\.' "$work/setup.log" || { cat "$work/setup.log" >&2; echo "baseband-guard: setup.sh did not finish" >&2; return 1; }
  grep -q 'baseband-guard' "$ksrc/security/Makefile" || { echo "baseband-guard: security/Makefile not hooked" >&2; return 1; }
  grep -q 'security/baseband-guard/Kconfig' "$ksrc/security/Kconfig" || { echo "baseband-guard: security/Kconfig not hooked" >&2; return 1; }
  [[ -L "$ksrc/security/baseband-guard" ]] || { echo "baseband-guard: symlink missing" >&2; return 1; }
  git -C "$ksrc/Baseband-guard" rev-parse --short=8 HEAD > "$work/version"
  echo "   integrated Baseband-guard @ $(cat "$work/version") (latest main)"
}
