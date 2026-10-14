# Time zones

After reading this guide you can show, edit and filter the datetimes of a
table in the time zone of the person who reads it. You also know what a
time that the clocks skip or repeat becomes, and what a shared link means.

## The smallest example

A table is in UTC unless the page says otherwise. A table you place in a
LiveView is given the zone as `time_zone`. The demo's dashboard gives each
of its tables the zone of the page
([`demo/lib/demo_web/live/dashboard_live.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo_web/live/dashboard_live.ex)):

<!-- source: demo/lib/demo_web/live/dashboard_live.ex -->
```elixir
<AshDataTable.table
  id="dashboard-tasks"
  resource={Demo.Tracker.Task}
  heading={2}
  actor={@current_user}
  tenant={@current_tenant}
  time_zone={@time_zone}
/>
```

A zone other than UTC needs a time zone database. Elixir brings none; add
one to the application and configure it
([`demo/config/config.exs`](https://github.com/StefanRoesch/ash_table/blob/main/demo/config/config.exs)):

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

The zone is the page's to give, on the server. A table never takes it from
the browser by itself.

| Where the table is | How it is given the zone |
| --- | --- |
| Placed with `<AshDataTable.table>` | The attribute `time_zone`. |
| Mounted with `ash_data_table` in the router | The socket assign `time_zone`, which the host's `on_mount` hook sets. |
| A nested table, a picker | The zone of the table it is in. |

Nil, nothing and `"UTC"` are UTC.

A mounted table finds the zone in the assign its domain names, as it finds
who is asking. The default name is `time_zone`; a domain names another
with `time_zone_assign`
([`demo/test/support/zone_tables.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/test/support/zone_tables.ex)):

<!-- source: demo/test/support/zone_tables.ex -->
```elixir
table do
  authorize? false
  time_zone_assign :zone
end
```

The usual source is the person: a setting of their account, which your
`on_mount` hook assigns. The demo takes the zone of the browser instead, as
a convenience: `assets/js/app.js` sends it when the LiveView connects, and
an `on_mount` hook checks it
([`demo/lib/demo_web/zone.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo_web/zone.ex)):

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

What the browser sends is a claim. The hook takes a zone that the time zone
database knows, and UTC for anything else. The first render, before the
browser has connected, is in UTC.

The layout of a mounted table is given the assign as well, so it can say
which zone the times are in. The table itself does not say it: a cell
shows a time, not a zone.

## What the zone changes

Only datetimes that are instants: `:utc_datetime`, `:utc_datetime_usec`,
`:datetime`, and NewTypes of them.

| Where | What it is in the zone |
| --- | --- |
| A cell, a value inside a map cell, a footer summary (`:min`, `:max`) | The wall time there, in the form of the input: `2026-07-15T14:00:00`. |
| The editor of a cell, a field of the action panel, the argument line | The control starts with the wall time there. What is typed is a time there, and the action is given the instant it is, in UTC. |
| A filter: before, after, between | The times typed are times there. |
| What a generic action returns, when the table says it | The wall time there. |

A `:naive_datetime` has no zone and is shown and given as it is. So are a
`:date` and a `:time`. Sorting is by the instant and does not change.

**Try it:** on `/tasks` in Berlin, open "Completed at" of a done task with
Enter, type `2031-07-15T16:30:15`, Enter. The cell shows that time. In a
browser that is in UTC the same task shows `2031-07-15T14:30:15`.

## Times that the clocks skip or repeat

Once a year the clocks go forward and an hour does not exist; once a year
they go back and an hour happens twice. In Europe/Berlin in 2026:

| Typed | What it is |
| --- | --- |
| `2026-03-29T02:30` | Does not exist. A cell or a panel saves nothing and says "This time does not exist in Europe/Berlin." at the field. |
| `2026-10-25T02:30` | Happens twice. It is the earlier of the two, `2026-10-25T00:30:00Z`. |

The later of the two cannot be typed. It is shown as `2026-10-25T02:30:00`
like the earlier one.

In a filter and in the argument line nothing is saved: a time that does
not exist there means the first moment after the gap, 03:00.

## Filters and links

A filter on a datetime keeps what was typed: the URL holds the wall time,
not the instant (`?task[f][completed_at][between][from]=2026-03-29T00:00`).
The table turns it into instants when it reads.

So a shared link means the same wall time wherever it is opened. A person
in Berlin who sends "completed on 2026-03-29" sends 00:00 to 23:59:59 of
that day; a person in New York who opens the link sees 00:00 to 23:59:59 of
their day.

A day is not always 24 hours. Between `2026-03-29T00:00` and
`2026-03-29T23:59:59` in Berlin is 23 hours, from `2026-03-28T23:00:00Z`.
The table asks Ash for exactly those instants.

## Mistakes

A name that is no zone is an `ArgumentError` when the table is rendered,
naming where it was given: the `time_zone` of `<AshDataTable.table>`, or the
assign and the domain of a mounted table.

A zone other than UTC without a time zone database is an `ArgumentError`
that says what to add. UTC needs no database.

## Edge cases

- **Text with an offset of its own** (`2026-07-15T14:00:00+02:00`) names
  its instant already and is given to Ash as it was typed. The controls
  never send one.
- **A date alone** typed into a datetime filter is the first moment of that
  day in the zone.
- **A value of a map that declares no fields** shows a `DateTime` it holds
  in the zone too.
- **A summary `:count`** is a number and does not change.
- **Live updates** carry keys, not times. The rows they bring are shown in
  the zone of the person who reads them.

## Things people trip over

- **"Every time is two hours off."** The page gives no zone, so the table
  is in UTC. Give `time_zone`, or set the assign on the socket.
- **"The first render shows UTC."** The demo learns the zone when the
  browser connects. A zone from the person's settings is there at once.
- **`Calendar.UTCOnlyTimeZoneDatabase`** is Elixir's default: it knows UTC
  and nothing else. Configure `tz` or `tzdata`.
- **"UTC" and "Etc/UTC"** are the same zone to the table. Other names of
  UTC (`"Etc/Zulu"`) need a database.

## Not in the first version

- **Formats of a locale** (`15.07.2026 14:00`, a 12-hour clock): times are
  written in the form of the input, ISO-like. That is deferred with the
  locale support.
- **The zone in each cell or in the header.** The page says it once, if it
  wants.
- **A zone per column,** or a column of a resource that says in which zone
  its times are.
- **Choosing the later of a repeated hour.**
- **A zone from the browser in the library itself.** It is a claim of the
  browser's; the demo shows how a host takes it.

Further work on what a table offers is in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
