# Changesets Buildkite Plugin

Runs the [changesets](https://changesets.dev) release flow on Buildkite: gate PRs
on a changeset, open the "Version Packages" PR, publish, and write the GitHub
release.

On GitHub Actions this is `changesets/action`. There is no Buildkite equivalent —
the [plugin directory](https://buildkite.com/plugins) has none, and neither does
GitHub — so this fills that gap.

## Usage

Two steps. One gates pull requests, the other drives releases from the default
branch:

```yaml
steps:
  - label: ':memo: changeset'
    plugins:
      - JakeGinnivan/changesets#v0.1.0:
          mode: check

  - label: ':pipeline: release'
    plugins:
      - JakeGinnivan/changesets#v0.1.0:
          mode: upload
          command: pnpm install --frozen-lockfile
          agents:
            queue: linux-small
```

`mode: upload` runs `changeset status` and uploads *one* step, named for what it
will do:

- changesets pending → **version packages**, which opens or force-updates the
  version PR
- none pending → **publish**, because the version PR has landed

Deciding at upload time rather than inside the step means the build page says
which half is happening before it runs, instead of you learning it from a log.

## Options

| Option | Default | |
|---|---|---|
| `mode` | *required* | `check`, `upload`, or `version` / `release` to drive a half yourself |
| `publish` | `publish` | `publish`, `stage`, or `none` to leave releasing to your own step |
| `release` | `true` | Create the GitHub release from the CHANGELOG entry |
| `npm-user` | — | npm account whose staged-packages page is linked (see below) |
| `command` | — | Command the generated steps run first, e.g. install and build |
| `agents` | — | Agent tags for the generated steps |

## Staged publishing

`publish: stage` uses [`npm stage publish`](https://docs.npmjs.com/cli/v11/commands/npm-stage/),
which puts the version on the registry without making it public. A maintainer
approves it later with 2FA — proof-of-presence on the act that publishes, with
no 2FA prompt in CI.

Changesets does not support this itself ([changesets#2025](https://github.com/changesets/changesets/issues/2025)
is open), so this mode calls npm directly instead of `changeset publish`. It is
therefore single-package only for now.

The stage id is read from `npm stage publish --json` and written into both the
GitHub release and the build annotation, so approving is a copy-paste:

```
npm stage view <id>
npm stage approve <id>
```

`npm stage approve` works for whoever is logged in and prompts for their own
2FA. The npmjs.com approval page lives under `/settings/<user>/staged-packages`,
which is per-account and cannot be derived from the package — set `npm-user` to
have it linked from the release notes, or leave it unset and the notes give the
CLI commands alone.

## The changeset gate

`mode: check` defers to `changeset status --since`, the tool's own check, so it
understands package boundaries rather than matching paths against `^src/`.

It has to let the "Version Packages" commit through — that commit deletes every
changeset, so the gate would otherwise fail the release PR permanently. It
recognises that commit **by its content, not its branch name**: branch builds
carry no PR metadata, so a `changeset-release/*` name match would be an
authorization check made of a string anyone can choose.

A commit is exempt only if it changes nothing but `package.json`, `CHANGELOG.md`
and deleted changesets, and every changed manifest differs only on `version` or
on dependency ranges. See `lib/is-version-pr.sh`, and `tests/fixtures.sh` for
the bypasses it rejects.

## Requirements

- `node`, `git` and `curl` on the agent
- `changeset` resolvable via `npx --no-install`, so your `command` should
  install dependencies
- A `GITHUB_TOKEN` with `contents: write` and `pull-requests: write`, read from
  the agent environment or `buildkite-agent secret get GITHUB_TOKEN`. The
  Buildkite GitHub App's own credentials are read-only and cannot push.
- `NPM_TOKEN` likewise, unless you publish some other way

## Tests

```sh
tests/fixtures.sh
```
