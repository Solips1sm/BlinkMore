#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -x dist/BlinkMore.app/Contents/MacOS/BlinkMore && -x dist/BlinkMoreACAgent ]] || { echo 'Run Scripts/build.sh first.' >&2; exit 1; }
codesign --verify --strict dist/BlinkMore.app
support="$HOME/Library/Application Support/BlinkMore"
backup="$support/Backups/$(date +%Y%m%d-%H%M%S)-$$"
agent_dir="$support/Automation"
label=com.solips1sm.blinkmore-on-ac
plist="$HOME/Library/LaunchAgents/$label.plist"
old_plist="$HOME/Library/LaunchAgents/com.openai.codex.blinkmore-on-ac.plist"
domain="gui/$(id -u)"
staging="/Applications/.BlinkMore-staging-$$.app"
rollback="/Applications/.BlinkMore-rollback-$$.app"
installed=0
success=0
mkdir -p "$backup" "$agent_dir" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
if [[ -d /Applications/BlinkMore.app ]]; then
  ditto -c -k --sequesterRsrc --keepParent /Applications/BlinkMore.app "$backup/BlinkMore.app.zip"
fi
[[ ! -f "$old_plist" ]] || cp "$old_plist" "$backup/legacy-agent.plist"
[[ ! -f "$plist" ]] || cp "$plist" "$backup/current-agent.plist"
[[ ! -f "$agent_dir/BlinkMoreACAgent" ]] || cp "$agent_dir/BlinkMoreACAgent" "$backup/BlinkMoreACAgent"
cleanup() {
  rm -rf "$staging"
  if [[ $success == 0 ]]; then
    launchctl bootout "$domain/$label" 2>/dev/null || true
    if [[ $installed == 1 ]]; then
      dist/BlinkMoreACAgent --stop
      rm -rf /Applications/BlinkMore.app
      [[ ! -d "$rollback" ]] || mv "$rollback" /Applications/BlinkMore.app
    fi
    if [[ -f "$backup/current-agent.plist" ]]; then
      cp "$backup/current-agent.plist" "$plist"
      [[ ! -f "$backup/BlinkMoreACAgent" ]] || cp "$backup/BlinkMoreACAgent" "$agent_dir/BlinkMoreACAgent"
      launchctl bootstrap "$domain" "$plist" || true
    elif [[ -f "$old_plist" ]]; then
      launchctl bootstrap "$domain" "$old_plist" || true
    fi
  fi
}
trap cleanup EXIT
ditto dist/BlinkMore.app "$staging"
codesign --verify --strict "$staging"
launchctl bootout "$domain/com.openai.codex.blinkmore-on-ac" 2>/dev/null || true
launchctl bootout "$domain/$label" 2>/dev/null || true
dist/BlinkMoreACAgent --stop
[[ ! -d /Applications/BlinkMore.app ]] || mv /Applications/BlinkMore.app "$rollback"
installed=1
mv "$staging" /Applications/BlinkMore.app
cp dist/BlinkMoreACAgent "$agent_dir/BlinkMoreACAgent"
# PlistBuddy accepts paths as separate arguments, including spaces.
cp Automation/LaunchAgent.plist "$plist"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $agent_dir/BlinkMoreACAgent" "$plist"
/usr/libexec/PlistBuddy -c "Set :StandardOutPath $HOME/Library/Logs/BlinkMoreAC.log" "$plist"
/usr/libexec/PlistBuddy -c "Set :StandardErrorPath $HOME/Library/Logs/BlinkMoreAC.error.log" "$plist"
plutil -lint "$plist"
launchctl bootstrap "$domain" "$plist"
success=1
rm -rf "$rollback"
[[ ! -f "$old_plist" ]] || rm "$old_plist"
printf 'Installed BlinkMore. Backup: %s\n' "$backup"
