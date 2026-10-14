defmodule AshDataTable.LiveUpdatesTest do
  @moduledoc """
  Boundaries 1 and 2 of live updates: `live?` in a `table` block and in a
  named table, `pub_sub` in a domain's block and what is reported without
  it, the model's answer, what the notifier announces and where, and the
  listener that gathers it.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Spark.Test

  alias AshDataTable.Listener
  alias AshDataTable.Model
  alias AshDataTable.Notifier
  alias AshDataTable.Resource.Info
  alias AshDataTable.Resource.Listening

  defmodule OwnNotifier do
    @moduledoc false
    use Ash.Notifier

    @impl true
    def notify(_notification), do: :ok
  end

  defmodule Note do
    @moduledoc false
    use Ash.Resource,
      domain: AshDataTable.LiveUpdatesTest.Notes,
      data_layer: Ash.DataLayer.Ets,
      simple_notifiers: [AshDataTable.LiveUpdatesTest.OwnNotifier],
      extensions: [AshDataTable.Resource]

    attributes do
      uuid_primary_key :id
      attribute :title, :string, public?: true
      attribute :secret, :string, public?: true
    end

    actions do
      defaults [:read, :destroy, create: [:title, :secret], update: [:title, :secret]]

      action :ping, :string do
        run fn _input, _context -> {:ok, "pong"} end
      end
    end

    table do
      live? true
      column :title
    end

    tables do
      table :quiet do
        live? false
        column :title
      end

      table :plain do
        column :title
      end
    end
  end

  defmodule Lodger do
    @moduledoc false
    use Ash.Resource,
      domain: AshDataTable.LiveUpdatesTest.Notes,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshDataTable.Resource]

    multitenancy do
      strategy :context
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    actions do
      defaults [:read, :destroy, create: [:name], update: [:name]]
    end

    table do
      live? true
    end
  end

  defmodule Still do
    @moduledoc false
    use Ash.Resource,
      domain: AshDataTable.LiveUpdatesTest.Notes,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshDataTable.Resource]

    attributes do
      uuid_primary_key :id
      attribute :title, :string, public?: true
    end

    actions do
      defaults [:read, create: [:title]]
    end

    tables do
      table :other do
        column :title
      end
    end
  end

  defmodule Notes do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

    table do
      pub_sub AshDataTable.LiveUpdatesTest.PubSub
    end

    resources do
      resource AshDataTable.LiveUpdatesTest.Note
      resource AshDataTable.LiveUpdatesTest.Lodger
      resource AshDataTable.LiveUpdatesTest.Still
    end
  end

  # in a domain that does not list the extension, and so names no server
  defmodule Stray do
    @moduledoc false
    use Ash.Resource,
      domain: AshDataTable.Test.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshDataTable.Resource]

    attributes do
      uuid_primary_key :id
      attribute :title, :string, public?: true
    end

    actions do
      defaults [:read, create: [:title]]
    end

    table do
      live? true
    end
  end

  @pub_sub AshDataTable.LiveUpdatesTest.PubSub

  # What was announced to this process so far. An action announces in the
  # process that runs it, before it returns.
  defp heard(sofar \\ []) do
    receive do
      {:ash_data_table_changed, _resource, _type, _key, _tenant} = message ->
        heard([message | sofar])
    after
      0 -> Enum.reverse(sofar)
    end
  end

  # Another process that listens to `topic`, and says what it heard when asked.
  defp another(topic) do
    test = self()

    task =
      Task.async(fn ->
        Phoenix.PubSub.subscribe(@pub_sub, topic)
        send(test, :listening)

        receive do
          :say -> heard()
        end
      end)

    assert_receive :listening
    task
  end

  defp said(task) do
    send(task.pid, :say)
    Task.await(task)
  end

  describe "`live? true` in the `table` block" do
    test "is read through Info, and is false where it is not said" do
      assert Info.live?(Note)
      assert Info.table_live?(Note)
      refute Info.live?(Still)
      refute Info.live?(AshDataTable.Test.Domain)
    end

    test "adds the table's notifier to the resource, beside the host's own" do
      assert Ash.Resource.Info.notifiers(Note) == [AshDataTable.Resource.Notifier, OwnNotifier]
      assert Ash.Resource.Info.notifiers(Lodger) == [AshDataTable.Resource.Notifier]
      assert Ash.Resource.Info.notifiers(Still) == []
    end

    test "rejects a value that is not a boolean" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          defmodule Elixir.AshDataTable.LiveUpdatesTest.LiveSometimes do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            table do
              live? :sometimes
            end
          end
        end

      assert Exception.message(error) =~ "invalid value for :live? option: expected boolean"
    end
  end

  describe "`live?` in a named table" do
    test "says whether that table follows, and it follows unless it says no" do
      assert Info.table!(Note, :default).live?
      assert Info.table!(Note, :plain).live?
      refute Info.table!(Note, :quiet).live?

      assert Listening.follows?(Note, Info.table!(Note, :plain))
      refute Listening.follows?(Note, Info.table!(Note, :quiet))
      # nothing to follow where the resource announces nothing
      refute Listening.follows?(Still, Info.table!(Still, :other))
    end
  end

  describe "the model" do
    test "says whether the table follows live updates" do
      assert Model.build(Note).live?
      assert Model.build(Note, table: :plain).live?
      refute Model.build(Note, table: :quiet).live?
      refute Model.build(Still).live?
    end

    test "does not follow where the page says `live?: false`" do
      refute Model.build(Note, live?: false).live?
    end

    test "follows where the page says `live?: true`, whatever the named table says" do
      assert Model.build(Note, table: :quiet, live?: true).live?
    end

    test "refuses a table that is told to follow a resource that announces nothing" do
      error = assert_raise ArgumentError, fn -> Model.build(Still, live?: true) end

      assert error.message ==
               "cannot build the table of AshDataTable.LiveUpdatesTest.Still: it is asked to show " <>
                 "live updates (`live?: true`), but AshDataTable.LiveUpdatesTest.Still announces " <>
                 "none: add `live? true` to its `table` block."

      error = assert_raise ArgumentError, fn -> Model.build(Still, table: :other, live?: true) end

      assert error.message =~
               "cannot build the table `:other` of AshDataTable.LiveUpdatesTest.Still"
    end
  end

  describe "`pub_sub` in the domain's `table` block" do
    test "is read for a resource of the domain, and is nil where none is named" do
      assert AshDataTable.Domain.Info.pub_sub(Note) == @pub_sub
      assert Listening.pub_sub(Note) == {:ok, @pub_sub}

      assert AshDataTable.Domain.Info.pub_sub(Stray) == nil

      assert {:error, {:no_pub_sub, Stray, AshDataTable.Test.Domain} = reason} =
               Listening.pub_sub(Stray)

      assert Listening.message(reason) =~
               "AshDataTable.LiveUpdatesTest.Stray says `live? true`, but the `table` block of " <>
                 "AshDataTable.Test.Domain names no `pub_sub`."
    end

    test "is missed when the domain is compiled with a resource that says `live? true`" do
      error =
        assert_dsl_error %Spark.Error.DslError{} do
          defmodule Elixir.AshDataTable.LiveUpdatesTest.Silent do
            use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

            table do
              authorize? true
            end

            resources do
              allow_unregistered? true
              resource AshDataTable.LiveUpdatesTest.Still
              resource AshDataTable.LiveUpdatesTest.Note
            end
          end
        end

      assert error.path == [:table, :pub_sub]

      assert error.message ==
               "AshDataTable.LiveUpdatesTest.Note says `live? true`, but the `table` block of " <>
                 "AshDataTable.LiveUpdatesTest.Silent names no `pub_sub`. Live updates are sent " <>
                 "through a Phoenix.PubSub server: add `pub_sub MyApp.PubSub` to the `table` " <>
                 "block of AshDataTable.LiveUpdatesTest.Silent (with `extensions: [AshDataTable.Domain]`)."
    end

    test "is not missed in a domain whose resources announce nothing" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.LiveUpdatesTest.Calm do
          use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

          resources do
            allow_unregistered? true
            resource AshDataTable.LiveUpdatesTest.Still
          end
        end
      end
    end

    test "rejects a name that is not an atom" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          defmodule Elixir.AshDataTable.LiveUpdatesTest.PubSubAsText do
            use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

            table do
              pub_sub "MyApp.PubSub"
            end
          end
        end

      assert Exception.message(error) =~ "invalid value for :pub_sub option: expected atom"
    end
  end

  describe "the router" do
    test "takes `live?` for a mounted table, and only a boolean" do
      assert AshDataTable.Router.__live_opts__(Note, live?: false)[:metadata].ash_data_table.live? ==
               false

      assert AshDataTable.Router.__live_opts__(Note, [])[:metadata].ash_data_table.live? == nil

      assert_raise ArgumentError,
                   ~r/the :live\? of ash_data_table must be `true` or `false`/,
                   fn ->
                     AshDataTable.Router.__live_opts__(Note, live?: :yes)
                   end
    end
  end

  describe "the topic" do
    test "is the resource's, and the tenant's where the resource has tenants" do
      assert Notifier.topic(Note, nil) == "ash_data_table:AshDataTable.LiveUpdatesTest.Note"
      assert Notifier.topic(Note, "acme") == "ash_data_table:AshDataTable.LiveUpdatesTest.Note"

      assert Notifier.topic(Lodger, nil) == "ash_data_table:AshDataTable.LiveUpdatesTest.Lodger"

      assert Notifier.topic(Lodger, "acme") ==
               "ash_data_table:AshDataTable.LiveUpdatesTest.Lodger:acme"

      assert Notifier.topic(Lodger, 7) == "ash_data_table:AshDataTable.LiveUpdatesTest.Lodger:7"
      assert Notifier.topic(Lodger, "acme") != Notifier.topic(Lodger, "globex")
    end
  end

  describe "the notifier" do
    setup do
      start_supervised!({Phoenix.PubSub, name: @pub_sub})

      on_exit(fn ->
        for resource <- [Note, Lodger, Stray], do: Ash.DataLayer.Ets.stop(resource)
      end)

      :ok
    end

    test "announces the resource, the kind of action and the primary key, and nothing of the record" do
      Phoenix.PubSub.subscribe(@pub_sub, Notifier.topic(Note, nil))

      note = Ash.create!(Note, %{title: "Hello", secret: "s3cret"}, actor: %{id: 7})
      Ash.update!(note, %{title: "Hello again"}, actor: %{id: 7})
      Ash.destroy!(note, actor: %{id: 7})

      messages = heard()

      assert messages == [
               {:ash_data_table_changed, Note, :create, %{id: note.id}, nil},
               {:ash_data_table_changed, Note, :update, %{id: note.id}, nil},
               {:ash_data_table_changed, Note, :destroy, %{id: note.id}, nil}
             ]

      refute inspect(messages) =~ "s3cret"
      refute inspect(messages) =~ "Hello"
    end

    test "announces nothing for a generic action" do
      Phoenix.PubSub.subscribe(@pub_sub, Notifier.topic(Note, nil))

      assert Note |> Ash.ActionInput.for_action(:ping, %{}) |> Ash.run_action!() == "pong"
      assert heard() == []
    end

    test "announces to the tenant the action ran in, and to those who read without one" do
      Phoenix.PubSub.subscribe(@pub_sub, Notifier.topic(Lodger, "acme"))

      other = another(Notifier.topic(Lodger, "globex"))
      all = another(Notifier.topic(Lodger, nil))

      lodger = Ash.create!(Lodger, %{name: "Ann"}, tenant: "acme")

      assert heard() == [{:ash_data_table_changed, Lodger, :create, %{id: lodger.id}, "acme"}]
      assert said(all) == [{:ash_data_table_changed, Lodger, :create, %{id: lodger.id}, "acme"}]
      assert said(other) == []
    end

    test "leaves out the listener of the table that ran the action" do
      topic = Notifier.topic(Note, nil)
      Phoenix.PubSub.subscribe(@pub_sub, topic)

      another = another(topic)

      # what a table gives every call it makes (`AshDataTable.Query.reader_opts/1`)
      opts = AshDataTable.Query.reader_opts(origin: self(), authorize?: false)
      assert opts[:context] == %{ash_data_table_origin: self()}

      note = Ash.create!(Note, %{title: "Mine"}, opts)

      assert heard() == []
      assert said(another) == [{:ash_data_table_changed, Note, :create, %{id: note.id}, nil}]
    end

    test "lets a write through where the domain names no server" do
      assert %{title: "Unheard"} = Ash.create!(Stray, %{title: "Unheard"})
    end

    test "lets a write through, and says so, where the server is not running" do
      stop_supervised!(Phoenix.PubSub.child_spec(name: @pub_sub).id)

      log =
        capture_log(fn ->
          assert %{title: "Unheard"} = Ash.create!(Note, %{title: "Unheard"})
        end)

      assert log =~ "a change of AshDataTable.LiveUpdatesTest.Note could not be announced"
      assert log =~ "AshDataTable.LiveUpdatesTest.PubSub"
    end
  end

  describe "the listeners of a process" do
    setup do
      start_supervised!({Phoenix.PubSub, name: @pub_sub})
      :ok
    end

    test "are found by that process, and flushed together" do
      test = self()
      topic = Notifier.topic(Note, nil)
      {:ok, one} = Listener.start(@pub_sub, topic, &send(test, {:batch, &1}))
      {:ok, two} = Listener.start(@pub_sub, topic, &send(test, {:batch, &1}))
      assert Enum.sort(Listener.of(self())) == Enum.sort([one, two])

      Phoenix.PubSub.broadcast(
        @pub_sub,
        topic,
        {:ash_data_table_changed, Note, :update, %{id: 1}, nil}
      )

      for listener <- Listener.of(self()), do: Listener.flush(listener)

      assert_received {:batch, [update: %{id: 1}]}
      assert_received {:batch, [update: %{id: 1}]}

      Listener.stop(one)
      Listener.flush(one)
      Listener.stop(two)
    end
  end

  describe "the listener" do
    setup do
      start_supervised!({Phoenix.PubSub, name: @pub_sub})
      :ok
    end

    # what the listener has handed over, once it has handed over all it heard
    defp batches(listener) do
      Listener.flush(listener)
      handed([])
    end

    defp handed(sofar) do
      receive do
        {:batch, batch} -> handed([batch | sofar])
      after
        0 -> Enum.reverse(sofar)
      end
    end

    test "hands a burst over as one batch, each record once" do
      test = self()
      topic = Notifier.topic(Note, nil)
      {:ok, listener} = Listener.start(@pub_sub, topic, &send(test, {:batch, &1}))

      # subscribed by the time it is started: nothing is missed
      for n <- 1..1000, type <- [:update, :update] do
        Phoenix.PubSub.broadcast(
          @pub_sub,
          topic,
          {:ash_data_table_changed, Note, type, %{id: n}, nil}
        )
      end

      assert [batch] = batches(listener)
      assert batch == for(n <- 1..1000, do: {:update, %{id: n}})

      Phoenix.PubSub.broadcast(
        @pub_sub,
        topic,
        {:ash_data_table_changed, Note, :destroy, %{id: 1}, nil}
      )

      assert batches(listener) == [[destroy: %{id: 1}]]

      # and by itself, a moment after the first thing it hears
      Phoenix.PubSub.broadcast(
        @pub_sub,
        topic,
        {:ash_data_table_changed, Note, :create, %{id: 2}, nil}
      )

      assert_receive {:batch, [create: %{id: 2}]}, 1_000
      # nothing twice: the timer of a batch that was handed over early brings none
      assert batches(listener) == []

      assert Process.alive?(listener)
    end

    test "ends when it is stopped, and with the process it listens for" do
      test = self()
      topic = Notifier.topic(Note, nil)

      {:ok, listener} = Listener.start(@pub_sub, topic, &send(test, {:batch, &1}))
      reference = Process.monitor(listener)
      assert AshDataTable.Test.listening(Note) == 1

      Listener.stop(listener)
      assert_receive {:DOWN, ^reference, :process, _pid, _reason}
      assert AshDataTable.Test.listening(Note) == 0

      owner =
        spawn(fn ->
          {:ok, listener} = Listener.start(@pub_sub, topic, fn _batch -> :ok end)
          send(test, {:started, listener})
          Process.sleep(:infinity)
        end)

      assert_receive {:started, listener}
      reference = Process.monitor(listener)
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^reference, :process, _pid, _reason}
    end

    test "says that the server is not running" do
      assert {:error, %ArgumentError{}} =
               Listener.start(AshDataTable.LiveUpdatesTest.NoSuchPubSub, "topic", fn _batch ->
                 :ok
               end)
    end
  end
end
