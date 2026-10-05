# Husky local gRPC fixture

This executable is a deterministic, in-memory implementation of the frozen
`husky.v1` contract for local development and conformance testing. It is not an
AI assistant, hosted service, or production backend. It stores no data after
process exit and executes no tools.

Start it only after explicitly selecting fixture mode:

```sh
swift run HuskyFixtureServer --fixture-mode --port 50051
swift run Husky --fixture-mode --fixture-port 50051
```

The server binds to `127.0.0.1` and uses plaintext HTTP/2 only on that loopback
listener. Port `0` asks the operating system for an available port; startup
prints the selected address and labels it as the local fixture. The app connects
to port `50051` by default; change it with `--fixture-port`. The app must use an
explicitly selected local fixture profile before connecting. Remote
endpoints are outside this fixture's scope and must use TLS.

The scripted service uses stable in-memory IDs, cursor pagination, idempotent
request replay, streamed deltas/completion/status, cancellation, unsolicited
server messages, retained-event replay, and a `ResyncRequired` path after the
configured event window expires. Responses are fixed fixture text. Nothing in
this target qualifies a production service or release backend.
