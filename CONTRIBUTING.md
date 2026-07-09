# Contributing to http_decoy

First: thank you. It genuinely means a lot.

## Quick start

```bash
git clone https://github.com/jibranusman95/http_decoy
cd http_decoy
bundle install
bundle exec rspec     # RSpec suite — make sure everything is green before you start
bundle exec rake test # Minitest suite
bundle exec rubocop   # no existing offenses to inherit
```

## How to contribute

**Found a bug?** Open an issue. Include a minimal reproduction if you can — it'll get fixed faster.

**Want a feature?** Open an issue first so we can align before you build. Nothing worse than putting work into something that doesn't fit.

**Have a fix ready?** Just open a PR. One thing per PR. Include a failing test if the change is non-trivial.

**Docs or README improvements?** Also very welcome — just send the PR directly.

## Before you submit

- `bundle exec rspec` — all green
- `bundle exec rake test` — all green (Minitest suite)
- `bundle exec rubocop` — no new offenses
- Focused scope — one fix or feature per PR

## What happens next

I review promptly — usually within a day or two, often faster. I'll either merge it, ask for changes with clear reasoning, or explain why it doesn't fit. No ghosting.

## License

By contributing, you agree your changes are released under the same [MIT License](LICENSE) as this project.
