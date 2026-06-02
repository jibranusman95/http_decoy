# Contributing to httpfake

Thanks for taking the time. Bug reports, documentation improvements, and feature proposals are all welcome.

## Setup

```bash
git clone https://github.com/jibranusman/httpfake
cd httpfake
bundle install
```

## Running the tests

```bash
bundle exec rspec          # full suite
bundle exec rspec spec/httpfake/server_spec.rb   # single file
```

## Linting

```bash
bundle exec rubocop        # check
bundle exec rubocop -a     # autocorrect safe offenses
```

Both must be green before a PR can be merged. CI enforces this on every push.

## Submitting a pull request

1. Fork the repo and create a branch from `main`
2. Write a failing test that describes the bug or feature
3. Make it pass
4. Run `bundle exec rspec` and `bundle exec rubocop` — both must be clean
5. Update `CHANGELOG.md` under `[Unreleased]`
6. Open a PR with a clear description of what and why

## What we're looking for

- Bug fixes with a reproducing spec
- New DSL features (propose in an issue first if it's non-trivial)
- Additional body content-type support
- Better error messages
- Real-world usage examples in the README

## Good first issues

Check the [`good first issue`](https://github.com/jibranusman/httpfake/issues?q=label%3A%22good+first+issue%22) label for beginner-friendly tasks.

## Code style

- `frozen_string_literal: true` on every file
- Follow the existing RuboCop config (`.rubocop.yml`)
- Keep handler blocks and DSL methods small and focused
- No clever metaprogramming without a comment explaining why

## Reporting bugs

Open a GitHub issue with:
- Ruby version (`ruby --version`)
- httpfake version
- Minimal reproduction case (ideally a failing RSpec example)
- What you expected vs what happened

## Security issues

Do not open a public issue for security vulnerabilities. Email the maintainer directly (address in the gemspec).
