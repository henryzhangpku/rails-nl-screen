# rails-nl-screen

By [Henry Zhang](https://www.officialhenryzhang.com/) ([GitHub](https://github.com/henryzhangpku)). Live demo: https://henryzhangpku.github.io/rails-nl-screen/

A learning project: a plain-English stock screen in Rails 8 + Hotwire.

**Study notes:** [How the Rails 8 stack is used here](docs/ARCHITECTURE.md): layer by layer, with architecture diagrams, "In 2007 / Now" comparisons, a Rails 8 vs. Python + TypeScript comparison, and exercises.

Type something like

> RSI(14) under 30 on the daily, MACD crossing up, volume above its 20-day average, price above the 200-day moving average

and the app:

1. **parses** it into a typed, whitelisted screen (`Condition` rows: indicator, timeframe, operator, period, value),
2. **shows you what it understood** before any results,
3. **runs it in a background job** over ~100 large US tickers using free daily prices (Yahoo's chart API), cached in SQLite,
4. **streams each match into the results table live** (Turbo Streams), with the value of every condition and a one-line "why it matched".
5. **ranks the survivors**: each passing condition scores how far past its threshold the stock is (0 to 1; for a MACD cross, how recent it was), and matches are sorted by the average.
6. **keeps a searchable history** at `/screens`: search as you type, filter, sort and paginate inside a Turbo Frame, delete with a toast.
7. **treats the Claude prompt as data**: it lives in [PromptEngine](https://rubygems.org/gems/prompt_engine) (a mountable engine) at `/prompts`, where each edit becomes a numbered version and every screen records which version parsed it. The editor sits behind Rails 8's generated sign-in.

No React, no Node build, no paid data. Optional: if `ANTHROPIC_API_KEY` is set, Claude (`claude-sonnet-5-5`) *proposes* the typed screen as JSON, and the same whitelist validations decide what is kept. The model proposes; code decides. Without the key, the deterministic rule-based parser does everything.

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
bin/setup          # bundle install, create the 4 SQLite databases, start the server
bin/dev            # later: start the server (Puma + Solid Queue worker in one process)
open http://localhost:3000
```

The prompt editor is at http://localhost:3000/prompts; `bin/setup` seeds a development admin,
`admin@example.com` / `nl-screen-admin` (set `ADMIN_EMAIL` / `ADMIN_PASSWORD` before seeding anywhere else).

Useful switches:

```sh
MARKET_DATA=synthetic bin/dev          # offline: deterministic fake prices instead of Yahoo
ANTHROPIC_API_KEY=sk-ant-... bin/dev   # let Claude propose the parse (still validated by code)
```

The first run of a screen makes ~100 requests to Yahoo's chart API (one per ticker); after that, bars come
from the `bars` table and each ticker is re-fetched at most once a day. If a ticker can't be fetched it is
listed as "No data" and skipped; use `MARKET_DATA=synthetic` to keep playing offline. (Stooq, the original
source, now puts a JavaScript bot check in front of its CSV downloads, so it was replaced.)

Tests:

```sh
bundle exec rspec --exclude-pattern "spec/system/**/*_spec.rb"   # models, parser, indicators, requests
bundle exec rspec spec/system   # happy path in headless Chrome (synthetic data, job run inline)
bin/rubocop && bin/brakeman
```

Edit the universe in `db/universe.txt`.

## What it understands

| You type | Becomes |
|---|---|
| `RSI(14) under 30`, `rsi > 70`, `oversold`, `overbought` | `rsi` below/above value |
| `MACD crossing up` / `MACD bearish cross` | `macd` crosses_up/crosses_down (within the last 3 bars) |
| `price above the 200-day moving average`, `below the 21 day EMA`, `above SMA(50)` | `sma`/`ema` above/below |
| `volume above its 20-day average`, `volume 2x its 50-day average` | `volume` above/below N x average |
| `within 5% of the 52-week high`, `down at least 25% from the 52-week high` | `drawdown` below/above % |
| `price between $20 and $100`, `trading under $50` | `price` above/below |
| `weekly RSI above 60` | any of the above on weekly bars |

Anything it can't map is shown back as "Didn't understand ...", never silently guessed.

## Architecture in 10 lines

1. `ScreensController#create` calls `Screen.from_query(text)` and redirects to the screen's page.
2. `ScreenParser` (regex rules) or `ScreenParser::Claude` (structured JSON output, prompt rendered by PromptEngine) proposes condition attributes.
3. `Condition::SPECS` is the whitelist; Condition validations drop anything that doesn't fit.
4. The show page renders "Here's what I understood" and subscribes with `turbo_stream_from @screen`.
5. `RunScreenJob` (Solid Queue) calls `Screen#run`, which walks `Universe.symbols`.
6. `Bar.series_for(symbol)` returns cached bars, fetching via `MarketData::Yahoo` at most daily (marker in Solid Cache).
7. `PriceSeries` holds the bars (and resamples to weekly); `Indicators` is pure Ruby math over arrays.
8. `Condition#evaluate(series)` returns `passed`, the observed value, and a short reason.
9. When all conditions pass, a scored `Match` is created; its `after_create_commit` appends a table row via Turbo Streams (over Solid Cable).
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
| `require_dependency`, const_missing magic | **Zeitwerk** autoloading: file path = constant name | `app/models/market_data/yahoo.rb` is `MarketData::Yahoo`; `app/models/screen_parser/claude.rb` is `ScreenParser::Claude` |
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
| — | Ruby 3 niceties used here: `Data.define` value objects, endless methods (`def spec = SPECS[indicator]`) | `Condition::Evaluation`, `PriceSeries::Point`, `ScreenParser::Result` |
| — | Built-in health check, Brakeman, RuboCop (omakase style), GitHub Actions CI | `/up` route, `.github/workflows/ci.yml` |
| `acts_as_authenticated` / restful_authentication plugins | **`bin/rails generate authentication`**: sessions, `has_secure_password`, a `Current` model and built-in `rate_limit`, generated as your own code | `app/controllers/concerns/authentication.rb`, `config/routes.rb` (route constraint guarding `/prompts`) |
| Engines (Rails 2.3, still rough) | **Mountable engines** with isolated namespaces, migrations and assets | `mount PromptEngine::Engine => "/prompts"` |
| `annotate_models` plugin | **annotaterb** (same idea, maintained): schema comments above each model, refreshed after `db:migrate` | `app/models/*.rb`, `.annotaterb.yml` |
| `rake` tasks, views only inside requests | Rake still, plus **rendering views anywhere** with `ApplicationController.render` | `lib/tasks/demo.rake` builds the Pages demo from the real partials |

Things that did **not** change much: MVC, ActiveRecord, migrations, `resources` routing, ERB, and "convention over
configuration". Read in this order: `config/routes.rb`, `app/controllers/screens_controller.rb`, `app/models/screen.rb`,
`app/models/condition.rb`, `app/models/screen_parser.rb`, `app/models/indicators.rb`, then the views.

## Not done (on purpose)

- Sign-in only guards the prompt editor; screens are public. No deploy secrets: before using Kamal you'd run `bin/rails credentials:edit` and fill in `config/deploy.yml`.
- Prices are end-of-day, split-adjusted but not dividend-adjusted, from an unofficial API; this is a learning toy, not a trading tool.
