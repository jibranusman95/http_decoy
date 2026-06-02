# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/jibranusman/http_decoy/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jibranusman/http_decoy/releases/tag/v0.1.0
