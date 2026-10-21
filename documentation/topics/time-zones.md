# Time zones

Show, edit and filter a table's datetimes in the reader's time zone; what a
time the clocks skip or repeat becomes; what a shared link means.

## The smallest example

A table is in UTC unless the page says otherwise. A table in your own
LiveView takes the zone as `time_zone`; the demo's dashboard gives each of
its tables the page's zone
([`demo/lib/demo_web/live/dashboard_live.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/live/dashboard_live.ex)):

<!-- source: demo/lib/demo_web/live/dashboard_live.ex -->
```heex
<AshDataTable.table
  id="dashboard-tasks"
  resource={Demo.Tracker.Task}
  heading={2}
  actor={@current_user}
  tenant={@current_tenant}
  time_zone={@time_zone}
/>
```

A zone other than UTC needs a time zone database. Elixir has none; add and
configure one
([`demo/config/config.exs`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/config/config.exs)):

<!-- sketch -->
```elixir
# mix.exs
{:tz, "~> 0.28"}
```

<!-- source: demo/config/config.exs -->
```elixir
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
```

`tzdata` works the same way (`Tzdata.TimeZoneDatabase`). `ash_data_table`
depends on neither.

**Try it:** `/dashboard` in the demo, in a browser whose zone is not UTC.
The line above the tables says "Times in Europe/Berlin" (or your zone; the
demo says nothing in UTC), and "Completed at" shows the times of that zone.

## Where the zone comes from

The page gives the zone, on the server. A table never takes it from the
browser by itself.

| Where the table is | How it is given the zone |
| --- | --- |
| A tag, `<AshDataTable.table>` | The attribute `time_zone`. |
| Attached with `AshDataTable.attach/4` | The option `time_zone`. |
| The page of a router line, `ash_data_table` | The socket assign `time_zone`, which the host's `on_mount` hook sets. |
| A nested table, a picker | The zone of the table it is in. |

Nil, nothing and `"UTC"` are UTC.

The router page finds the zone in the assign its domain names (as it finds
who is asking), and follows it when a hook assigns another while the page is
open. The default is `time_zone`; a domain names another with
`time_zone_assign`
([`demo/test/support/zone_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/zone_tables.ex)):

<!-- source: demo/test/support/zone_tables.ex -->
```elixir
table do
  authorize? false
  time_zone_assign :zone
end
```

The usual source is the person's account setting, which your `on_mount`
hook assigns. The demo takes the browser's zone instead, as a convenience:
`assets/js/app.js` sends it on connect, and an `on_mount` hook checks it
([`demo/lib/demo_web/zone.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/zone.ex)):

<!-- source: demo/assets/js/app.js -->
```javascript
params: {
  _csrf_token: csrfToken,
  // The browser's time zone, which the demo shows the tables' datetimes
  // in (`DemoWeb.Zone`): a convenience of the demo's, which the server checks.
  time_zone: Intl.DateTimeFormat().resolvedOptions().timeZone,
},
```

<!-- source: demo/lib/demo_web/zone.ex -->
```elixir
def on_mount(:default, _params, _session, socket) do
  zone =
    if connected?(socket),
      do: known(get_connect_params(socket)["time_zone"]),
      else: @utc

  {:cont, Phoenix.Component.assign(socket, time_zone: zone)}
end
```

What the browser sends is a claim: the hook takes a zone the database knows,
and UTC for anything else. The first render, before the browser connects,
is in UTC.

The router page's layout gets the assign too, so it can say which zone the
times are in. The table does not: a cell shows a time, not a zone.

## What the zone changes

Only datetimes that are instants: `:utc_datetime`, `:utc_datetime_usec`,
`:datetime`, and NewTypes of them.

| Where | What it is in the zone |
| --- | --- |
| A cell, a value inside a map cell, a footer summary (`:min`, `:max`) | The wall time there, in the form of the input: `2026-07-15T14:00:00`. |
| The editor of a cell, a field of the action panel, the argument line | The control starts with the wall time there. What is typed is a time there, and the action is given the instant it is, in UTC. |
| A filter: before, after, between | The times typed are times there. |
| What a generic action returns, when the table says it | The wall time there. |

`:naive_datetime`, `:date` and `:time` have no zone and are shown and given
as they are. Sorting is by the instant and does not change.

**Try it:** on `/tasks` in Berlin, open "Completed at" of a done task with
Enter, type `2031-07-15T16:30:15`, Enter. The cell shows that time. In a
browser that is in UTC the same task shows `2031-07-15T14:30:15`.

## Times that the clocks skip or repeat

Once a year an hour does not exist (clocks go forward), once a year an hour
happens twice (clocks go back). In Europe/Berlin in 2026:

| Typed | What it is |
| --- | --- |
| `2026-03-29T02:30` | Does not exist. A cell or a panel saves nothing and says "This time does not exist in Europe/Berlin." at the field. |
| `2026-10-25T02:30` | Happens twice. It is the earlier of the two, `2026-10-25T00:30:00Z`. |

The later of the two cannot be typed; it is shown as `2026-10-25T02:30:00`
like the earlier one.

A filter and the argument line save nothing: there a time that does not
exist means the first moment after the gap, 03:00.

## Filters and links

A filter on a datetime keeps what was typed: the URL holds the wall time,
not the instant (`?task[f][completed_at][between][from]=2026-03-29T00:00`).
The table turns it into instants when it reads.

So a shared link means the same wall time wherever it is opened: "completed
on 2026-03-29" sent from Berlin is 00:00 to 23:59:59 of that day, and opened
in New York it is 00:00 to 23:59:59 of their day.

A day is not always 24 hours: `2026-03-29T00:00` to `2026-03-29T23:59:59` in
Berlin is 23 hours, from `2026-03-28T23:00:00Z`. The table asks Ash for
exactly those instants.

## Mistakes

A name that is no zone is an `ArgumentError` naming where it was given: the
tag's `time_zone` when it renders, `AshDataTable.attach/4`'s `time_zone`
when called, or the router page's assign and domain.

A zone other than UTC without a time zone database is an `ArgumentError`
that says what to add. UTC needs no database.

## Edge cases

- **Text with its own offset** (`2026-07-15T14:00:00+02:00`) already names
  its instant and goes to Ash as typed. The controls never send one.
- **A date alone** typed into a datetime filter is the first moment of that
  day in the zone.
- **A value of a map that declares no fields** shows a `DateTime` it holds
  in the zone too.
- **A summary `:count`** is a number and does not change.
- **Live updates** carry keys, not times; the rows they bring show in the
  reader's zone.

## Things people trip over

- **"Every time is two hours off."** The page gives no zone, so the table
  is in UTC. Give the tag or `attach/4` its `time_zone`, or set the assign
  on the socket for the router page.
- **"The first render shows UTC."** The demo learns the zone when the
  browser connects. A zone from the person's settings is there at once.
- **`Calendar.UTCOnlyTimeZoneDatabase`** is Elixir's default: it knows UTC
  and nothing else. Configure `tz` or `tzdata`.
- **"UTC" and "Etc/UTC"** are the same zone to the table. Other names of
  UTC (`"Etc/Zulu"`) need a database.

## Not in the first version

- **Locale formats** (`15.07.2026 14:00`, a 12-hour clock): times are
  written in the input's ISO-like form; deferred with locale support.
- **The zone in each cell or in the header.** The page says it once, if it
  wants.
- **A zone per column,** or a column of a resource that says in which zone
  its times are.
- **Choosing the later of a repeated hour.**
- **The browser's zone in the library itself.** It is the browser's claim;
  the demo shows how a host takes it.

Further work on what a table offers is in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
