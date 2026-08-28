# Upstream policy

## Purpose

Sugarman keeps the following projects as Git submodules so their source can be
reviewed alongside the iOS app without being copied into Sugarman's Git
history:

| Path | Pinned revision | Role |
| --- | --- | --- |
| `upstream/xdripswift` | `69eb88330a22e7d9969ee94ec6fa87072367fd2e` | iOS/Swift reference |
| `upstream/Juggluco` | `11d016eb3aeffe77e86d9522f5192e83790b5a21` | Android and sensor-behaviour reference |

The pinned revisions are deliberate. Updating an upstream is a reviewed change,
not an automatic dependency update.

## Setup

Clone Sugarman and its upstreams in one command:

```sh
git clone --recurse-submodules git@github.com:seichris/sugarman.git
```

Or initialize the references in an existing checkout:

```sh
git submodule update --init --recursive
```

`--recursive` matters because Juggluco has an upstream submodule of its own.

## Boundaries

- Do not add either upstream project to the Sugarman Xcode target.
- Do not use a filesystem symlink as a project dependency; it is not portable
  to CI or other contributors' checkouts.
- Keep new Sugarman source, tests, and build configuration outside `upstream/`.
- Record the source path, commit, copyright notice, and licence review for
  every adapted file or algorithm.

## Licence and reuse

Both upstream repositories publish GPL version 3 licence text. Sugarman is
intended to be open source, but open sourcing alone does not determine whether
a particular reuse is compliant. Before copying or adapting upstream code,
choose and document a compatible Sugarman project licence, preserve required
notices, and review the specific source file's provenance.

Juggluco is an Android project and its build instructions refer to third-party
binary inputs. It is therefore a behavioural/reference source, not an iOS
library to link into Sugarman.

## Updating a pinned upstream

1. Fetch and inspect the desired revision in the relevant submodule.
2. Review the upstream diff, licences, and any new build or binary inputs.
3. Check out the selected commit in the submodule.
4. Stage the gitlink change from the Sugarman root and document the reason in
   the commit.

For example:

```sh
git -C upstream/xdripswift fetch origin
git -C upstream/xdripswift checkout <reviewed-commit>
git add upstream/xdripswift
```
