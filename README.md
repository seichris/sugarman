# Sugarman

An open-source iOS project for glucose-related workflows.

## Upstream references

This repository intentionally tracks two upstream projects as pinned Git
submodules rather than vendoring their histories into Sugarman:

- `upstream/xdripswift` — iOS/Swift reference implementation
- `upstream/Juggluco` — Android/reference implementation for sensor behaviour

They are reference sources, not Xcode build dependencies. Sugarman code lives
outside `upstream/` and should be implemented as native, testable Swift.

Clone with the references included:

```sh
git clone --recurse-submodules git@github.com:seichris/sugarman.git
```

For an existing clone:

```sh
git submodule update --init --recursive
```

See [the upstream policy](docs/UPSTREAMS.md) before copying or adapting code.
