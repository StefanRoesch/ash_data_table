# Localize and `ash_localize`: what exists, and what `ash_table` should do

Researched 2026-10-09. Marks used below: **[ran]** I ran it in a scratch project, **[source]** I read it in the package's code or docs, **[memory]** not checked again here.

## Verdict

1. **`localize` is real and ready.** Hex package by Kip Cole, version 1.3.0, stable since 1.0.0 on 2026-07-30. It is the successor of the whole `ex_cldr_*` family, by the same author. It is light: one new package for a host that already has Gettext, pure Elixir, 7.5 s to compile.
2. **`ash_localize` is not published.** It is not on Hex. It is a GitHub repository, `team-alembic/ash_localize`, version 0.1.0, marked "early development", last commit 2026-08-02. Its numeric types cannot be edited from a web form today.
3. **So: build number and date formatting on `localize` now. Leave the `ash_localize` types out** until the package is on Hex. Show money (`ash_money`, which is published) read-only.
4. **Keep the native inputs for editing.** Locale-aware parsing exists, but it misreads silently when the typed text and the locale disagree.

The owner's memory, corrected: "Localize was CLDR before" is right for `localize` (it replaces `ex_cldr`). There never was an `ash_cldr`; `ash_localize` is new (repository created 2026-05-21).

## 1. What exists

Versions read: `localize` 1.3.0, `calendrical` 1.3.0, `ex_money` 6.2.1, `ex_money_sql` 2.1.0, `ash_money` 0.2.6, `ash` 3.34.6, `ash_localize` commit `c441909`. Figures from the Hex API on 2026-10-09.

| Package | On Hex | Latest | Maturity | Who | What it is |
| --- | --- | --- | --- | --- | --- |
| `localize` | yes | 1.3.0, 2026-09-21 | 1.0.0 on 2026-07-30; 66 releases since 2025-04; 201k downloads | Kip Cole | Numbers, dates, units, lists, parsing of numbers. Needs Elixir 1.17, OTP 26, `gettext ~> 1.0`, `decimal ~> 2.0 or ~> 3.0` |
| `calendrical` | yes | 1.3.0, 2026-08-26 | 9.7k downloads | Kip Cole | Parsing of dates and times; pulls `astro` and `geo` |
| `localize_web` | yes | 1.1.0, 2026-08-10 | 37k downloads | Kip Cole | Plug and `on_mount` helper that set the locale for Localize and Gettext together |
| `localize_number_inputs`, `localize_datetime_inputs` | yes | 0.2.x | under 600 downloads each | Kip Cole | LiveView inputs with a JavaScript library (AutoNumeric) |
| `ex_money` | yes | 6.2.1, 2026-08-04 | 3.1M downloads | Kip Cole | Money. Since 6.0 it depends on `localize`, no longer on `ex_cldr` |
| `ash_money` | yes | 0.2.6, 2026-06-08 | pre-1.0; 27 releases; 172k downloads | ash-project | `AshMoney.Types.Money`. 0.2.6 needs `ex_money ~> 6.0` |
| **`ash_localize`** | **no** (Hex and HexDocs answer 404) | 0.1.0, unreleased | 6 stars, no tags, quiet since 2026-08-02 | Josh Price (team-alembic), one commit by Kip Cole | Ash types and calculations on top of `localize`. Needs `ash ~> 3.30` |
| `ex_cldr`, `ex_cldr_numbers`, `ex_cldr_dates_times`, `ex_cldr_units` | yes | 2.47.5 and others | 3 to 8M downloads each | Kip Cole | The old family. Its README: supported "until December 31, 2027", move to `localize` |

Sources: `https://hex.pm/api/packages/<name>`; `https://github.com/team-alembic/ash_localize` (README, `mix.exs`, `docs/PLAN.md`); `https://github.com/elixir-cldr/cldr` README; `ex_money` CHANGELOG 6.0.0-rc.0; `localize` guide `guides/migration.md`.

How `localize` differs from `ex_cldr` **[source]**: no backend module and nothing generated at compile time. Locale data is loaded at run time. Only `en` ships in the package; every other locale is a file of 0.5 to 0.8 MB fetched with `mix localize.download_locales` at build time.

Oddities of `ash_localize` **[source]**: its `mix.exs` names `github.com/elixir-localize/ash_localize` as its home, which answers 404. Its README lists the Phoenix, Postgres, GraphQL and JSON:API parts as "not yet built".

## 2. The API a table would call

All formatting functions return `{:ok, text}` or `{:error, exception}`; each has a `!` twin. All take `locale:`; without it they use the process locale. **[ran]** (the docstrings say "default `:en`", which is wrong).

| Value | Call | Options that matter |
| --- | --- | --- |
| integer, float, Decimal | `Localize.Number.to_string(n, opts)` | `format: :percent`, `currency: :EUR`, `fractional_digits:`, `max_fractional_digits:`, `number_system:` |
| Date | `Localize.Date.to_string(d, opts)` | `format: :short \| :medium \| :long \| :full`, or a skeleton such as `:yMd` |
| DateTime, NaiveDateTime | `Localize.DateTime.to_string(dt, opts)` | same, plus `date_format:`, `time_format:` |
| Time | `Localize.Time.to_string(t, opts)` | `format:` |
| list | `Localize.List.to_string(list, opts)` | |
| unit | `Localize.Unit.to_string(unit, opts)` | `format: :long \| :short \| :narrow` |
| money | `Money.to_string(money, opts)`, and plain `to_string(money)` | |
| anything of the above | `Localize.to_string(value, opts)` | a protocol, `Localize.Chars` |
| typed number | `Localize.Number.Parser.parse(text, locale:, number: :integer \| :float \| :decimal)` | `lenient:` |
| typed date, datetime, time | `Localize.Date.parse/2`, `Localize.DateTime.parse/2`, `Localize.Time.parse/2` | need `calendrical` installed |
| typed money | `Money.parse(text, locale:, default_currency:)` | |

### The locale

- `Localize.put_locale/1` and `Localize.get_locale/0` use the process dictionary, like Gettext. `Localize.with_locale/2` sets it for one function. **[source]** `lib/localize.ex`
- **Gettext and Localize do not know of each other.** After `Localize.put_locale("de")`, `Gettext.get_locale()` is still `"en"`, and the reverse. **[ran]** A host sets both. `localize_web` has a helper for it: `Localize.Plug.put_locale_from_session(session, gettext: MyApp.Gettext)`. **[source]**
- Gettext-style names are accepted: `"de_AT"` is understood. **[ran]**
- Default when nothing is set: the environment variable `LOCALIZE_DEFAULT_LOCALE`, then `config :localize, default_locale:`, then **the server's `LANG`**, then `:en`. **[source]** README

### Two traps with locale data **[ran]**

A locale whose file was not downloaded falls back to a neutral locale and still answers `{:ok, ...}`. With `localize` installed and nothing else done:

```
Localize.Number.to_string(1234.5, locale: :de)        {:ok, "1,234.5"}
Localize.Date.to_string(~D[2026-10-09], locale: :de)  {:ok, "2026 M10 9"}
```

Only a debug log line says so. And with `supported_locales: [:en, :de, ...]` configured, a locale outside the list becomes English without an error:

```
Localize.put_locale(:ja)                              {:ok, <the :en locale>}
```

### Real outputs **[ran]**

` ` is a no-break space; `‎` and `‏` are direction marks.

| Call | `en` | `de` | `ar` |
| --- | --- | --- | --- |
| integer 1234567 | `1,234,567` | `1.234.567` | `1,234,567` |
| float 1234567.891 | `1,234,567.891` | `1.234.567,891` | `1,234,567.891` |
| Decimal 1234.50 | `1,234.5` | `1.234,5` | `1,234.5` |
| Decimal 1234.5678 | `1,234.568` | `1.234,568` | `1,234.568` |
| -1234.5 | `-1,234.5` | `-1.234,5` | `‎-1,234.5` |
| 0.4567 as percent | `46%` | `46 %` | `46‎%‎` |
| 1234.5 EUR | `€1,234.50` | `1.234,50 €` | `‏1,234.50 €` |
| date, medium | `Oct 9, 2026` | `09.10.2026` | `09‏/10‏/2026` |
| date, short | `10/9/26` | `09.10.26` | `9‏/10‏/2026` |
| date, long | `October 9, 2026` | `9. Oktober 2026` | `9 أكتوبر 2026` |
| time, medium | `2:05:09 PM` | `14:05:09` | `2:05:09 م` |
| datetime, medium | `Oct 9, 2026, 2:05:09 PM` | `09.10.2026, 14:05:09` | `09‏/10‏/2026، 2:05:09 م` |
| UTC datetime, long | `October 9, 2026, 2:05:09 PM UTC` | `9. Oktober 2026, 14:05:09 UTC` | `9 أكتوبر 2026، 2:05:09 م UTC` |
| Berlin datetime, long | `… 4:05:09 PM GMT+2` | `… 16:05:09 MESZ` | `… 4:05:09 م غرينتش+2` |
| list a, b, c | `a, b, and c` | `a, b und c` | `a وb وc` |
| 3.5 kilometer | `3.5 kilometers` | `3,5 Kilometer` | `3.5 كيلومتر` |
| Money EUR 1234.50 | `€1,234.50` | `1.234,50 €` | `‏1,234.50 €` |

More, same run:

```
de-CH  1234567.891                              "1'234'567.891"
hi     1234567                                  "12,34,567"
ar     1234.5 with locale "ar-u-nu-arab"        "١٬٢٣٤٫٥"
hi     1234.5 with number_system: :native       "१,२३४.५"
de     Decimal 1234.5678, max_fractional_digits: 10   "1.234,5678"
de     Decimal 1234.50, fractional_digits: 2          "1.234,50"
de     1234567 with format: "0"                       "1234567"
```

What this shows:

- **Decimals are rounded to three places and trailing zeros are dropped** unless the digits are given. A table must pass them, or it shows a value the record does not have.
- **Integers get grouping.** An ID 1234567 becomes `1,234,567`.
- **The medium datetime shows no zone.** Only `:long` and `:full` do.
- **Arabic uses Latin digits by default** in the CLDR data read here (version 48.2). Arabic-Indic digits need the `-u-nu-arab` locale extension or `number_system:`.
- Speed, 10,000 calls each: about 26 µs per number, 16 µs per date, 30 µs per datetime. A page of 100 rows by 30 number columns is about 80 ms of formatting.

### Parsing what a person types **[ran]**

It works when the text matches the locale, and round trips of formatted values came back exact in `en`, `de`, `de-CH`, `fr`, `ar`, `hi`. It is strict about the locale and does not notice the other convention:

```
Parser.parse("1.234,56", locale: :de)   {:ok, 1234.56}
Parser.parse("1.234,56", locale: :en)   {:ok, 1.23456}      wrong, no error
Parser.parse("1,234.56", locale: :de)   {:ok, 1.23456}      wrong, no error
Parser.parse("1.234",    locale: :de)   {:ok, 1234}         a person may have meant 1.234
Parser.parse("1234.5",   locale: :de)   {:error, ...}
Parser.parse("1,23",     locale: :en)   {:ok, 123}
Parser.parse("45%",      locale: :en)   {:error, ...}       no percent
Parser.parse("١٬٢٣٤٫٥",  locale: :ar)   {:error, ...}       needs number_system: :arab

Localize.Date.parse("09.10.2026", locale: :de)   {:ok, ~D[2026-10-09]}
Localize.Date.parse("09.10.2026", locale: :en)   {:ok, ~D[2026-09-10]}   month and day swapped
Localize.Date.parse("31.02.2026", locale: :de)   {:error, %Calendrical.DateParseError{}}
Localize.DateTime.parse("09.10.2026, 14:05", locale: :de)   {:ok, ~N[2026-10-09 14:05:00]}
```

Date parsing needs `calendrical`, which brings `astro` (with an 8.8 MB file of planet positions) and `geo`.

### Dependency weight **[ran]**

| Added to a project | New packages | Compile | Other |
| --- | --- | --- | --- |
| `localize` | `localize`, plus `decimal`, `gettext`, `expo`, `nimble_parsec`, which `ash_table` already has | 7.5 s on 12 cores | 6.1 MB of source and data; no NIF unless asked for; no download at compile time; one 0.5 to 0.8 MB file per locale from `mix localize.download_locales` |
| + `calendrical` | `calendrical`, `astro`, `geo` | not timed alone | 8.8 MB ephemeris file inside `astro` |
| + `ash_money` | `ash_money`, `ex_money`, and in practice `ex_money_sql`, `localize_sql`, `ecto_sql`, `db_connection` | not timed alone | |

## 3. The types

### `ash_localize` (unpublished) **[source]** `lib/ash_localize/types/*.ex`, `code_type.ex`, `quantity_type.ex`, `unit_type.ex`; casts and queries **[ran]** on the ETS data layer

| Type (short name) | Value in Elixir | Stored as | Constraints | Casts text from a form? | Sort and filter |
| --- | --- | --- | --- | --- | --- |
| `Locale` (`:locale`) | `"en-US"` | string | none | yes: `"en-us"` becomes `"en-US"` | as a string |
| `Territory` (`:territory`) | `"DE"` | string | none | yes: `"de"` becomes `"DE"`; `"Germany"` is refused | as a string |
| `Subdivision` (`:subdivision`) | `"usca"` | string | `territory` | yes | as a string |
| `Timezone` (`:timezone`) | `"Europe/Berlin"` | string | none | yes: `"CET"` becomes `"Europe/Brussels"` | as a string |
| `CurrencyCode` (`:currency_code`) | `"EUR"` | string | none | yes | as a string |
| `Count` (`:count`) | integer | integer | `of`, `min` (0), `max`, `zero?` | **no**: `"5"` gives "is not an integer count" | works |
| `Ordinal` (`:ordinal`) | integer | integer | `of`, `min` (1), `max` | **no** | works |
| `Percentage` (`:percentage`) | Decimal, 0.75 means 75% | decimal | `min` (0), `max` (1) | **no**: `"0.75"` gives "is not a number" | works |
| `Ratio` (`:ratio`) | Decimal | decimal | `min` (0), `max` (1) | **no** | works |
| `Score` (`:score`) | Decimal | decimal | `of`, `min`, `max` | **no** | works |
| `Rating` (`:rating`) | Decimal | decimal | `out_of` (required), `of`, `min` | **no** | works |
| `Unit` (`:unit`) and 17 named ones: `Length`, `Distance`, `Mass`, `Speed`, `Acceleration`, `Force`, `Volume`, `Area`, `Temperature`, `Energy`, `Power`, `Pressure`, `Angle`, `Frequency`, `Digital`, `ElectricCurrent`, `Voltage` | `%Localize.Unit{value:, name:}` | one number, in the base unit | `base_unit`, `storage`, `category` | **no**: `"12.5"` gives "is not a valid quantity". Accepts a number, `{3, "kilometer"}`, `%{"value" => 3, "unit" => "kilometer"}` | sorting works; `>` works; `speed == 100` found nothing |
| `PersonName` (`:person_name`) | `%Localize.PersonName{}` | map | none | a map of name parts | not tried |
| `PhoneNumber` (`:phone_number`) | `%Localize.PhoneNumber.Number{}` | E.164 string | none | a string | not tried |
| `PostalAddress` (`:postal_address`) | `%Localize.Address.Address{}` | map | none | a map of parts | not tried |

The last three exist only when their own package is installed (`localize_person_names`; `localize_phone_number` and `localize_address` need the C libraries libphonenumber and libpostal). I did not install them.

It also has `AshLocalize.format/2`, fifteen `Format*` calculations, `AshLocalize.translate_error/2`, and a rule for the locale that deliberately ignores the process dictionary (argument, then Ash context, then actor, then a configured default).

What a table would need for them:

- The five code types are text. They could be edited as text today, or later with a list of names (`Localize.Territory.display_name/1`).
- The six number types are numbers, with a format of their own (percent, "3rd", "3⁄4"). **A form cannot save them**: `AshPhoenix.Form.submit` with `"5"` fails **[ran]**. The built-in Ash number types accept text; these do not. That is a gap upstream.
- A unit is a number with a unit name. Editing means a number in the base unit, or a number and a unit picker. Text is refused here too.
- `Localize.Unit` has no `String.Chars`. `ash_table` today would show it as `%Localize.Unit{...}`. **[ran]**

### `ash_money`, the incumbent for money **[source]** `lib/ash_money/types/money.ex`; **[ran]**

| | |
| --- | --- |
| Value | `%Money{currency: :EUR, amount: Decimal}` from `ex_money` |
| Stored as | a Postgres composite type `money_with_currency` by default; a map with `storage_type: :map` |
| Constraints | `storage_type`, `ex_money_opts`, `min`, `max` |
| Casts | `%Money{}`, `{currency, amount}`, `%{"amount" => …, "currency" => …}`, and text such as `"€12.50"` |
| Sort and filter | on ETS with two currencies it raises "Cannot compare monies with different currencies". Postgres not tried |
| Needs | `ex_money_sql` in practice. Without it every cast except of a `%Money{}`, and every write, raises `UndefinedFunctionError` for `Money.Ecto.Map.Type` |
| Shown | `to_string(money)` already follows the Localize process locale: `"€1,234.50"`, in `de` `"1.234,50 €"` |

**The money trap [ran].** `ex_money` reads the amount with the Localize process locale, also inside the map:

```
Localize.put_locale("de")
cast %{"amount" => "1234.50", "currency" => "EUR"}    Money.new(:EUR, "123450")     a hundred times too much
cast "12.50"  (process locale en)                     Money.new(:USD, "12.50")      currency guessed from the locale
Localize.put_locale("en")
cast %{"amount" => "1.234,50", "currency" => "EUR"}   Money.new(:EUR, "1.23450")
cast %{"amount" => Decimal.new("1234.50"), "currency" => "EUR"}   correct in every locale
```

A native number input sends `1234.50`. Passed on as text in a German session it is saved as 123450. A money editor must send the amount as a `Decimal`.

## 4. Optional dependency: how it is done

### How Ash's libraries do it **[source]**

All of them use a block decided when the library is compiled, around a whole module or function:

| Where | What |
| --- | --- |
| `ash_reference/ash_json_api/lib/ash_json_api/controllers/open_api.ex:5` with `mix.exs:159` | `if Code.ensure_loaded?(OpenApiSpex) do defmodule … end`; `{:open_api_spex, "~> 3.16", optional: true}` |
| `ash_reference/ash_json_api/lib/ash_json_api/router.ex:99` | a function `spec/0` that exists only when the optional part was compiled |
| `ash_reference/ash_graphql/lib/error.ex:214` | a protocol implementation only when `AshAuthentication` is there |
| `ash_table/deps/ash_phoenix/lib/ash_phoenix/inertia/error.ex:5` with `mix.exs:156` | the same for `inertia` |
| `ash_money/lib/ash_money/types/money.ex:145, 421, 448, 460` | the same for `ex_money_sql`, `ash_json_api`, `ash_graphql`, `ash_postgres` |
| `ash_table/lib/mix/tasks/ash_table.install.ex:1` | `ash_table` itself, for Igniter |

Neither `ash_json_api` nor `ash_graphql` has a CI job that compiles without its optional dependencies (searched their `.github` folders for `no-optional-deps`; the other checkouts were not searched).

`localize` itself uses the other way, decided on each call, for `calendrical`: `Module.concat/1` plus `Code.ensure_loaded?/1` (`deps/localize/lib/localize/optional_dependency.ex`).

### What I tried **[ran]** (Elixir 1.19.4, a scratch library with `{:localize, "~> 1.3", optional: true}`, used by a scratch host as a git dependency)

| Question | Result |
| --- | --- |
| Host adds `localize` later. Is the library recompiled? | Yes, by itself. The compile-time block switches to "with". |
| Host removes `localize` again. | **Not recompiled.** The library still holds the "with" code and would raise `UndefinedFunctionError` until `mix deps.compile <lib> --force`. |
| Library names `Localize.Number` in a call guarded only at run time; compiled without `localize`. | Warning "Localize.Number.to_string!/2 is undefined", so `--warnings-as-errors` fails. |
| The same with `@compile {:no_warn_undefined, [Localize, Localize.Number]}`. | No warning; works with and without. |
| `mix compile --no-optional-deps --warnings-as-errors` in the library. | **Only honest from an empty `_build`.** With an earlier build present, the check `Code.ensure_loaded?(Localize)` was still true and the "with" code was compiled. |
| `mix test --no-optional-deps`. | Not an option of `mix test`. This works instead, from an empty `_build/test`: `MIX_ENV=test mix compile --no-optional-deps`, then `mix test --no-compile --no-deps-check`. |

## 5. Input controls

Facts:

- `<input type="date">` and `type="datetime-local"` always send `2026-10-09` and `2026-10-09T14:05`. What the person sees is "formatted based on the locale of the user's browser" (MDN, `input/date`); for `datetime-local`, "as reported by their operating system" (MDN, `input/datetime-local`). The page cannot set it. **[source]**
- `<input type="number">` always sends digits with a dot. It shows no grouping. Which decimal separator a person may type depends on the browser: Chrome follows the browser's language, Firefox follows the page's `lang` attribute. **[memory]**

Where the app's language and the browser can disagree, for a person who chose German in the app on an English browser:

| | Cell (app locale) | Editor (browser) |
| --- | --- | --- |
| date | `09.10.2026` | `10/09/2026` |
| datetime | `09.10.2026, 14:05:09` | `10/09/2026, 02:05:09 PM` |
| number | `1.234,5` | `1234.5` |

The same disagreement appears in the filter row. Nothing wrong is saved: the value sent is the same in every locale. It is only a difference in looks, and for most people the browser and the chosen language agree.

What others do **[memory]**: Airtable, Baserow, NocoDB and Grist use text editors and their own date pickers, with the format set per field. Google Sheets has one locale per document. None relies on the browser's locale. That is the full solution, and a large one: a date picker, a number mask, and the parsing whose silent misreadings are shown in part 2.

Least surprising for `ash_table`: **show in the app's locale, edit in the native input.** A person never types a value that is then read in the wrong convention, the pickers and phone keyboards keep working, and nothing new has to be built. Setting `lang` on the table to the app's locale is a small help for Firefox.

## Recommendation for `ash_table`

### Format through Localize

| Cell type | Call | Note |
| --- | --- | --- |
| number, integer | `Localize.Number.to_string/2` | grouping. Not for primary keys and foreign keys: an ID is not a quantity |
| number, Decimal | the same with `fractional_digits:` set to the value's own scale | else it is rounded to three places and loses trailing zeros |
| number, float | the same with a high `max_fractional_digits:` | |
| date | `Localize.Date.to_string/2`, `:medium` | `09.10.2026`, `Oct 9, 2026` |
| datetime | `Localize.DateTime.to_string/2`, `:medium` | to the second and without a zone, as today |
| array of these | each value as above, joined as today | `Localize.List` would add "and", which is wrong for a list of values |
| other: a struct | `Localize.to_string/2` when the struct implements `Localize.Chars` | makes `Money` and `Localize.Unit` readable at no cost |

Locale: the Localize process locale, read by default by every call above. The host sets it beside `Gettext.put_locale/1`; the demo's `DemoWeb.Locale` gains one line. The alternative is to pass `locale: Gettext.get_locale(backend)` on every call, so one setting drives both; it rules out German text with Swiss number formats, and it is not how Localize or `ex_money` work.

One change in `AshTable.Format`: `input/2` today falls through to `format/2` for numbers, dates and datetimes. They must part: `format/2` is what the cell shows (localized), `input/2` stays what the native input holds (plain). `AshTable.Edit` compares what was typed with `input/2`, so it needs no change.

### Cell types of the added types

| Type | Now | When it is taken up |
| --- | --- | --- |
| `AshMoney.Types.Money` | shown through `Localize.Chars`, read-only | a `:money` cell: a number input for the amount, a select for the currency; send the amount as a `Decimal`, never as text (the money trap) |
| `ash_localize` code types | nothing; they show as text already | `:text`, or `:enum` with names from Localize |
| `ash_localize` number types | nothing; they show as plain numbers | `:number` with a format; needs upstream to accept text |
| `ash_localize` units | readable through `Localize.Chars` | number in the base unit, unit shown beside it |
| person name, address, phone | nothing | like an embedded resource; phone as text |

### Wiring

1. `mix.exs`: `{:localize, "~> 1.0", optional: true}`. Note: it needs `gettext ~> 1.0`; `ash_table` allows 0.26.
2. One module holds every call to Localize. I recommend the check on each call (`Code.ensure_loaded?(Localize)`) with `@compile {:no_warn_undefined, …}`, not the compile-time block the Ash libraries use. Reason: it survives the host removing `localize`, and the plain path stays compiled and testable in the same build. The compile-time block is the Ash precedent and also works; its one weakness is the removal case in the table of part 4.
3. **Add a switch: `config :ash_table, localize: true`.** The decided rule is "installed means on". But `ex_money` 6 and `ash_money` 0.2.6 bring `localize` along. A host that adds money would see its tables change to grouped numbers, in the server's `LANG` if it never set a Localize locale. This is the one point where I recommend departing from the decision; the owner should confirm.
4. Tests: with the switch, both paths run in the normal suite. Add one CI job from an empty `_build`: `mix compile --no-optional-deps --warnings-as-errors`. It also covers Igniter.
5. Documentation for the host: set `supported_locales`, run `mix localize.download_locales` in the build, set the Localize locale where the Gettext locale is set. Without the download the table shows `2026 M10 9`.

### Out of this part

- Parsing typed text by locale; text inputs in place of the native ones.
- Every `ash_localize` type, until the package is on Hex. Worth an issue upstream: its number and unit types refuse text, so no web form can save them.
- Editing money.
- Time zones, time of day, durations (already out of slice 4).
- Non-Latin digits, other calendars, per-column formats (percent, currency, digits).
- Localized values in the filter row.

## Not verified

- Browser behaviour of `type="number"` and what Airtable, Baserow, NocoDB, Grist and Google Sheets do: from memory.
- `ash_localize` on Postgres; its person name, phone and address types; its calculations. Its own test suite was not run.
- `ash_money` sorting and filtering on Postgres.
- Whether `ash_localize` will be published, and under which organisation.
- Why `speed == 100` found nothing and why `country == "de"` did not match `"DE"` on ETS; seen, not investigated.
- `localize` on OTP 26 (needs `json_polyfill` per its README); run here on OTP 28.
