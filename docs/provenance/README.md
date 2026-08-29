# Provenance registry

Every adapted unit of upstream expression needs a record that matches
[schema.json](schema.json). Use [TEMPLATE.md](TEMPLATE.md) when drafting,
then add an object to [registry.json](registry.json).

Milestone M0 adds **no** adapted Juggluco or xdripswift implementation.
The registry is therefore an empty list plus package metadata. Independently
authored Sugarman modules do not require an upstream provenance row.

Reuse modes:

| Mode | Meaning |
| --- | --- |
| `verbatim` | File copied with notices preserved |
| `adapted` | Translated or modified implementation of upstream expression |
| `behavioral` | Reimplemented from observed/documented behaviour without copying source |
| `independently observed` | Derived from owned-hardware evidence or public vendor docs |

CI and reviewers require a provenance entry before any adapted file lands.
Crypto, authentication, binding, activation, reset/lifecycle commands, and
licence records need two-person review (not yet applicable at M0).
