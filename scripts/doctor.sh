#!/usr/bin/env bash
# Report passdown install-channel hygiene per host: one channel per host, and
# direct installs in sync with this checkout. Exits 1 when any ISSUE is found.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skills_src="$repo_root/plugins/passdown/skills"
issues=0

report_host() { # report_host <host> <skills-dir> <plugin-state: yes|no|n/a>
  local host="$1" skills_dir="$2" plugin="$3"
  local direct=() skill name src
  if [ -d "$skills_dir" ]; then
    for skill in "$skills_dir"/passdown-*/; do
      [ -d "$skill" ] || continue
      direct+=("${skill%/}")
    done
  fi

  if [ "${#direct[@]}" -gt 0 ] && [ "$plugin" = yes ]; then
    issues=$((issues + 1))
    echo "ISSUE $host: BOTH plugin and direct installs are active — pick one channel (remove $skills_dir/passdown-* or uninstall the plugin)"
  elif [ "${#direct[@]}" -eq 0 ] && [ "$plugin" != yes ]; then
    echo "NOTE  $host: passdown is not installed"
  elif [ "$plugin" = yes ]; then
    echo "OK    $host: plugin channel only"
  else
    echo "OK    $host: direct channel only (${#direct[@]} skills)"
  fi

  for skill in ${direct[@]+"${direct[@]}"}; do
    name="$(basename "$skill")"
    src="$skills_src/$name"
    if [ ! -d "$src" ]; then
      issues=$((issues + 1))
      echo "ISSUE $host: direct skill '$name' is not part of this checkout"
    elif ! diff -rq "$src" "$skill" >/dev/null 2>&1; then
      issues=$((issues + 1))
      echo "ISSUE $host: direct skill '$name' is out of sync with this checkout — re-run ./install.sh --host $host"
    fi
  done
}

claude_plugin=no
claude_plugins_file="$HOME/.claude/plugins/installed_plugins.json"
if [ -f "$claude_plugins_file" ] &&
  grep -q '"passdown@passdown"' "$claude_plugins_file"; then
  claude_plugin=yes
fi

codex_plugin=no
codex_config="${CODEX_HOME:-$HOME/.codex}/config.toml"
if [ -f "$codex_config" ] && grep -q 'passdown@passdown' "$codex_config"; then
  codex_plugin=yes
fi

report_host claude "$HOME/.claude/skills" "$claude_plugin"
report_host codex "$HOME/.agents/skills" "$codex_plugin"
report_host kiro "$HOME/.kiro/skills" n/a

if [ "$issues" -gt 0 ]; then
  echo "FAIL  $issues issue(s) found"
  exit 1
fi
echo "PASS  install channels are clean"
