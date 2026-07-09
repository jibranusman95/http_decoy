# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `HttpDecoy::Minitest` — Minitest integration, parallel to `HttpDecoy::RSpec`:
  - `include HttpDecoy::Minitest` + `fake_server(name) { ... }` class macro (inline pattern)
  - `HttpDecoy.define(:name) { ... }.minitest_helpers` — suite-wide helper module, shared with RSpec via the same `Definition`
  - `assert_received_request(server, method, path, times:, body:)` / `refute_received_request(server, method, path)` assertions
  - `with_scenario(:name) { ... }` instance method, same semantics as the RSpec version
  - `require "http_decoy/minitest"` never loads RSpec, and `require "http_decoy/rspec"` never loads Minitest
- `respond(status, ..., after: seconds)` — delay a response by a real, measurable amount of time; useful for testing timeout thresholds and loading states against a wall clock rather than a raised exception. Works with `respond_sequence` entries too.
- `raise_error(:timeout | :reset | :refused)` now actually terminates the TCP connection when the fake server is reached over a real socket (not via WebMock interception) — previously this path silently returned a normal `500` response instead of simulating a dropped connection, so code that specifically handles `Errno::ECONNRESET`/timeouts was never exercised unless WebMock was in the loop. Uses `SO_LINGER` to force a real RST rather than a clean EOF.

### Fixed

- `HttpDecoy.define(:name) { ... }.rspec_helpers` used standalone via `RSpec.configure { |c| c.include Foo.rspec_helpers }` (the primary documented usage) raised `NoMethodError` on `_http_decoy_register` unless the example group also separately did `include HttpDecoy::RSpec`. Ruby's `included` hook doesn't cascade through nested `include`s, so the generated helper module's `included` callback now explicitly extends `ClassMethods` onto the includer.

### Changed

- `HttpDecoy::Definition` moved to its own file (`definition.rb`) so `HttpDecoy.define` no longer force-loads RSpec — a Minitest-only project including `http_decoy/minitest` never pulls in `rspec/core`, and vice versa.
- Deduplicated the request-body matcher shared by the RSpec `have_received_request(...).with(body:)` chain and the new Minitest `assert_received_request(..., body:)` into `HttpDecoy::BodyMatcher`.

## [0.1.0] — 2026-06-02

### Added

- `HttpDecoy.define` — declare a named fake service with a DSL block
- `HttpDecoy::RouteMap` — route definition DSL (`get`, `post`, `put`, `patch`, `delete`)
- `HttpDecoy::Router` — path matching with `:param` template segments
- `HttpDecoy::Server` — real WEBrick HTTP server on OS-assigned port (port 0); starts in a background thread, stops cleanly
- `HttpDecoy::RequestLog` — thread-safe store of every received request; powers assertion helpers
- `HttpDecoy::HandlerContext` — `instance_eval` DSL surface inside handler blocks:
  - `respond(status, json:, text:, headers:)` — build a response
  - `respond_sequence(*entries)` — return different responses on successive calls
  - `requires_body(*keys)` — assert required fields are present; raises `ContractError` with descriptive message if not
  - `validates(key, type:, min:, max:, inclusion:)` — type and range validation
  - `raise_error(:timeout | :reset | :refused)` — simulate transport-level failures
  - `body`, `path_params`, `query_params` — request data accessors
  - Lambdas in JSON response values are resolved at request time (`-> { body[:amount] }`)
- `fake_server(name) { ... }` — class-level RSpec macro; starts a fresh server per example, tears it down after
- `HttpDecoy.define(:name) { ... }.rspec_helpers` — suite-wide helper module pattern
- `with_scenario(:name) { ... }` — activate a named failure/alternate scenario in a test block
- `have_received_request(method, path)` — RSpec matcher with `.once`, `.twice`, `.times(n)`, `.with(body:)` chains
- WebMock auto-detection: if WebMock is loaded and `base_url` is declared, requests are intercepted automatically; teardown removes only http_decoy's stub
- `HttpDecoy.configure { |c| c.auto_intercept = false }` — opt out of automatic WebMock interception
- Supports `application/json`, `application/x-www-form-urlencoded`, and raw bodies
- Compatible with Rack 2.x and Rack 3.x
- Ruby 3.1+ support
- 92% test coverage (SimpleCov), 66 examples

[Unreleased]: https://github.com/jibranusman95/http_decoy/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jibranusman95/http_decoy/releases/tag/v0.1.0
