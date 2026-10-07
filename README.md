# Husky

A native floating chat client for macOS, with saved backend connections,
conversation history, streaming replies, and local drafts. Backends integrate
through the versioned `husky.v1` gRPC API.

## Development

The package targets macOS 15 or later. Current local verification uses Apple
Swift 6.4. Build and run the tests with Xcode's Swift toolchain:

```sh
swift build
swift test
```

For a local development backend, start the deterministic fixture in one terminal:

```sh
swift run HuskyFixtureServer --fixture-mode
```

Start the client in another:

```sh
swift run Husky
```

Open **Connect → Connection settings**, add `http://127.0.0.1:50051`, enable
local HTTP development, and create a conversation. The fixture returns labeled
deterministic text. Use HTTPS for remote backends; saved bearer tokens use
Keychain. See [backend setup and adapter requirements](docs/backend-adapter.md).

The menu-bar menu can show/hide Husky or reset its position. The header has a
move handle. `--demo` displays a static appearance sample; `--fixture-mode`
retains the foundation's direct fixture demonstration.

## Delivery status

Client source and automated verification are under review in [PR #6](https://github.com/sirerun/husky/pull/6). All 88 automated tests pass at `e3b7232`. Native
movement, focus/IME, display and accessibility acceptance remain open. Signed
releases, local installation and Sparkle update verification are later delivery
gates. See the [checkable plan](docs/plan.md) and [verification log](docs/devlog.md)
for exact evidence and limitations.

## License

[Apache License 2.0](LICENSE), with the copyright notice in [NOTICE](NOTICE).
