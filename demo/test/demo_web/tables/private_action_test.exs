defmodule DemoWeb.Tables.PrivateActionTest do
  @moduledoc """
  Every action a table runs is `public?`, however the table came by it.

  The resources (`test/support/private_tables.ex`) read the demo's projects
  and tasks as dossiers and notes. Each has a private read action that the
  policies let everybody run, the way Ash's documentation has it for a
  private action, and that returns what the public one hides: the sealed
  dossier, the sealed note. A table that ran one would show them.

  The tables that would are written here, in `Demo.Support.Exposed`: what
  the compiler says about each is a result of the test. Compiled all the
  same, each is refused when it is built.

  Which actions were reached is seen in two ways: through
  `Demo.Support.Ran`, a preparation of every read action of the two
  resources, and through Ash's telemetry of the reads it runs.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage
  import Spark.Test, only: [dsl_errors: 1]

  alias Demo.Generator
  alias Demo.Support.Ran
  alias Demo.Support.Vault.{Dossier, Folder, Link, Note}

  @why "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies."

  setup_all do
    errors =
      dsl_errors do
        # No `read_action`: the table falls back to the primary read action.
        defmodule Elixir.Demo.Support.Exposed.Shelf do
          use Ash.Resource,
            domain: Demo.Support.Vault,
            data_layer: AshPostgres.DataLayer,
            authorizers: [Ash.Policy.Authorizer],
            extensions: [AshTable.Resource],
            primary_read_warning?: false

          postgres do
            table "projects"
            repo Demo.Repo
            migrate? false
          end

          table do
            column :name
          end

          actions do
            read :read do
              primary? true
              public? false
              prepare Demo.Support.Ran
            end

            read :open do
              prepare Demo.Support.Ran
            end
          end

          policies do
            bypass private_action?() do
              authorize_if always()
            end

            policy action(:open) do
              authorize_if expr(description == "open")
            end
          end

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
            attribute :description, :string, public?: true
            attribute :organization_id, :uuid
          end
        end

        # A relationship of the block whose own read action is private.
        defmodule Elixir.Demo.Support.Exposed.Cabinet do
          use Ash.Resource,
            domain: Demo.Support.Vault,
            data_layer: AshPostgres.DataLayer,
            extensions: [AshTable.Resource]

          postgres do
            table "projects"
            repo Demo.Repo
            migrate? false
          end

          table do
            column :name

            relationship :all_notes
          end

          actions do
            defaults [:read]
          end

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
          end

          relationships do
            has_many :all_notes, Demo.Support.Vault.Note do
              destination_attribute :project_id
              read_action :internal
              public? true
            end
          end
        end

        # A reference cell whose related record Ash loads through the
        # destination's primary read action, which is private.
        defmodule Elixir.Demo.Support.Exposed.Receipt do
          use Ash.Resource,
            domain: Demo.Support.Vault,
            data_layer: AshPostgres.DataLayer,
            extensions: [AshTable.Resource]

          postgres do
            table "tasks"
            repo Demo.Repo
            migrate? false
          end

          table do
            column :title
            column :dossier
          end

          actions do
            defaults [:read]
          end

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            belongs_to :dossier, Demo.Support.Vault.Dossier do
              source_attribute :project_id
              public? true
            end
          end
        end

        # A reference cell whose relationship names the private read action
        # itself.
        defmodule Elixir.Demo.Support.Exposed.Voucher do
          use Ash.Resource,
            domain: Demo.Support.Vault,
            data_layer: AshPostgres.DataLayer,
            extensions: [AshTable.Resource]

          postgres do
            table "tasks"
            repo Demo.Repo
            migrate? false
          end

          table do
            column :title
            column :dossier
          end

          actions do
            defaults [:read]
          end

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            belongs_to :dossier, Demo.Support.Vault.Dossier do
              source_attribute :project_id
              read_action :read
              public? true
            end
          end
        end

        # An aggregate column that is read through a private read action:
        # the last of the titles, which is that of the sealed note.
        defmodule Elixir.Demo.Support.Exposed.Drawer do
          use Ash.Resource,
            domain: Demo.Support.Vault,
            data_layer: AshPostgres.DataLayer,
            extensions: [AshTable.Resource]

          postgres do
            table "projects"
            repo Demo.Repo
            migrate? false
          end

          table do
            column :name
            column :last_title
          end

          actions do
            defaults [:read]
          end

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
          end

          relationships do
            has_many :notes, Demo.Support.Vault.Note, destination_attribute: :project_id
          end

          aggregates do
            max :last_title, :notes, :title do
              read_action :internal
              public? true
            end
          end
        end

        # A calculation column that holds such an aggregate, written out.
        defmodule Elixir.Demo.Support.Exposed.Index do
          use Ash.Resource,
            domain: Demo.Support.Vault,
            data_layer: AshPostgres.DataLayer,
            extensions: [AshTable.Resource]

          postgres do
            table "projects"
            repo Demo.Repo
            migrate? false
          end

          table do
            column :name
            column :latest
          end

          actions do
            defaults [:read]
          end

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
          end

          relationships do
            has_many :all_notes, Demo.Support.Vault.Note do
              destination_attribute :project_id
              read_action :internal
            end
          end

          calculations do
            calculate :latest, :string, expr(max(all_notes, field: :title)), public?: true
          end
        end

        # An aggregate column over a path: the notes are read through their
        # public read action, the dossiers in between through their private
        # primary one.
        defmodule Elixir.Demo.Support.Exposed.Register do
          use Ash.Resource,
            domain: Demo.Support.Vault,
            data_layer: AshPostgres.DataLayer,
            extensions: [AshTable.Resource]

          postgres do
            table "organizations"
            repo Demo.Repo
            migrate? false
          end

          table do
            column :name
            column :first_title
          end

          actions do
            defaults [:read]
          end

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
          end

          relationships do
            has_many :dossiers, Demo.Support.Vault.Dossier,
              destination_attribute: :organization_id
          end

          aggregates do
            min :first_title, [:dossiers, :notes], :title, public?: true
          end
        end

        # A relationship of the block that Ash joins through the private
        # primary read action of the join resource.
        defmodule Elixir.Demo.Support.Exposed.Tray do
          use Ash.Resource,
            domain: Demo.Support.Vault,
            data_layer: AshPostgres.DataLayer,
            extensions: [AshTable.Resource]

          postgres do
            table "tasks"
            repo Demo.Repo
            migrate? false
          end

          table do
            column :title

            relationship :all_marks
          end

          actions do
            defaults [:read]
          end

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            has_many :links, Demo.Support.Vault.Link, destination_attribute: :task_id

            many_to_many :all_marks, Demo.Support.Vault.Mark do
              through Demo.Support.Vault.Link
              join_relationship :links
              source_attribute_on_join_resource :task_id
              destination_attribute_on_join_resource :label_id
              public? true
            end
          end
        end

        # An aggregate column over such a relationship.
        defmodule Elixir.Demo.Support.Exposed.Tally do
          use Ash.Resource,
            domain: Demo.Support.Vault,
            data_layer: AshPostgres.DataLayer,
            extensions: [AshTable.Resource]

          postgres do
            table "tasks"
            repo Demo.Repo
            migrate? false
          end

          table do
            column :title
            column :mark_count
          end

          actions do
            defaults [:read]
          end

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            has_many :links, Demo.Support.Vault.Link, destination_attribute: :task_id

            many_to_many :all_marks, Demo.Support.Vault.Mark do
              through Demo.Support.Vault.Link
              join_relationship :links
              source_attribute_on_join_resource :task_id
              destination_attribute_on_join_resource :label_id
            end
          end

          aggregates do
            count :mark_count, :all_marks, public?: true
          end
        end

        # A relationship of the block through a path: the notes of an
        # organization's dossiers. Ash reads the dossiers in between through
        # their private primary read action.
        defmodule Elixir.Demo.Support.Exposed.Archive do
          use Ash.Resource,
            domain: Demo.Support.Vault,
            data_layer: AshPostgres.DataLayer,
            extensions: [AshTable.Resource]

          postgres do
            table "organizations"
            repo Demo.Repo
            migrate? false
          end

          table do
            column :name

            relationship :notes
          end

          actions do
            defaults [:read]
          end

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
          end

          relationships do
            has_many :dossiers, Demo.Support.Vault.Dossier,
              destination_attribute: :organization_id

            has_many :notes, Demo.Support.Vault.Note do
              through [:dossiers, :notes]
              public? true
            end
          end
        end

        # No relationship declared: the default set, which leaves out the
        # shelves, whose table would read through a private action, and the
        # notes, which Ash reads through one on the way.
        defmodule Elixir.Demo.Support.Exposed.Rack do
          use Ash.Resource,
            domain: Demo.Support.Vault,
            data_layer: AshPostgres.DataLayer,
            extensions: [AshTable.Resource]

          postgres do
            table "organizations"
            repo Demo.Repo
            migrate? false
          end

          table do
            column :name
          end

          actions do
            defaults [:read]
          end

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
          end

          relationships do
            has_many :shelves, Demo.Support.Exposed.Shelf do
              destination_attribute :organization_id
              public? true
            end

            has_many :dossiers, Demo.Support.Vault.Dossier do
              destination_attribute :organization_id
              public? true
            end

            has_many :notes, Demo.Support.Vault.Note do
              through [:dossiers, :notes]
              public? true
            end
          end
        end

        # A table that edits, over a private primary read action: Ash loads
        # what the update returns through it. Here the private action is
        # exempt from the field policies too, so the row that was saved
        # would show the description the page hides.
        defmodule Elixir.Demo.Support.Exposed.Editor do
          use Ash.Resource,
            domain: Demo.Support.Vault,
            data_layer: AshPostgres.DataLayer,
            authorizers: [Ash.Policy.Authorizer],
            extensions: [AshTable.Resource],
            primary_read_warning?: false

          postgres do
            table "projects"
            repo Demo.Repo
            migrate? false
          end

          table do
            read_action :open
            update_action :update

            column :name
            column :description
          end

          actions do
            # a save stamps the dossier, which hides its description
            update :update do
              accept [:name]
              change set_attribute(:description, "stamped")
            end

            read :read do
              primary? true
              public? false
              prepare Demo.Support.Ran
            end

            read :open do
              prepare Demo.Support.Ran
            end
          end

          policies do
            bypass private_action?() do
              authorize_if always()
            end

            policy action([:open, :update]) do
              authorize_if always()
            end
          end

          # the description of a dossier is seen where it says "open"
          field_policies do
            field_policy_bypass :*, private_action?() do
              authorize_if always()
            end

            field_policy :description do
              authorize_if expr(description == "open")
            end

            field_policy :* do
              authorize_if always()
            end
          end

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
            attribute :description, :string, public?: true
          end
        end
      end

    %{errors: Map.new(errors)}
  end

  # Two dossiers, of which the public read action returns the open one, and
  # three notes, of which it returns the two that are not sealed. The open
  # note has two marks, of which the links' public read action joins one.
  setup do
    organization = Generator.generate(Generator.organization())

    reporter =
      Generator.generate(Generator.user(organization_id: organization.id, role: :admin))

    [open, sealed] =
      for {name, description} <- [{"Open dossier", "open"}, {"Sealed dossier", "sealed"}] do
        Generator.generate(
          Generator.project(
            organization_id: organization.id,
            name: name,
            description: description
          )
        )
      end

    notes =
      for {dossier, title, sealed?} <- [
            {open, "Open note", false},
            {open, "Sealed note", true},
            {sealed, "Note in the sealed dossier", false}
          ],
          into: %{} do
        note =
          Generator.generate(
            Generator.task(
              organization_id: organization.id,
              project_id: dossier.id,
              reporter_id: reporter.id,
              title: title,
              billable?: sealed?
            )
          )

        {title, note}
      end

    for {name, withheld} <- [{"Plain mark", nil}, {"Withheld mark", "withheld"}] do
      mark = Generator.generate(Generator.label(organization_id: organization.id, name: name))

      Generator.generate(
        Generator.task_label(
          organization_id: organization.id,
          task_id: notes["Open note"].id,
          label_id: mark.id,
          note: withheld
        )
      )
    end

    Ran.watch()

    test = self()
    handler = "private-action-#{System.unique_integer()}"

    :telemetry.attach(
      handler,
      [:ash, :vault, :read, :start],
      fn _event, _measurements, metadata, _config ->
        send(test, {:read, metadata.resource_short_name, metadata.action})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    %{organization: organization, open: open, sealed: sealed, notes: notes}
  end

  # The reads Ash has run since the last call, each `{resource, action}`.
  defp reads do
    receive do
      {:read, resource, action} -> [{resource, action} | reads()]
    after
      50 -> []
    end
  end

  # What a page shows, as `shows` reads it; or what the table says when it
  # refuses to be built.
  defp page(conn, path, shows) do
    {:ok, view, html} = live(conn, path)
    {:shown, shows.(view, html)}
  rescue
    error in ArgumentError -> {:refused, Exception.message(error)}
  end

  defp texts(html, id, field), do: html |> column(id, field) |> Enum.sort()

  describe "a table that would run a private action is refused, and reads nothing" do
    test "a table that names no `read_action` over a private primary read action", %{conn: conn} do
      assert page(conn, "/support/shelves", fn _view, html -> texts(html, "shelf", "name") end) ==
               {:refused,
                "cannot build the table of Demo.Support.Exposed.Shelf: its read action cannot be used. " <>
                  "The primary read action `read` is not public, and the table names no `read_action`, so it would read through it. " <>
                  @why <> " Make `read` public, or name a public read action with `read_action`."}

      assert Ran.actions() == []
    end

    test "a table that offers a relationship whose own read action is private",
         %{conn: conn, open: open} do
      all_notes = fn view, _html ->
        expand(view, "cabinet", open.id)
        html = toggle(view, "cabinet", open.id, "all_notes")
        texts(html, nested("cabinet", open.id, "all_notes"), "title")
      end

      assert page(conn, "/support/cabinets", all_notes) ==
               {:refused,
                "cannot build the table of Demo.Support.Exposed.Cabinet: its relationship `all_notes` cannot be offered. " <>
                  "`all_notes` points to Demo.Support.Vault.Note, whose read action `internal`, the relationship's own `read_action`, is not public. " <>
                  @why <>
                  " Make `internal` public, give the relationship a public `read_action`, or do not offer `all_notes` in this table."}

      assert Ran.actions() == []
    end

    test "a table with a reference cell whose related record Ash loads through a private primary read action",
         %{conn: conn} do
      assert page(conn, "/support/receipts", fn _view, html ->
               texts(html, "receipt", "dossier")
             end) ==
               {:refused,
                "cannot build the table of Demo.Support.Exposed.Receipt: its column `dossier` cannot be shown. " <>
                  "`dossier` points to Demo.Support.Vault.Dossier, whose read action `read`, its primary read action, is not public. " <>
                  "The related record of a column is read as Ash loads the relationship. " <>
                  @why <>
                  " Make `read` public, give the relationship a public `read_action`, or do not show `dossier` as a column."}

      assert Ran.actions() == []
    end

    test "a table with a reference cell whose relationship names a private read action",
         %{conn: conn} do
      assert page(conn, "/support/vouchers", fn _view, html ->
               texts(html, "voucher", "dossier")
             end) ==
               {:refused,
                "cannot build the table of Demo.Support.Exposed.Voucher: its column `dossier` cannot be shown. " <>
                  "`dossier` points to Demo.Support.Vault.Dossier, whose read action `read`, the relationship's own `read_action`, is not public. " <>
                  "The related record of a column is read as Ash loads the relationship. " <>
                  @why <>
                  " Make `read` public, give the relationship a public `read_action`, or do not show `dossier` as a column."}

      assert Ran.actions() == []
    end

    test "a table with an aggregate column that Ash reads through the aggregate's private read action",
         %{conn: conn} do
      assert page(conn, "/support/drawers", fn _view, html ->
               texts(html, "drawer", "last_title")
             end) ==
               {:refused,
                "cannot build the table of Demo.Support.Exposed.Drawer: its column `last_title` cannot be shown. " <>
                  "The aggregate `last_title` reads Demo.Support.Vault.Note through `internal`, the aggregate's own `read_action`, which is not public. " <>
                  @why <>
                  " Make `internal` public, give the aggregate a public `read_action`, or do not show `last_title` as a column."}

      assert Ran.actions() == []
    end

    test "a table with a calculation column that holds an aggregate Ash reads through a private action",
         %{conn: conn} do
      assert page(conn, "/support/indexes", fn _view, html -> texts(html, "index", "latest") end) ==
               {:refused,
                "cannot build the table of Demo.Support.Exposed.Index: its column `latest` cannot be shown. " <>
                  "The calculation `latest` is computed from the aggregate `max(all_notes[field: :title])`: it reads Demo.Support.Vault.Note through `internal`, the `read_action` of the relationship `all_notes`, which is not public. " <>
                  @why <>
                  " Make `internal` public, give the relationship a public `read_action`, or do not show `latest` as a column."}

      assert Ran.actions() == []
    end

    test "a table with an aggregate column over a path that passes a resource Ash reads through its private primary read action",
         %{conn: conn} do
      assert page(conn, "/support/registers", fn _view, html ->
               texts(html, "register", "first_title")
             end) ==
               {:refused,
                "cannot build the table of Demo.Support.Exposed.Register: its column `first_title` cannot be shown. " <>
                  "The aggregate `first_title` reads Demo.Support.Vault.Dossier through `read`, its primary read action, which is not public. " <>
                  @why <>
                  " Make `read` public, give the relationship `dossiers` a public `read_action`, or do not show `first_title` as a column."}

      assert Ran.actions() == []
    end

    test "a table that offers a many-to-many which Ash joins through the join resource's private primary read action",
         %{conn: conn, notes: notes} do
      note = notes["Open note"]

      all_marks = fn view, _html ->
        expand(view, "tray", note.id)
        html = toggle(view, "tray", note.id, "all_marks")
        texts(html, nested("tray", note.id, "all_marks"), "name")
      end

      assert page(conn, "/support/trays", all_marks) ==
               {:refused,
                "cannot build the table of Demo.Support.Exposed.Tray: its relationship `all_marks` cannot be offered. " <>
                  "`all_marks` is read through the join resource Demo.Support.Vault.Link, whose read action `read`, its primary read action, is not public. " <>
                  @why <>
                  " Make `read` public, give the join relationship `links` a public `read_action`, or do not offer `all_marks` in this table."}

      assert Ran.actions() == []
    end

    test "a table with an aggregate column over such a many-to-many", %{conn: conn} do
      assert page(conn, "/support/tallies", fn _view, html ->
               texts(html, "tally", "mark_count")
             end) ==
               {:refused,
                "cannot build the table of Demo.Support.Exposed.Tally: its column `mark_count` cannot be shown. " <>
                  "The aggregate `mark_count` reads Demo.Support.Vault.Link through `read`, its primary read action, as the join resource of `all_marks`, which is not public. " <>
                  @why <>
                  " Make `read` public, give the join relationship `links` a public `read_action`, or do not show `mark_count` as a column."}

      assert Ran.actions() == []
    end

    test "a table that offers a relationship through a path that passes a resource Ash reads through its private primary read action",
         %{conn: conn, organization: organization} do
      notes = fn view, _html ->
        expand(view, "archive", organization.id)
        html = toggle(view, "archive", organization.id, "notes")
        texts(html, nested("archive", organization.id, "notes"), "title")
      end

      assert page(conn, "/support/archives", notes) ==
               {:refused,
                "cannot build the table of Demo.Support.Exposed.Archive: its relationship `notes` cannot be offered. " <>
                  "`notes` is read through Demo.Support.Vault.Dossier, a resource on its `through` path, whose read action `read`, the one Ash reads it through there, is not public. " <>
                  @why <> " Make `read` public, or do not offer `notes` in this table."}

      assert Ran.actions() == []
    end

    test "a table that edits over a private primary read action, through which Ash loads what an update returns",
         %{conn: conn, sealed: sealed} do
      after_a_save = fn view, _html ->
        html = save(view, "editor", sealed.id, "name", "Renamed dossier")
        texts(html, "editor", "description")
      end

      assert page(conn, "/support/editors", after_a_save) ==
               {:refused,
                "cannot build the table of Demo.Support.Exposed.Editor: " <>
                  "The table changes records: it has editable columns, row actions or a create action. " <>
                  "Ash loads what a create, an update or a destroy action returns through the primary read action, and the primary read action `read` is not public. " <>
                  @why <>
                  " Make `read` public, or leave the table read-only: without `update_action`, `action` and `create_action`."}

      assert Ran.actions() == []
    end

    test "and each is reported where it is declared when its resource is compiled",
         %{errors: errors} do
      assert Map.new(errors, fn {module, errors} -> {module, Enum.map(errors, & &1.path)} end) ==
               %{
                 Demo.Support.Exposed.Shelf => [[:table, :read_action]],
                 Demo.Support.Exposed.Cabinet => [[:table, :relationship, :all_notes]],
                 Demo.Support.Exposed.Receipt => [[:table, :column, :dossier]],
                 Demo.Support.Exposed.Voucher => [[:table, :column, :dossier]],
                 Demo.Support.Exposed.Drawer => [[:table, :column, :last_title]],
                 Demo.Support.Exposed.Index => [[:table, :column, :latest]],
                 Demo.Support.Exposed.Register => [[:table, :column, :first_title]],
                 Demo.Support.Exposed.Tray => [[:table, :relationship, :all_marks]],
                 Demo.Support.Exposed.Tally => [[:table, :column, :mark_count]],
                 Demo.Support.Exposed.Archive => [[:table, :relationship, :notes]],
                 Demo.Support.Exposed.Editor => [[:table]]
                 # and nothing about the rack, which declares no relationship
               }
    end
  end

  describe "a table that declares no relationship" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, "/support/dossiers")
      %{view: view}
    end

    test "does not offer one whose read action is private", %{view: view, open: open} do
      html = expand(view, "dossier", open.id)

      assert lines(html, "dossier", open.id) == ["Notes"]

      html = toggle(view, "dossier", open.id, "notes")
      assert texts(html, nested("dossier", open.id, "notes"), "title") == ["Open note"]
    end

    test "and a hand-sent event does not open it", %{view: view, open: open} do
      expand(view, "dossier", open.id)
      html = toggle(view, "dossier", open.id, "all_notes")

      assert texts(html, nested("dossier", open.id, "all_notes"), "title") == []
      assert Enum.filter(Ran.actions(), &match?({Note, :internal, _what}, &1)) == []
    end

    test "nor does a URL that limits the notes' table to it: the table shows itself as if nothing had been asked",
         %{conn: conn, open: open} do
      {:ok, _view, html} = live(conn, "/support/notes?note[of][dossier][all_notes]=#{open.id}")

      assert text(html, "#note-related-heading") == nil
      assert texts(html, "note", "title") == ["Note in the sealed dossier", "Open note"]
      assert Enum.filter(Ran.actions(), &match?({Note, :internal, _what}, &1)) == []
    end

    test "does not offer a many-to-many that Ash joins through a private read action, by a line or by a hand-sent event",
         %{conn: conn, notes: notes} do
      note = notes["Open note"]
      {:ok, view, _html} = live(conn, "/support/notes")
      html = expand(view, "note", note.id)

      assert lines(html, "note", note.id) == ["Dossier", "Binder", "Marks"]

      # joined through the links' public read action: not the withheld link
      html = toggle(view, "note", note.id, "marks")
      assert texts(html, nested("note", note.id, "marks"), "name") == ["Plain mark"]

      html = toggle(view, "note", note.id, "all_marks")
      assert texts(html, nested("note", note.id, "all_marks"), "name") == []
      assert Enum.filter(Ran.actions(), &match?({Link, :read, _what}, &1)) == []
    end

    test "does not offer one whose destination's table would read through a private action, nor one through a path that passes one",
         %{conn: conn, organization: organization} do
      {:ok, view, _html} = live(conn, "/support/racks")
      html = expand(view, "rack", organization.id)

      assert lines(html, "rack", organization.id) == ["Dossiers"]

      for name <- ["shelves", "notes"] do
        html = toggle(view, "rack", organization.id, name)
        assert texts(html, nested("rack", organization.id, name), "name") == []
        assert texts(html, nested("rack", organization.id, name), "title") == []
      end

      html = toggle(view, "rack", organization.id, "dossiers")
      assert texts(html, nested("rack", organization.id, "dossiers"), "name") == ["Open dossier"]

      assert Enum.filter(Ran.actions(), fn {resource, action, _what} ->
               {resource, action} in [{Dossier, :read}, {Demo.Support.Exposed.Shelf, :read}]
             end) == []
    end
  end

  describe "a private action that no table offers" do
    test "is not run by a hand-sent event that names it", %{conn: conn, notes: notes} do
      note = notes["Open note"]
      {:ok, view, _html} = live(conn, "/support/notes")

      act(view, "note", note.id, "shred")
      assert_reply view, %{ok: false}

      assert Demo.Repo.query!("SELECT count(*) FROM tasks WHERE id = $1", [
               Ecto.UUID.dump!(note.id)
             ]).rows == [[1]]
    end
  end

  describe "a table whose resource has a private primary read action reads through its own" do
    test "the page, and what is loaded onto its records in a second step", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/support/dossiers")

      assert column(html, "dossier", "name") == ["Open dossier"]
      # counted through the notes' public read action: not the sealed note
      assert column(html, "dossier", "note_count") == ["1"]

      # nothing private was run, or so much as asked about
      assert Ran.actions() == [
               # the count, loaded onto the page in a step of its own
               {Dossier, :open, :load},
               {Dossier, :open, :read},
               # the notes it counts, read with that load
               {Note, :read, :load},
               # and asked about, for the line "Notes"
               {Note, :read, :read}
             ]
    end

    test "the row a nested table belongs to, and the one a record is created under",
         %{conn: conn, open: open} do
      {:ok, view, _html} = live(conn, "/support/dossiers")
      expand(view, "dossier", open.id)
      reads()

      toggle(view, "dossier", open.id, "notes")

      # the row, its notes, and the dossier each note's reference cell names
      assert reads() == [{:dossier, :open}, {:note, :read}, {:dossier, :open}]

      view |> element("[id='dossier-row-#{open.id}-l-notes-create']") |> render_click()
      assert reads() == [{:dossier, :open}]
    end

    test "the row a URL limits a table to: not one the table of that row would not show",
         %{conn: conn, open: open, sealed: sealed} do
      {:ok, _view, html} = live(conn, "/support/notes?note[of][dossier][notes]=#{open.id}")

      assert text(html, "#note-related-heading") == "Open dossier: Notes"
      assert column(html, "note", "title") == ["Open note"]

      Ran.forget()
      {:ok, _view, html} = live(conn, "/support/notes?note[of][dossier][notes]=#{sealed.id}")

      assert column(html, "note", "title") == []
      assert text(html, "#note-error") == "This record is no longer available."
      assert Enum.filter(Ran.actions(), &match?({Dossier, :read, _what}, &1)) == []
    end
  end

  describe "a table nested under a row, through a relationship that names its own public read action" do
    test "reads its rows again through that action: a row it shows can be opened, though the table of its own resource would not show it",
         %{conn: conn, sealed: sealed, notes: notes} do
      note = notes["Note in the sealed dossier"]
      {:ok, view, _html} = live(conn, "/support/notes")

      expand(view, "note", note.id)
      binders = nested("note", note.id, "binder")
      html = toggle(view, "note", note.id, "binder")

      # through `every`, which the relationship names; the binders' own table
      # reads through `open`, which does not return this one
      assert texts(html, binders, "name") == ["Sealed dossier"]

      expand(view, binders, sealed.id)
      html = toggle(view, binders, sealed.id, "notes")

      assert text(html, "[id='#{nested(binders, sealed.id, "notes")}-error']") == nil

      assert texts(html, nested(binders, sealed.id, "notes"), "title") == [
               "Note in the sealed dossier"
             ]
    end
  end

  describe "a table that names another read action than the primary one, and edits" do
    setup %{conn: conn} do
      {:ok, view, html} = live(conn, "/support/folders")
      %{view: view, html: html}
    end

    test "shows the rows of its own read action", %{html: html} do
      assert texts(html, "folder", "name") == ["Open dossier", "Sealed dossier"]
    end

    test "saves a cell of a row that the primary read action would not return: the record is read again as the table reads it",
         %{view: view, sealed: sealed} do
      reads()

      html = save(view, "folder", sealed.id, "name", "Renamed dossier")
      assert_reply view, %{ok: true}

      assert texts(html, "folder", "name") == ["Open dossier", "Renamed dossier"]
      assert reads() == [{:folder, :every}]
    end

    test "shows the row again after the save as Ash loads what the update returned: through the primary read action",
         %{view: view, sealed: sealed} do
      Ran.forget()

      html = save(view, "folder", sealed.id, "name", "Renamed dossier")
      assert_reply view, %{ok: true}

      assert texts(html, "folder", "shouted") == ["Open dossier!", "Renamed dossier!"]

      assert Ran.actions() == [
               # the record, read again before the save; and the update itself,
               # which Ash runs as a statement over the read action it names
               {Folder, :every, :read},
               # what the update returned, loaded by Ash, and the rest of the
               # row, loaded by the table in the same way
               {Folder, :read, :load}
             ]
    end
  end
end
