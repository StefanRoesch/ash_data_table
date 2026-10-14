defmodule AshTable.ZonesTest do
  @moduledoc """
  Boundaries 1 and 2: the time zone of a page. Which zones are taken, how a
  datetime is shown in one, what a wall time typed in one is given to Ash
  as (around both changes of the clocks), and which instants a filter on a
  datetime means.

  Every zone and every instant here is fixed. Europe/Berlin changes its
  clocks on 2026-03-29 (02:00 CET is 03:00 CEST: 23 hours) and on
  2026-10-25 (03:00 CEST is 02:00 CET: 25 hours).

  Not async: one test takes the time zone database away for a moment.
  """
  use ExUnit.Case, async: false

  alias AshTable.Act
  alias AshTable.Format
  alias AshTable.Model
  alias AshTable.Query
  alias AshTable.State
  alias AshTable.Test.Filtering
  alias AshTable.Zone

  @berlin "Europe/Berlin"

  defp field(name, type, cell_type \\ :datetime),
    do: %{name: name, type: {type, []}, cell_type: cell_type}

  describe "the zone a page gives" do
    test "nil and UTC are UTC, a zone of the database is itself" do
      assert Zone.check(nil) == {:ok, "Etc/UTC"}
      assert Zone.check("UTC") == {:ok, "Etc/UTC"}
      assert Zone.check("Etc/UTC") == {:ok, "Etc/UTC"}
      assert Zone.check(@berlin) == {:ok, @berlin}
      assert Zone.check("America/New_York") == {:ok, "America/New_York"}
    end

    test "a name that is no zone is refused, naming where it was given" do
      assert Zone.check("Mars/Olympus") == {:error, :not_a_zone}
      assert Zone.check(:berlin) == {:error, :not_a_zone}
      assert Zone.check(1) == {:error, :not_a_zone}

      error =
        assert_raise ArgumentError, fn ->
          Zone.check!("Mars/Olympus", "The `time_zone` of <AshTable.table>")
        end

      assert error.message =~ "The `time_zone` of <AshTable.table> is \"Mars/Olympus\""
      assert error.message =~ "no time zone the time zone database knows"
    end

    test "a zone other than UTC without a time zone database says what to add" do
      database = Calendar.get_time_zone_database()
      Calendar.put_time_zone_database(Calendar.UTCOnlyTimeZoneDatabase)
      on_exit(fn -> Calendar.put_time_zone_database(database) end)

      # UTC needs none
      assert Zone.check(nil) == {:ok, "Etc/UTC"}
      assert Zone.check("UTC") == {:ok, "Etc/UTC"}
      assert Zone.check(@berlin) == {:error, :no_database}

      error = assert_raise ArgumentError, fn -> Zone.check!(@berlin, "The assign") end
      assert error.message =~ "{:tz, \"~> 0.28\"}"
      assert error.message =~ "{:tzdata, \"~> 1.1\"}"
      assert error.message =~ "config :elixir, :time_zone_database, Tz.TimeZoneDatabase"
    end

    test "a placed table refuses a name that is no zone when it is rendered" do
      assigns = %{
        __changed__: nil,
        id: nil,
        resource: Filtering,
        table: nil,
        scope: nil,
        actor: nil,
        tenant: nil,
        authorize?: nil,
        live?: nil,
        url: nil,
        label: nil,
        heading: true,
        assigns: %{},
        time_zone: "Mars/Olympus"
      }

      error = assert_raise ArgumentError, fn -> AshTable.table(assigns) end
      assert error.message =~ "The `time_zone` of <AshTable.table> is \"Mars/Olympus\""
    end

    test "a mounted table reads it from the assign its domain names, `time_zone` by default" do
      assert AshTable.Domain.Info.time_zone_assign(Filtering) == :time_zone
      assert AshTable.Domain.Info.time_zone(Filtering, %{time_zone: @berlin}) == @berlin
      assert AshTable.Domain.Info.time_zone(Filtering, %{}) == nil
    end
  end

  describe "a datetime shown in a zone" do
    test "is the wall time there, in the form of the control, without the zone" do
      column = field(:at, :utc_datetime)

      # winter, summer, and the two sides of both changes of the clocks
      assert Format.format(column, ~U[2026-01-15 12:00:00Z], @berlin) == "2026-01-15T13:00:00"
      assert Format.format(column, ~U[2026-07-15 12:00:00Z], @berlin) == "2026-07-15T14:00:00"
      assert Format.format(column, ~U[2026-03-29 00:59:59Z], @berlin) == "2026-03-29T01:59:59"
      assert Format.format(column, ~U[2026-03-29 01:00:00Z], @berlin) == "2026-03-29T03:00:00"
      assert Format.format(column, ~U[2026-10-25 00:30:00Z], @berlin) == "2026-10-25T02:30:00"
      assert Format.format(column, ~U[2026-10-25 01:30:00Z], @berlin) == "2026-10-25T02:30:00"

      # the day can change with it
      assert Format.format(column, ~U[2026-01-15 23:30:00Z], @berlin) == "2026-01-16T00:30:00"
      assert Format.input(column, ~U[2026-01-15 23:30:00Z], @berlin) == "2026-01-16T00:30:00"
    end

    test "in UTC, and without a zone, is as it was before there were zones" do
      column = field(:at, :utc_datetime)

      assert Format.format(column, ~U[2026-07-15 12:00:00Z], "Etc/UTC") == "2026-07-15T12:00:00"
      assert Format.format(column, ~U[2026-07-15 12:00:00Z]) == "2026-07-15T12:00:00"
    end

    test "a naive datetime, a date and a time are shown as they are" do
      assert Format.format(field(:at, :naive_datetime), ~N[2026-07-15 12:00:00], @berlin) ==
               "2026-07-15T12:00:00"

      assert Format.format(field(:on, :date, :date), ~D[2026-07-15], @berlin) == "2026-07-15"
    end

    test "inside an array, a value of named fields, and a summary" do
      at = field(:at, :utc_datetime)
      many = %{at | cell_type: {:array, :datetime}, type: {{:array, :utc_datetime}, []}}

      assert Format.format(many, [~U[2026-07-15 12:00:00Z], ~U[2026-01-15 12:00:00Z]], @berlin) ==
               "2026-07-15T14:00:00, 2026-01-15T13:00:00"

      assert Format.input(many, [~U[2026-07-15 12:00:00Z]], @berlin) == ["2026-07-15T14:00:00"]

      map = %{
        name: :visit,
        cell_type: :map,
        type: {Ash.Type.Map, []},
        fields: [
          %{field(:at, :utc_datetime) | name: :at} |> Map.merge(%{label: "At", key?: false})
        ]
      }

      assert Format.format(map, %{at: ~U[2026-07-15 12:00:00Z]}, @berlin) ==
               "At: 2026-07-15T14:00:00"

      assert Format.summary(Map.put(at, :summary, :max), ~U[2026-07-15 12:00:00Z], @berlin) ==
               "2026-07-15T14:00:00"
    end

    test "what a generic action returns is said in the zone" do
      action = %Model.Action{name: :when, label: "When", type: :action, returns: nil}
      assert Act.said(action, ~U[2026-07-15 12:00:00Z], @berlin) == "2026-07-15T14:00:00"
    end
  end

  describe "a wall time typed in a zone" do
    test "is given to Ash as the instant it is, in UTC" do
      assert Zone.instant("2026-01-15T13:00", @berlin) == {:ok, "2026-01-15T12:00:00Z"}
      assert Zone.instant("2026-07-15T14:00:30", @berlin) == {:ok, "2026-07-15T12:00:30Z"}
      assert Zone.instant("2026-07-15 14:00:30.250", @berlin) == {:ok, "2026-07-15T12:00:30.250Z"}
      # a date alone is its first moment there
      assert Zone.instant("2026-07-15", @berlin) == {:ok, "2026-07-14T22:00:00Z"}
    end

    test "that is there twice, when the clocks go back, is the earlier instant" do
      assert Zone.instant("2026-10-25T02:30", @berlin) == {:ok, "2026-10-25T00:30:00Z"}
    end

    test "that is not there, when the clocks go forward, is a gap, with the instant after it" do
      assert Zone.instant("2026-03-29T02:30", @berlin) == {:gap, "2026-03-29T01:00:00Z"}
      assert Zone.instant("2026-03-29T01:59:59", @berlin) == {:ok, "2026-03-29T00:59:59Z"}
      assert Zone.instant("2026-03-29T03:00", @berlin) == {:ok, "2026-03-29T01:00:00Z"}
    end

    test "with an offset of its own, or that is no wall time, goes to Ash as typed" do
      assert Zone.instant("2026-07-15T14:00:00+02:00", @berlin) == :as_typed
      assert Zone.instant("2026-07-15T14:00:00Z", @berlin) == :as_typed
      assert Zone.instant("tomorrow", @berlin) == :as_typed
      assert Zone.instant("2026-13-45T10:00", @berlin) == :as_typed
    end

    test "comes back as it was typed, for every instant but the later of a repeated hour" do
      column = field(:at, :utc_datetime)

      for instant <- [
            ~U[2026-01-15 12:00:00Z],
            ~U[2026-03-29 00:59:59Z],
            ~U[2026-03-29 01:00:00Z],
            ~U[2026-10-25 00:00:00Z],
            ~U[2026-10-25 00:30:00Z],
            ~U[2026-10-25 02:00:00Z],
            ~U[2026-12-31 23:30:00Z]
          ] do
        shown = Format.input(column, instant, @berlin)
        assert {:ok, written} = Zone.instant(shown, @berlin)
        assert {:ok, ^instant, 0} = DateTime.from_iso8601(written), "#{instant}"
      end

      # 02:30 CET, the second 02:30 of that night, is typed as the first
      assert Format.input(column, ~U[2026-10-25 01:30:00Z], @berlin) == "2026-10-25T02:30:00"
      assert Zone.instant("2026-10-25T02:30:00", @berlin) == {:ok, "2026-10-25T00:30:00Z"}
    end

    test "of a field: only an instant is converted, in arrays and in values of named fields" do
      assert Zone.given(field(:at, :utc_datetime), "2026-07-15T14:00", @berlin) ==
               {"2026-07-15T12:00:00Z", []}

      assert Zone.given(field(:at, :datetime), "2026-07-15T14:00", @berlin) ==
               {"2026-07-15T12:00:00Z", []}

      assert Zone.given(field(:at, :utc_datetime_usec), "2026-07-15T14:00", @berlin) ==
               {"2026-07-15T12:00:00Z", []}

      # a naive datetime has no zone, and text is text
      assert Zone.given(field(:at, :naive_datetime), "2026-07-15T14:00", @berlin) ==
               {"2026-07-15T14:00", []}

      assert Zone.given(field(:at, :string, :text), "2026-07-15T14:00", @berlin) ==
               {"2026-07-15T14:00", []}

      many = %{
        name: :at,
        cell_type: {:array, :datetime},
        type: {{:array, :utc_datetime}, []}
      }

      assert Zone.given(many, ["2026-07-15T14:00", "2026-03-29T02:30"], @berlin) ==
               {["2026-07-15T12:00:00Z", "Europe/Berlin 2026-03-29T02:30"], [[1]]}

      visit = %{
        name: :visit,
        cell_type: {:array, :map},
        type: {{:array, Ash.Type.Map}, []},
        fields: [field(:at, :utc_datetime), field(:note, :string, :text)]
      }

      assert Zone.given(
               visit,
               [
                 %{"at" => "2026-07-15T14:00", "note" => "2026-07-15T14:00"},
                 %{"at" => "2026-03-29T02:15"}
               ],
               @berlin
             ) ==
               {[
                  %{"at" => "2026-07-15T12:00:00Z", "note" => "2026-07-15T14:00"},
                  %{"at" => "Europe/Berlin 2026-03-29T02:15"}
                ], [[1, :at]]}
    end

    test "in UTC is given as typed, as before there were zones" do
      assert Zone.given(field(:at, :utc_datetime), "2026-03-29T02:30", "Etc/UTC") ==
               {"2026-03-29T02:30", []}
    end

    test "that does not exist is text no datetime of Ash takes: nothing is stored for it" do
      {given, [[]]} = Zone.given(field(:at, :utc_datetime), "2026-03-29T02:30", @berlin)
      assert {:error, _message} = Ash.Type.cast_input(:utc_datetime, given, [])
    end

    test "a panel names the field of such a time, with the zone" do
      inputs = [
        %Model.Input{
          name: :due_at,
          label: "Due at",
          kind: :attribute,
          type: {:utc_datetime, []},
          cell_type: :datetime,
          editor: :datetime
        }
      ]

      assert Act.gaps(inputs, %{"due_at" => "2026-03-29T02:30"}, @berlin) ==
               %{due_at: ["This time does not exist in Europe/Berlin."]}

      assert Act.gaps(inputs, %{"due_at" => "2026-03-29T03:30"}, @berlin) == %{}
      assert Act.gaps(inputs, %{"due_at" => "2026-03-29T02:30"}, "Etc/UTC") == %{}

      assert Act.values(inputs, %{"due_at" => "2026-07-15T14:00"}, @berlin) ==
               %{"due_at" => "2026-07-15T12:00:00Z"}
    end
  end

  describe "an argument of the line in a zone" do
    test "shows its default there, and is given what is typed as the instant it is" do
      argument = %Model.Argument{
        name: :since,
        label: "Since",
        type: {:utc_datetime, []},
        cell_type: :datetime,
        editor: :datetime,
        default: ~U[2026-07-15 12:00:00Z]
      }

      model =
        %Model{
          resource: Filtering,
          primary_key: [:id],
          read_action: :read,
          pagination: nil,
          columns: [],
          arguments: [argument]
        }
        |> Model.zoned(@berlin)

      assert [%{time_zone: @berlin} = zoned] = model.arguments
      assert Model.Argument.rest(zoned) == "2026-07-15T14:00:00"
      assert Model.Argument.rest(argument) == "2026-07-15T12:00:00"

      assert Model.supply(model, %{{nil, :since} => "2026-07-15T16:00"}).read_arguments ==
               %{since: "2026-07-15T14:00:00Z"}

      # a time the clocks skip: the first moment after the gap, as in a filter
      assert Model.supply(model, %{{nil, :since} => "2026-03-29T02:30"}).read_arguments ==
               %{since: "2026-03-29T01:00:00Z"}
    end
  end

  describe "a filter on a datetime in a zone" do
    setup do
      # around the night the clocks go forward: 2026-03-29 in Berlin is
      # from 2026-03-28T23:00Z to 2026-03-29T22:00Z, 23 hours
      for {name, seen_at} <- [
            {"before", ~U[2026-03-28 22:59:59.000000Z]},
            {"first", ~U[2026-03-28 23:00:00.000000Z]},
            {"gap", ~U[2026-03-29 01:00:00.000000Z]},
            {"last", ~U[2026-03-29 21:59:59.000000Z]},
            {"after", ~U[2026-03-29 22:00:00.000000Z]}
          ] do
        Ash.Seed.seed!(Filtering, %{
          name: name,
          email: "#{name}@example.com",
          visits: 1,
          percentage: 1,
          active: true,
          born_on: ~D[2026-01-01],
          seen_at: seen_at,
          archived_at: DateTime.to_naive(seen_at),
          status: :open
        })
      end

      on_exit(fn -> Ash.DataLayer.Ets.stop(Filtering) end)
      :ok
    end

    defp names(filters, zone) do
      model = Filtering |> Model.build() |> Model.zoned(zone)
      {:ok, page} = Query.read(model, %State{filters: filters}, authorize?: false)
      page.records |> Enum.map(& &1.name) |> Enum.sort()
    end

    test "between the first and the last moment of a day is that day there" do
      day = {:between, {"2026-03-29T00:00", "2026-03-29T23:59:59"}}

      assert names(%{seen_at: day}, @berlin) == ["first", "gap", "last"]
      # the same text in UTC is another day
      assert names(%{seen_at: day}, "Etc/UTC") == ["after", "gap", "last"]
    end

    test "between dates alone is from the first moment of the one to that of the other" do
      # both ends among them: "after" is the first moment of 2026-03-30 there
      assert names(%{seen_at: {:between, {"2026-03-29", "2026-03-30"}}}, @berlin) ==
               ["after", "first", "gap", "last"]
    end

    test "before and after are of the wall time there" do
      assert names(%{seen_at: {:before, "2026-03-29T00:00"}}, @berlin) == ["before"]
      assert names(%{seen_at: {:after, "2026-03-29T23:59:59"}}, @berlin) == ["after"]
    end

    test "a time the clocks skip means the first moment after the gap" do
      assert names(%{seen_at: {:before, "2026-03-29T02:30"}}, @berlin) == ["before", "first"]

      assert names(%{seen_at: {:between, {"2026-03-29T02:30", nil}}}, @berlin) ==
               ["after", "gap", "last"]
    end

    test "a naive datetime is filtered by as typed" do
      assert names(%{archived_at: {:before, "2026-03-29T00:00"}}, @berlin) == ["before", "first"]
    end

    test "the state, and so the URL, keeps what was typed" do
      model = Filtering |> Model.build() |> Model.zoned(@berlin)
      state = %State{filters: %{seen_at: {:between, {"2026-03-29T00:00", "2026-03-29T23:59:59"}}}}

      assert State.to_params(state, model)["f"] == %{
               "seen_at" => %{
                 "between" => %{"from" => "2026-03-29T00:00", "to" => "2026-03-29T23:59:59"}
               }
             }
    end
  end
end
