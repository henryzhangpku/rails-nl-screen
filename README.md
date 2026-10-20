# rails-nl-screen

By [Henry Zhang](https://www.officialhenryzhang.com/) ([GitHub](https://github.com/henryzhangpku)). Live demo: https://henryzhangpku.github.io/rails-nl-screen/

A learning project: a plain-English stock screen in Rails 8 + Hotwire.

**Study notes:** [How the Rails 8 stack is used here](docs/ARCHITECTURE.md): layer by layer, with architecture diagrams, "In 2007 / Now" comparisons, a Rails 8 vs. Python + TypeScript comparison, and exercises.

Type something like

> RSI under 30 on the daily, MACD crossing above its signal on the weekly, volume above its 20-day average

and the app:

1. **parses** it into a screen spec: whitelisted conditions such as `rsi14 < 30`, `macd_cross_up_w == true`,
   `close > sma200`. The spec is the **same contract as [EquityScout](https://github.com/henryzhangpku/equity-scout)**,
   the Python version of this product: same field names, units, operators, validation messages and wording
   (see [Same product, two stacks](#same-product-two-stacks)),
2. **shows you what it understood** before any results, and lists anything it **won't screen, with the reason**
   (an EMA, revenue growth...), never approximated,
3. **runs it in a background job** over ~100 large US tickers using free daily prices (Yahoo's chart API), cached in SQLite,
4. **walks every stock through a funnel** (how many passed, failed, or had no data at each step) and **streams each
   match into the results table live** (Turbo Streams), with the values it used and a one-line "why it matched",
5. **ranks the survivors** as EquityScout does: a weighted mean of percentile ranks on the spec's ranking fields.
6. **keeps a searchable history** at `/screens`: search as you type, filter, sort and paginate inside a Turbo Frame, delete with a toast.
7. **treats the LLM prompt as data**: it lives in [PromptEngine](https://github.com/aviflombaum/prompt_engine), Avi Flombaum's mountable engine, at `/prompts`, where each edit becomes a numbered version and every screen records which version parsed it, and `bin/rails prompts:eval` scores a version against a set of example screens. The editor sits behind Rails 8's generated sign-in. The app runs the engine from [Henry's fork](https://github.com/henryzhangpku/prompt_engine), whose only changes are three fixes offered upstream ([details](docs/ARCHITECTURE.md#running-on-a-fork-three-fixes-to-promptengine)).

No React, no Node build, no paid data. Optional: with an API key, an LLM *proposes* the screen spec as JSON (DeepSeek `deepseek-v4-flash` by default; any provider [RubyLLM](https://rubyllm.com) supports works), and the same contract decides what is kept. The model proposes; code decides. Without a key, the deterministic rule-based parser does everything.

## Demo

A static snapshot of the example screens is published to GitHub Pages:
**https://henryzhangpku.github.io/rails-nl-screen/** (rebuilt on every push to `main` and each weekday
after the US close by `.github/workflows/pages.yml`).

It's read-only: Pages serves plain files, while the real app needs a Ruby server for the database,
background jobs and live updates. `bin/rails demo:export` (`lib/tasks/demo.rake`) runs each query in
`Screen::EXAMPLES` exactly as the job would, renders the same partials the live page uses with
`ApplicationController.render`, and writes HTML to `tmp/site/`. It uses real prices, or
labelled synthetic ones if the price source can't be reached.

## Setup

Needs Ruby 3.3 (see `.ruby-version`) and, for system tests, Chrome.

```sh
bin/setup          # bundle install, create the 4 SQLite databases, seed (prompt, evals, admin), start the server
bin/dev            # later: start the server (Puma + Solid Queue worker in one process)
open http://localhost:3000
```

The prompt editor is at http://localhost:3000/prompts; `bin/setup` seeds a development admin,
`admin@example.com` / `nl-screen-admin` (set `ADMIN_EMAIL` / `ADMIN_PASSWORD` before seeding anywhere else).

Useful switches:

```sh
MARKET_DATA=synthetic bin/dev          # offline: deterministic fake prices instead of Yahoo
DEEPSEEK_API_KEY=sk-... bin/dev                          # let DeepSeek propose the parse (still validated by code)
OPENAI_API_KEY=sk-... SCREEN_PARSER_MODEL=gpt-5 bin/dev   # or any other RubyLLM provider
```

Not every provider enforces the JSON schema the parser asks for. OpenAI's does. DeepSeek's chat API
doesn't (RubyLLM warns and falls back to plain JSON mode), so for DeepSeek the app uses its Responses API, which
takes the schema; set `SCREEN_PARSER_PROTOCOL=chat_completions` to go back. Either way the `Condition`
validations are the real boundary: anything off-schema is dropped, not trusted.

The first run of a screen makes ~100 requests to Yahoo's chart API (one per ticker); after that, bars come
from the `bars` table and each ticker is re-fetched at most once a day. If a ticker can't be fetched it is
listed as "No data" and skipped; use `MARKET_DATA=synthetic` to keep playing offline. (Stooq, the original
source, now puts a JavaScript bot check in front of its CSV downloads, so it was replaced.)

Tests:

```sh
bundle exec rspec --exclude-pattern "spec/system/**/*_spec.rb"   # models, parser, indicators (incl. parity with EquityScout), requests
bundle exec rspec spec/system   # happy path in headless Chrome (synthetic data, job run inline)
bin/rubocop && bin/brakeman
```

Edit the universe in `db/universe.txt`.

## What it understands

The rule-based parser, as screen-spec conditions (ratios are decimals: `-0.20` is 20%):

| You type | Becomes |
|---|---|
| `RSI under 30`, `rsi > 70`, `oversold`, `weekly RSI above 60` | `rsi14 < 30`, `rsi14 > 70`, `rsi14 < 30`, `rsi14_w > 60` |
| `MACD crossing up`, `MACD crossing above its signal on the weekly`, `MACD above its signal` | `macd_cross_up == true` (on the last session), `macd_cross_up_w == true`, `macd_hist > 0` |
| `price above the 200-day moving average`, `below SMA(50)`, `golden cross` | `close > sma200`, `close < sma50`, `sma50_above_sma200 == true` |
| `volume above its 20-day average`, `volume 2x its 50-day average` | `volume_ratio_20d > 1`, `volume_ratio_50d > 2` |
| `within 5% of the 52-week high`, `down at least 25% from the 52-week high` | `drawdown_52w >= -0.05`, `drawdown_52w <= -0.25` |
| `price between $20 and $100`, `trading under $50` | `close between [20, 100]`, `close < 50` |
| `up over the last 3 months`, `6-month return above 10%` | `mom_3m > 0`, `mom_6m > 0.1` |

Not screened, with the reason: an EMA, a MACD cross down, an RSI other than 14, a weekly moving average (the contract
has no field for them), and fields this demo doesn't compute because it only loads prices: revenue, margins, market
cap, short interest, returns vs a benchmark. With an API key, the LLM can propose any of the contract's 105 fields
and ranking; the same rules decide.

## Architecture in 10 lines

1. `ScreensController#create` calls `Screen.from_query(text)` and redirects to the screen's page.
2. `ScreenParser` (regex rules) or `ScreenParser::LLM` (JSON from any RubyLLM provider, prompt from PromptEngine) proposes a screen spec.
3. `ScreenSpec` is the contract (EquityScout's): `Screen#adopt` keeps what passes it and lists the rest as not screened.
4. The show page renders "Here's what I understood" and subscribes with `turbo_stream_from @screen`.
5. `RunScreenJob` (Solid Queue) calls `Screen#run`, which walks `Universe.symbols`.
6. `Bar.series_for(symbol)` returns cached bars, fetching via `MarketData::Yahoo` at most daily (marker in Solid Cache).
7. `Features.for(series)` computes every field from the bars (`Indicators` is the math; numbers match EquityScout's).
8. Each funnel step is `ScreenSpec.check`: pass, fail, or missing data; the symbol stops at the first that isn't a pass.
9. A survivor becomes a `Match` (its `after_create_commit` appends a row via Turbo Streams, over Solid Cable); when the run ends, matches are ranked.
10. Progress changes on `Screen` broadcast a Turbo 8 page refresh, so the status line is always current.

## What's new in Rails 8 vs 2007-era Rails (a map for Henry)

In 2007 you had Rails 1.2/2.0: Prototype + RJS, `script/generate`, `vendor/plugins`, Mongrel, `config/environment.rb`
doing everything, Capistrano, and memcached/Redis for anything async. Here is what replaced what, and where to
look in this repo.

| Then | Now | Where in this codebase |
|---|---|---|
| Prototype/RJS, `link_to_remote` | **Hotwire**: Turbo (Drive, Frames, Streams) + Stimulus. HTML over the wire, no JSON API, no SPA. | `app/views/screens/show.html.erb` (`turbo_stream_from`), `app/models/match.rb` (`broadcast_append_to`) |
| Partial page updates via RJS | **Turbo Streams** broadcast from models over WebSockets | `Match` appends rows; `Screen` sends `broadcast_refresh_to` |
| Full re-render or hand-written DOM patching | **Turbo 8 page refresh + morphing**: "re-fetch this page and morph the difference" | `turbo_refreshes_with method: :morph` in `screens/show.html.erb` |
| `javascripts/*.js` + inline JS | **Stimulus** controllers: small classes wired up with `data-` attributes | `app/javascript/controllers/examples_controller.js` (`data-action="examples#fill"`) |
| Sprockets (from 3.1), then Webpacker | **Importmaps** (no bundler, no Node) + **Propshaft** (just serves and fingerprints files) | `config/importmap.rb`, `app/javascript/application.js`, `app/assets/stylesheets/*.css` (one file per component) |
| `vendor/plugins`, `config.gem` | **Bundler** + `Gemfile.lock` | `Gemfile` (`ruby_llm`, `rspec-rails` added with `bundle add`) |
| `require_dependency`, const_missing magic | **Zeitwerk** autoloading: file path = constant name | `app/models/market_data/yahoo.rb` is `MarketData::Yahoo`; `app/models/screen_parser/llm.rb` is `ScreenParser::LLM` (one Zeitwerk inflection rule, in `config/initializers/inflections.rb`) |
| BackgrounDRb, `script/runner` from cron | **Active Job** + **Solid Queue** (jobs in a database table, no Redis) | `app/jobs/run_screen_job.rb`, `config/queue.yml`, `config/puma.rb` (`plugin :solid_queue`) |
| memcached | **Solid Cache** (cache in a SQLite/DB table) | `config/cache.yml`, `Rails.cache.fetch` in `app/models/bar.rb` |
| No WebSockets | **Action Cable** + **Solid Cable** (pub/sub through a DB table) | `config/cable.yml` |
| One database | **Multiple databases** per app | `config/database.yml`: primary, cache, queue, cable (each a SQLite file in `storage/`) |
| SQLite "for toys" | SQLite is a production default now (WAL, tuned connection settings) | everything; no database server to install |
| `attr_accessible` / `attr_protected` | **Strong parameters**, and in 8.0 `params.expect` | `ScreensController#create` |
| Status-ish string columns + constants | `enum` with query methods and scopes | `Screen` (`screen.done?`, `Screen.running`) |
| Serialized YAML text columns | Native **JSON columns** | `screens.notes`, `matches.details` |
| `find(:all, :conditions => ...)` | Chainable relations, `upsert_all` | `Bar.for_symbol`, `Bar.import` |
| `config/database.yml` passwords, `secrets.yml` | **Encrypted credentials** (`config/credentials.yml.enc` + a key you never commit) | Not used here (no secrets). `bin/rails credentials:edit` creates both files; `config/master.key` is gitignored. API keys are plain env vars. |
| Capistrano to a hand-built server | **Kamal** (Docker deploys to any host, zero-downtime) + **Thruster** (HTTP/2, caching proxy in front of Puma) | `config/deploy.yml`, `.kamal/`, `Dockerfile` |
| Test::Unit, fixtures only | Minitest is still the default; this app uses **RSpec** (rspec-rails): model, request and **system specs** in a real browser | `spec/models/*`, `spec/requests/*`, `spec/system/screens_spec.rb` |
| — | Ruby 3 niceties used here: `Data.define` value objects, endless methods (`def label = ScreenSpec.describe(to_spec)`) | `ScreenSpec::Field`, `PriceSeries::Point`, `ScreenParser::Result` |
| — | Built-in health check, Brakeman, RuboCop (omakase style), GitHub Actions CI | `/up` route, `.github/workflows/ci.yml` |
| `acts_as_authenticated` / restful_authentication plugins | **`bin/rails generate authentication`**: sessions, `has_secure_password`, a `Current` model and built-in `rate_limit`, generated as your own code | `app/controllers/concerns/authentication.rb`, `config/routes.rb` (route constraint guarding `/prompts`), `config/initializers/prompt_engine.rb` (the engine's own controllers require it too) |
| Engines (Rails 2.3, still rough) | **Mountable engines** with isolated namespaces, migrations and assets | `mount PromptEngine::Engine => "/prompts"` |
| `annotate_models` plugin | **annotaterb** (same idea, maintained): schema comments above each model, refreshed after `db:migrate` | `app/models/*.rb`, `.annotaterb.yml` |
| `rake` tasks, views only inside requests | Rake still, plus **rendering views anywhere** with `ApplicationController.render` | `lib/tasks/demo.rake` builds the Pages demo from the real partials |

Things that did **not** change much: MVC, ActiveRecord, migrations, `resources` routing, ERB, and "convention over
configuration". Read in this order: `config/routes.rb`, `app/controllers/screens_controller.rb`, `app/models/screen.rb`,
`app/models/screen_spec.rb`, `app/models/condition.rb`, `app/models/screen_parser.rb`, `app/models/features.rb`, then the views.

## Same product, two stacks

[EquityScout](https://github.com/henryzhangpku/equity-scout) is this product in Python (pandas, SEC fundamentals,
backtests, cited explanations). This app is the same product in Rails, sharing its contract rather than its code:

| | EquityScout (Python) | This app (Rails) |
|---|---|---|
| The contract | `src/scout/spec.py`: fields, units, operators, `validate()` | `app/models/screen_spec.rb`, a line-by-line port: same 105 fields, same messages |
| Plain English | `docs/ui.js` `plainCond` | `ScreenSpec.describe`, same wording ("Down at least 20% from 52-week high") |
| Indicators | `src/scout/indicators.py` (pandas) | `Indicators` + `Features` (plain Ruby); `spec/models/features_spec.rb` checks every value against EquityScout's own output |
| Funnel and ranking | `screen.py`: in / passed / failed / missing per step; weighted percentile ranks | `Screen#run`: the same funnel and ranking |
| Not screened | `unmapped: [{text, reason}]` | the same, shown under "Not screened" |
| Data | ~3,800 stocks, prices + SEC + FINRA | 100 large caps, prices only: other fields are refused with the reason |

Differences, on purpose: ranking ties go to the more liquid name (EquityScout uses market cap, not loaded here); a
proposed condition that breaks the contract is listed as not screened while the rest runs (EquityScout asks the model
for one correction, then stops the run).

## Not done (on purpose)

- One admin user, by design: there is no sign-up and no roles. Sign-in (30-day sessions) guards the prompt editor and deleting screens; running and browsing screens is public, with creating one rate limited. Kamal is configured but not deployed (the Pages snapshot is the demo), so there are no deploy secrets: before using it you'd run `bin/rails credentials:edit` and fill in `config/deploy.yml`.
- Prices are end-of-day, split-adjusted but not dividend-adjusted, from an unofficial API; this is a learning toy, not a trading tool.
