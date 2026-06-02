# http_decoy

**A real fake HTTP server. For real tests.**

[![CI](https://github.com/jibranusman95/http_decoy/actions/workflows/ci.yml/badge.svg)](https://github.com/jibranusman95/http_decoy/actions)
[![Gem Version](https://badge.fury.io/rb/http_decoy.svg)](https://badge.fury.io/rb/http_decoy)
[![Downloads](https://img.shields.io/gem/dt/http_decoy)](https://rubygems.org/gems/http_decoy)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

Your WebMock stubs are lying to you.

They test that your code constructs the right HTTP call. Not that the API would accept it. Not that the response shape matches what your code expects. Not that you haven't been sending a stale request format for six months while production quietly breaks.

**http_decoy spins up a real Rack server inside your tests** — one that validates incoming request contracts, computes dynamic responses from real inputs, and fails loudly the moment your code sends something wrong.

No cassettes. No scattered stubs. No surprises on deploy day.

---

## The problem, illustrated

Three tests. Same feature. Different levels of lying.

### Test 1 — WebMock (stub at the adapter layer)

```ruby
stub_request(:post, "https://api.stripe.com/v1/charges")
  .with(body: { amount: "2000", currency: "usd" })
  .to_return(status: 200, body: '{"id":"ch_123","status":"succeeded"}')
```

This test passes even if:
- Your code sends `paymet_method` instead of `payment_method` (typo, ships to prod)
- Stripe adds a required field next week (stub keeps returning 200, forever)
- The response shape changes (your parser breaks in prod, not in tests)
- Your code sends `"2000"` as a string but Stripe requires an integer

The stub doesn't know anything about Stripe. It just pattern-matches and returns JSON.

### Test 2 — VCR (record once, replay forever)

```ruby
it "charges the customer", vcr: { cassette_name: "stripe/charge" } do
  result = StripeService.charge(amount: 2000)
  expect(result.status).to eq "succeeded"
end
```

This test passes even if:
- The cassette was recorded in 2022 and `payment_method` became required in 2023
- The cassette contains your actual Stripe test key (committed to git, forever)
- You need to test what happens when a card is declined (good luck editing cassette YAML)
- CI has no network access for the initial recording run

You end up with 50 YAML files nobody touches, all slowly diverging from reality.

### Test 3 — http_decoy (what tests should look like)

```ruby
FakeStripe = HttpDecoy.define(:stripe) do
  base_url "https://api.stripe.com"

  post "/v1/charges" do
    requires_body :amount, :currency, :payment_method
    validates :amount,   type: Integer, min: 50
    validates :currency, inclusion: %w[usd gbp eur]

    respond 200, json: {
      id:       -> { "ch_#{SecureRandom.hex(8)}" },
      status:   "succeeded",
      amount:   -> { body[:amount] },
      currency: -> { body[:currency] }
    }
  end

  post "/v1/charges", scenario: :card_declined do
    respond 402, json: { error: { code: "card_declined" } }
  end
end
```

Now your tests:
- **Fail immediately** if your code sends a missing or invalid field
- **Reflect real request data** back in responses — no frozen stubs
- **Test failure paths** with one line: `with_scenario(:card_declined) { ... }`
- **Work offline**, in CI, on a plane, in an airgapped environment
- **Live in one place** — define once, use across every test in the suite

---

## Install

```ruby
# Gemfile
group :test do
  gem "http_decoy"
end
```

```bash
bundle install
```

---

## Quickstart (5 minutes)

### 1. Define your fake service

```ruby
# spec/support/fakes/fake_stripe.rb
FakeStripe = HttpDecoy.define(:stripe) do
  base_url "https://api.stripe.com"

  post "/v1/charges" do
    requires_body :amount, :currency, :payment_method
    validates :amount, type: Integer, min: 50

    respond 200, json: {
      id:     -> { "ch_#{SecureRandom.hex(8)}" },
      status: "succeeded",
      amount: -> { body[:amount] }
    }
  end

  get "/v1/charges/:id" do
    respond 200, json: {
      id:     -> { path_params[:id] },
      status: "succeeded"
    }
  end

  post "/v1/charges", scenario: :card_declined do
    respond 402, json: {
      error: { code: "card_declined", message: "Your card was declined." }
    }
  end

  post "/v1/charges", scenario: :network_error do
    raise_error :timeout
  end
end
```

### 2. Load it in spec_helper

```ruby
# spec/spec_helper.rb
require "http_decoy"
require "support/fakes/fake_stripe"

RSpec.configure do |config|
  config.include FakeStripe.rspec_helpers
end
```

### 3. Write tests

```ruby
RSpec.describe StripeService do
  describe "#charge" do
    it "creates a charge and returns the id" do
      result = StripeService.charge(amount: 2000, currency: "usd", payment_method: "pm_card_visa")
      expect(result.id).to match(/\Ach_/)
      expect(result.amount).to eq 2000
    end

    it "raises PaymentError on card decline" do
      with_scenario(:card_declined) do
        expect { StripeService.charge(amount: 2000, currency: "usd", payment_method: "pm_card_visa") }
          .to raise_error(StripeService::PaymentError, /declined/)
      end
    end

    it "raises NetworkError on timeout" do
      with_scenario(:network_error) do
        expect { StripeService.charge(amount: 2000, currency: "usd", payment_method: "pm_card_visa") }
          .to raise_error(StripeService::NetworkError)
      end
    end

    it "catches bad requests before they reach prod" do
      # Missing payment_method — http_decoy raises immediately with a descriptive error
      expect { StripeService.charge(amount: 2000, currency: "usd") }
        .to raise_error(HttpDecoy::HandlerContext::ContractError, /payment_method is required/)
    end
  end
end
```

No setup per test. No per-test `stub_request`. No cassette files.

---

## DSL Reference

### Defining a server

```ruby
MyFakeService = HttpDecoy.define(:my_service) do
  base_url "https://api.example.com"   # intercepted via WebMock automatically
  # ...routes
end
```

### Routes

```ruby
get    "/path"
post   "/path"
put    "/path"
patch  "/path"
delete "/path"
```

Path parameters:

```ruby
get "/users/:id/posts/:post_id" do
  respond 200, json: { user_id: path_params[:id], post_id: path_params[:post_id] }
end
```

Query parameters:

```ruby
get "/search" do
  respond 200, json: { results: [], query: query_params[:q] }
end
```

### Request contract validation

```ruby
post "/orders" do
  requires_body :item_id, :quantity              # presence check
  validates :quantity, type: Integer, min: 1     # type + range
  validates :status, inclusion: %w[pending paid] # enum

  respond 201, json: { order_id: -> { SecureRandom.uuid } }
end
```

When validation fails, http_decoy raises `HttpDecoy::HandlerContext::ContractError` with a message naming the exact field and rule. Your test fails at the right place, with the right message.

### Dynamic responses

Use lambdas anywhere in the response body — evaluated at request time with access to the full request:

```ruby
post "/echo" do
  respond 200, json: {
    received_at: -> { Time.now.iso8601 },
    you_sent:    -> { body },
    your_ip:     -> { request.ip }
  }
end
```

### Scenarios (failure simulation)

```ruby
# Definition
post "/payments", scenario: :rate_limited do
  respond 429, json: { error: "Too many requests" }, headers: { "Retry-After" => "30" }
end

post "/payments", scenario: :timeout do
  raise_error :timeout
end

# Usage in tests
with_scenario(:rate_limited) do
  expect { PaymentService.pay(100) }.to raise_error(PaymentService::RateLimitError)
end
```

Available transport errors: `:timeout`, `:reset`, `:refused`.

### Stateful sequences

```ruby
get "/account/balance" do
  respond_sequence(
    [200, { json: { balance: 1000, status: "active" } }],
    [200, { json: { balance:    0, status: "active" } }],
    [403, { json: { error: "Account suspended" } }]
  )
end
```

First call → 1000. Second call → 0. Third call → 403. Wraps automatically.

### Request assertions

```ruby
it "sends the right payload" do
  StripeService.charge(amount: 500, currency: "usd", payment_method: "pm_123")

  expect(fake_server(:stripe)).to have_received_request(:post, "/v1/charges")
    .once
    .with(body: { amount: 500, currency: "usd" })
end
```

Chains: `.once`, `.twice`, `.times(n)`, `.with(body: ...)`.

---

## RSpec integration

Suite-wide (recommended):

```ruby
RSpec.configure do |config|
  config.include FakeStripe.rspec_helpers
  config.include FakeSendGrid.rspec_helpers
end
```

Inline per describe block:

```ruby
RSpec.describe "degraded upstream" do
  include HttpDecoy::RSpec

  fake_server(:api) do
    get "/status" do
      respond 503, json: { status: "degraded" }
    end
  end

  it "handles it gracefully" do
    expect(MyApp.health_check).to eq :degraded
  end
end
```

---

## Configuration

```ruby
# Opt out of WebMock auto-interception (e.g. if you manage stubs manually)
HttpDecoy.configure do |config|
  config.auto_intercept = false
end
```

---

## Why not WebMock / VCR? (honest comparison)

| | WebMock | VCR | **http_decoy** |
|---|---|---|---|
| Real server | No | No | **Yes** |
| Request contract validation | No | No | **Yes** |
| Dynamic responses | No | No | **Yes** |
| Failure scenario testing | Verbose | Very hard | **One line** |
| Works offline | Yes | First run: No | **Yes** |
| Secrets in version control | No | **Risk** | No |
| Cassettes to maintain | No | **Yes** | No |
| Define once, use everywhere | Requires setup | Yes | **Yes** |
| Catches API drift | No | No | **Yes** |

http_decoy uses WebMock internally to intercept requests — complementary, not a replacement.

---

## Real-world examples

<details>
<summary>Stripe (payments)</summary>

```ruby
FakeStripe = HttpDecoy.define(:stripe) do
  base_url "https://api.stripe.com"

  post "/v1/payment_intents" do
    requires_body :amount, :currency, :payment_method
    validates :amount, type: Integer, min: 50

    respond 200, json: {
      id:             -> { "pi_#{SecureRandom.hex(12)}" },
      status:         "succeeded",
      amount:         -> { body[:amount] },
      currency:       -> { body[:currency] },
      payment_method: -> { body[:payment_method] }
    }
  end

  post "/v1/payment_intents", scenario: :insufficient_funds do
    respond 402, json: {
      error: { code: "insufficient_funds", decline_code: "insufficient_funds" }
    }
  end
end
```
</details>

<details>
<summary>SendGrid (email)</summary>

```ruby
FakeSendGrid = HttpDecoy.define(:sendgrid) do
  base_url "https://api.sendgrid.com"

  post "/v3/mail/send" do
    requires_body :to, :from, :subject, :content
    respond 202, text: ""
  end

  post "/v3/mail/send", scenario: :invalid_email do
    respond 400, json: { errors: [{ message: "Invalid email address" }] }
  end
end
```
</details>

<details>
<summary>Internal microservice</summary>

```ruby
FakeInventory = HttpDecoy.define(:inventory) do
  base_url "https://inventory.internal"

  get "/products/:sku/stock" do
    respond 200, json: {
      sku:   -> { path_params[:sku] },
      stock: -> { rand(0..100) },
      unit:  "each"
    }
  end

  get "/products/:sku/stock", scenario: :out_of_stock do
    respond 200, json: { sku: -> { path_params[:sku] }, stock: 0 }
  end

  get "/products/:sku/stock", scenario: :service_down do
    respond 503, json: { error: "Inventory service is down" }
  end
end
```
</details>

---

## Requirements

- Ruby 3.1+
- Runtime dependencies: `webrick`, `rack` (both lightweight)
- Optional: `webmock` for URL interception

---

## Contributing

```bash
git clone https://github.com/jibranusman95/http_decoy
cd http_decoy
bundle install
bundle exec rspec      # run all tests
bundle exec rubocop    # lint
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for full guidelines. Good first issues are labeled [`good first issue`](https://github.com/jibranusman95/http_decoy/issues?q=label%3A%22good+first+issue%22).

---

## License

MIT. See [LICENSE](LICENSE).

---

*http_decoy — stop testing your assumptions, start testing your contracts.*
