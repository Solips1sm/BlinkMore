#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -x dist/Eyesight.app/Contents/MacOS/Eyesight && -x dist/BlinkMoreACAgent ]] || { echo 'Run Scripts/build.sh first.' >&2; exit 1; }
codesign --verify --strict dist/Eyesight.app
support="$HOME/Library/Application Support/BlinkMore"
backup="$support/Backups/$(date +%Y%m%d-%H%M%S)-$$"
agent_dir="$support/Automation"
label=com.solips1sm.blinkmore-on-ac
plist="$HOME/Library/LaunchAgents/$label.plist"
old_plist="$HOME/Library/LaunchAgents/com.openai.codex.blinkmore-on-ac.plist"
domain="gui/$(id -u)"
staging="/Applications/.Eyesight-staging-$$.app"
rollback="/Applications/.Eyesight-rollback-$$.app"
legacy_rollback="/Applications/.BlinkMore-rollback-$$.app"
target="/Applications/Eyesight.app"
if [[ -e "$target" ]] && [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist") != com.oxremy.blinkmorefree ]]; then
  target="/Applications/BlinkMore.app"
fi
installed=0
success=0
mkdir -p "$backup" "$agent_dir" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
for name in Eyesight BlinkMore; do
  current="/Applications/$name.app"
  [[ "$current" != /Applications/Eyesight.app || "$target" == "$current" ]] || continue
  if [[ -e "$current" ]]; then
    identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$current/Contents/Info.plist")
    [[ "$identifier" == com.oxremy.blinkmorefree ]] || { echo "Refusing to replace another app: $current" >&2; exit 1; }
    ditto -c -k --sequesterRsrc --keepParent "$current" "$backup/$name.app.zip"
  fi
done
[[ ! -f "$old_plist" ]] || cp "$old_plist" "$backup/legacy-agent.plist"
[[ ! -f "$plist" ]] || cp "$plist" "$backup/current-agent.plist"
[[ ! -f "$agent_dir/BlinkMoreACAgent" ]] || cp "$agent_dir/BlinkMoreACAgent" "$backup/BlinkMoreACAgent"
cleanup() {
  rm -rf "$staging"
  if [[ $success == 0 ]]; then
    launchctl bootout "$domain/$label" 2>/dev/null || true
    if [[ $installed == 1 ]]; then
      dist/BlinkMoreACAgent --stop
      rm -rf "$target"
    fi
    [[ ! -d "$rollback" ]] || mv "$rollback" "$target"
    [[ ! -d "$legacy_rollback" ]] || mv "$legacy_rollback" /Applications/BlinkMore.app
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
ditto dist/Eyesight.app "$staging"
codesign --verify --strict "$staging"
launchctl bootout "$domain/com.openai.codex.blinkmore-on-ac" 2>/dev/null || true
launchctl bootout "$domain/$label" 2>/dev/null || true
dist/BlinkMoreACAgent --stop
stats="$HOME/Library/Containers/com.oxremy.blinkmorefree/Data/Library/Application Support/BlinkMore/daily-statistics.json"
[[ ! -f "$stats" ]] || cp "$stats" "$backup/daily-statistics.json"
[[ ! -d "$target" ]] || mv "$target" "$rollback"
if [[ "$target" != /Applications/BlinkMore.app && -d /Applications/BlinkMore.app ]]; then
  mv /Applications/BlinkMore.app "$legacy_rollback"
fi
mv "$staging" "$target"
installed=1
cp dist/BlinkMoreACAgent "$agent_dir/BlinkMoreACAgent"
# PlistBuddy accepts paths as separate arguments, including spaces.
cp Automation/LaunchAgent.plist "$plist"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $agent_dir/BlinkMoreACAgent" "$plist"
/usr/libexec/PlistBuddy -c "Set :StandardOutPath $HOME/Library/Logs/BlinkMoreAC.log" "$plist"
/usr/libexec/PlistBuddy -c "Set :StandardErrorPath $HOME/Library/Logs/BlinkMoreAC.error.log" "$plist"
plutil -lint "$plist"
launchctl bootstrap "$domain" "$plist"
success=1
rm -rf "$rollback" "$legacy_rollback"
[[ ! -f "$old_plist" ]] || rm "$old_plist"
printf 'Installed Eyesight at %s. Backup: %s\n' "$target" "$backup"
