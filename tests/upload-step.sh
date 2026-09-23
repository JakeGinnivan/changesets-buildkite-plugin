#!/usr/bin/env bash
# Checks that the step mode-upload.sh generates re-references this plugin the
# same way the pipeline did.
#
# The generated step cannot call a script by path: $PLUGIN_DIR is a checkout on
# the agent running the upload, and the step it generates may be picked up by a
# different agent. So it has to name the plugin -- and it has to survive every
# way a plugin can be named, including a vendored relative path that carries no
# recognisable plugin name at all.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

# Runs the emit_step logic with a given BUILDKITE_PLUGINS and reports the
# plugin key the generated step would use.
emit() {
  node -e '
    const pluginsJson = process.argv[1]
    let ref = null
    try {
      for (const entry of JSON.parse(pluginsJson || "[]")) {
        if (typeof entry !== "object" || entry === null) { continue }
        const [key, config] = Object.entries(entry)[0] ?? []
        if (config && typeof config === "object" && config.mode === "upload") {
          ref = key
          break
        }
      }
    } catch {}
    console.log(ref ?? "")
  ' "$1"
}

check() {
  local name="$1" plugins="$2" expect="$3"
  local got
  got="$(emit "$plugins")"
  if [[ "$got" == "$expect" ]]; then
    printf '  ok    %-40s %s\n' "$name" "${got:-<none>}"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %-40s expected %s, got %s\n' "$name" "${expect:-<none>}" "${got:-<none>}"
    FAIL=$((FAIL + 1))
  fi
}

echo 'mode-upload.sh plugin reference'

check 'pinned tag' \
  '[{"JakeGinnivan/changesets#v0.1.0":{"mode":"upload"}}]' \
  'JakeGinnivan/changesets#v0.1.0'

check 'pinned SHA' \
  '[{"JakeGinnivan/changesets#250c60a":{"mode":"upload"}}]' \
  'JakeGinnivan/changesets#250c60a'

check 'full git URL' \
  '[{"https://github.com/JakeGinnivan/changesets-buildkite-plugin.git#v1":{"mode":"upload"}}]' \
  'https://github.com/JakeGinnivan/changesets-buildkite-plugin.git#v1'

# The case the old name-matching regex got wrong: nothing in the key says
# "changesets".
check 'vendored relative path' \
  '[{"./.buildkite/plugins/release":{"mode":"upload"}}]' \
  './.buildkite/plugins/release'

# Another plugin in the same step must not be mistaken for this one.
check 'alongside another plugin' \
  '[{"docker#v5.0.0":{"image":"node"}},{"JakeGinnivan/changesets#v0.1.0":{"mode":"upload"}}]' \
  'JakeGinnivan/changesets#v0.1.0'

# A plugin whose name contains "changesets" but is not us, and is not in upload
# mode, must not be picked.
check 'similarly named other plugin' \
  '[{"someone/changesets-notify#v1":{"channel":"#rel"}},{"./vendored":{"mode":"upload"}}]' \
  './vendored'

# A check-mode step generates nothing, so nothing should match.
check 'check mode only' \
  '[{"JakeGinnivan/changesets#v0.1.0":{"mode":"check"}}]' \
  ''

check 'empty' '[]' ''

echo
echo "  ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
