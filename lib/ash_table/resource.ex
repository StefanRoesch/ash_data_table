defmodule AshTable.Resource do
  @moduledoc """
  The Ash extension that gives a resource a table.

      defmodule MyApp.Tracker.Task do
        use Ash.Resource,
          domain: MyApp.Tracker,
          extensions: [AshTable.Resource]

        table do
          read_action :open
          paginate_with :offset
          update_action :update

          column :title

          column :status do
            label "State"
            sortable? false
            filterable? false
          end

          column :price do
            update_action :reprice
            confirm "Change the price?"
          end

          column :slug do
            update_action false
          end
        end
      end

  The `table` block is optional: with the extension listed and no block, the
  table shows the resource's public attributes, read through its primary read
  action.

  Every action a table runs is `public?`, however the table came by it:
  named in the block, fallen back to, or reached through a relationship, a
  reference cell, or an aggregate or calculation column. An action that is `public? false`
  is not meant for interfaces, and its policies may let everybody run it,
  so a table that would run one is reported when the resource is compiled
  and refused when it is built. See the Authorization guide.

  With no `column`, the table shows the default set: the public attributes in
  the order `Ash.Resource.Info.public_attributes/1` returns them. Once one
  `column` is declared, the table is exactly the declared columns in the
  declared order. Calculations and aggregates appear only when named.

  A `column` that names a public belongs-to relationship is a reference
  cell: it shows the related record's label, which is the attribute that the
  destination resource's own `table` block names with `label_field`. It is
  neither sorted nor filtered by. The label is read as Ash loads the
  relationship, as the person, so the destination's policies decide what
  they read in the cell.

  Ash applies the read policy of a related resource to an aggregate and not
  its field policies, and applies no policy to what a calculation
  references. An aggregate or calculation column over a field that a field
  policy protects needs a field policy of its own, on this resource. The
  compiler warns when it has none; `exposes_protected_field? true` on the
  column says that it is meant.

  Every column the resource allows to be filtered has a filter of its type in
  the filter row under the header. `filterable? false` leaves a column
  without one; nothing switches a filter on that the resource does not allow.

  Nothing can be edited until the block names an `update_action`. The one of
  the table makes every column editable whose attribute that action accepts;
  a column can name its own, or `false` to stay read-only. An edit of a cell
  runs the column's action with the cell's attribute as its only input, so an
  action that needs more (a required argument without a default) cannot be
  behind a column. `confirm` asks a question before a cell of the column is
  saved.

  A person whose read the resource refuses outright is answered as if the
  table's page did not exist; `on_forbidden :message` tells them that they are
  not allowed instead. See `AshTable.Live.Page` for everything a table does
  about what a person may not see or do.

  Page size and default sort are not part of the block. They live on the read
  action (`pagination default_limit: …` and `prepare build(sort: …)`).

  ## Choosing a related record

  A reference cell is edited like any other cell: through an update action,
  the column's own or the table's. What that action has to accept is the
  relationship's foreign key (its `source_attribute`), which has to be a
  public, writable attribute.

      table do
        update_action :update    # accepts :assignee_id

        column :assignee
      end

  The person does not type the key. Enter on the cell opens the picker: a
  dialog with the table of the destination resource, as that resource
  declares it and as the person may read it, in which they select one row
  and choose it. "None" is offered where the key can be empty. The save is
  the save of a cell: the column's action runs with the key as its only
  input, a `confirm` asks first, and the row is shown from what the action
  returns.

  The records on offer are read through the relationship's own
  `read_action` when it names one, else through the read action of the
  destination's table; either has to be `public?`. The record that was
  chosen is read again on the server, by its key and as the person, before
  the key is saved: a key from the browser that names no record they may
  read there saves nothing.

  A relationship with a `filter` has no picker, and its cell is read-only:
  which records it can hold is for Ash's loader to say. So is a cell whose
  key no update action accepts.

  An input of a row action or of the create action that is such a key is
  given the same way, in the action panel: see below.

  ## Nested tables

  A row can be expanded into the tables of its related records:

      table do
        max_depth 2

        relationship :comments

        relationship :author do
          label "Written by"
        end
      end

  An expanded row shows one line per relationship, and a line opens the
  nested table: the table of the destination resource, as that resource
  declares it, limited to the records related to the row. It sorts, filters,
  pages and edits by itself, and its rows expand again.

  With no `relationship`, a row offers every public relationship whose
  destination resource has a table (lists this extension), except manual
  relationships and those that are read through a private action. Once one
  `relationship` is declared, a row offers exactly the declared ones in the
  declared order. A resource with nothing to offer has no expanders.

  What a nested table can do follows from the relationship, as Ash loads it:

    * It runs the relationship's own `read_action` when it declares one, else
      the read action of the destination's table. While the person has chosen
      no sort, the relationship's own `sort` comes first.
    * It has pages when the relationship holds many records, is joined by
      attributes, and that action declares pagination. A relationship with
      `no_attributes?` and a manual one are shown in full.
    * A relationship that holds one record (a belongs-to, a has-one) is a
      table of at most one row, without sort, filters or pages. So is a
      manual relationship, of however many rows.
    * A line whose destination the person can never read is left out for
      them, and the destination's policies and field policies apply to what
      a nested table shows as they do on a page of its own.

  `max_depth` says how deep a person can expand, counted from the table on
  the page: its nested tables are at depth 1. The default is 3, and the
  tables at that depth have no expanders. It is the setting of the table on
  the page that counts for everything beneath it. A table with `max_depth 0`
  never expands its rows, wherever it is shown.

  The last row of a nested table links to its full view, where the host's
  router mounts the destination's table (`AshTable.Router.ash_table/3`):
  that page, limited to the same records. See `AshTable.Live.Page`.

  ## Row actions and create

  A row can have buttons that run an action on its record, and a table a
  button that creates one:

      table do
        action :archive

        action :reassign do
          label "Hand over"
        end

        action :destroy do
          confirm "Delete this task? This cannot be undone."
        end

        create_action :create
      end

  Both are opt-in. An `action` names a public update or destroy action of
  the resource: a row action. Its button stands in the last column of the
  table, "Actions", in the declared order, and says the action's name in
  words unless `label` says otherwise. A generic action takes no record and
  cannot be a row action; a create action is named with `create_action`.

  Using a button runs the action straight away when the action has no
  inputs, or optional arguments only, which keep their defaults. An action
  that accepts attributes, or has an argument that is `allow_nil? false`,
  opens the action panel first: changing its attributes is what such an
  action is for. The create action always opens the panel.

  The panel has one field per input the action takes from the outside, in
  the action's own order: the public attributes it accepts, then its public
  arguments.

    * A field is called what the table's column for the attribute is called,
      else by the input's name in words.
    * Its control is the editor a cell of its type has (text, number,
      boolean, date, datetime, enum, and an array of those), or a plain
      text field for a value that is written as one line and has no editor
      of its own: a UUID, a time, an `:atom` without `one_of`.
    * An input that is the foreign key of a public belongs-to relationship
      whose destination has a table is not typed: its field says what the
      related record is called, and has a button that opens the picker on
      top of the panel. The field is called what the table's column of that
      relationship is called. A key whose destination has no table, or
      whose relationship has a `filter`, is a plain text field.
    * An input that is an embedded resource or a map that declares its
      fields, or an array of either, is a group of the value's fields under
      the input's label, each with the control of its own type.
    * A type with no field (a map that declares no fields, a union, an
      array of those) is left out of the panel when the input is optional. An action that
      requires such an input cannot be run from a table: the compiler
      reports it, and the table has no button for it.
    * A field is marked as required as the action says: an attribute that is
      `allow_nil? false` and not in the action's `allow_nil_input`, or in
      its `require_attributes`; an argument that is `allow_nil? false`. A
      create does not require an attribute whose default is computed.
    * A row action's fields start with the record's values and its
      arguments' defaults; those of a create with the defaults.

  The action is run through `AshPhoenix.Form`, as the person, on the record
  as it is read again at that moment. What it says about a field is shown at
  the field, and the panel stays open; what is about no field of the panel
  is shown above them. An action that ran straight away and failed marks the
  row's actions cell with its message.

  `confirm` asks a question before the action runs, or for an action with a
  panel when "Run" is used. A destroy action without `confirm` deletes at
  one click, which the compiler warns about: give it a question, or say
  `confirm false`.

  After an update action the row is shown from what the action returned and
  stays where it is. After a destroy the row is taken away, with everything
  open under it. A created record is the first row of the page until the
  table reads again. The total follows by one.

  The create button is on the line of the table's name and says "New" and
  the resource's short name in words: "New task". A nested table offers
  create only where the table can say what joins the new record to the row
  above: for a has-many joined by attributes, when this `create_action`
  accepts the relationship's destination attribute. The table then gives
  that attribute itself, and the button is on the relationship's line.

  A person who can never run an action has no button for it. An input of a
  field they can never see, or do not see on the record, is no field of
  their panel. See `AshTable.Live.Page`.

  ## Selecting rows and bulk actions

  A table with a row action has a box at the start of every row. A person
  selects rows, with the pointer or with Space, and runs a row action on
  all of them at once from the line above the grid. Nothing is declared for
  it: every row action is offered for the selected rows, unless it says
  otherwise.

      table do
        action :archive

        action :destroy do
          confirm "Delete this project, with all its tasks?"
          bulk? false
        end
      end

  `bulk? false` keeps an action to one row. An action that accepts an
  attribute of the primary key, or one that is an identity by itself, is not
  offered for a selection either: its inputs would be given once for every
  record, and no two records can hold that value. `bulk? true` on such an
  action is reported.

  Every such action asks first, with the number of records, and an action
  with inputs asks for them once, in the action panel, with empty fields.
  It then runs on each selected record as the row's button would: the
  record is read as the person through the table's read action, and the
  action is run on it as the person, through `Ash.bulk_update/4` or
  `Ash.bulk_destroy/4`, one record and one transaction at a time. The table
  says on how many records it ran and on how many it did not, with the
  action's messages, and the rows it did not run on stay selected.

  Which rows are selected is kept in the browser. It lasts through a sort
  and a change of page, and is given up when a filter changes. Once a whole
  page is selected, "Select all that match" selects every record the
  filters match.

  ## Custom components

  A column can name a module that says how its cells look, what they are
  edited with, or both:

      table do
        update_action :update

        column :status do
          component AshTable.Components.Badge
        end

        column :progress do
          component MyAppWeb.Cells.Progress
        end
      end

  The module implements `AshTable.Component`: `cell/1` shows a value and
  `editor/1` edits it, each a function component, and the table's own
  display or editor is used for the part a component does not have. Three
  are shipped: `AshTable.Components.Badge`, `AshTable.Components.Progress`
  and `AshTable.Components.Slider`.

  A component changes the look and the control and nothing else. A cell is
  saved through the column's `update_action` as before, with what the
  control holds; sorting, filtering and authorization are those of the
  field. A component is given the cell's value and what the resource knows
  about the field, never the record; it is not called for a value the person
  may not see, for which the table shows its own placeholder, nor for a
  record without one. The editor of a column's component is also the field
  of that attribute in the action panel.

  The resource does not depend on the module it names. A module that does
  not exist, is no component, or says that it cannot serve the column is
  reported once the application is compiled, and the table refuses to be
  built with it. A column that names a relationship has no component.
  """

  @column %Spark.Dsl.Entity{
    name: :column,
    describe:
      "A column of the table, showing one field of the resource, or the label of the record a belongs-to relationship leads to.",
    examples: [
      "column :title",
      "column :assignee",
      """
      column :status do
        label "State"
        sortable? false
      end
      """,
      """
      column :price do
        update_action :reprice
        confirm "Change the price?"
      end
      """,
      """
      column :progress do
        component AshTable.Components.Slider
      end
      """
    ],
    target: AshTable.Resource.Column,
    args: [:name],
    identifier: :name,
    # named without a dependency of the resource on the module: a component
    # is a module of the web layer, and is looked at once everything is
    # compiled (`VerifyComponents`)
    no_depend_modules: [:component],
    schema: AshTable.Resource.Column.schema()
  }

  @relationship %Spark.Dsl.Entity{
    name: :relationship,
    describe: """
    A relationship a row of the table can be expanded into: its line under the row opens the nested table of the related records.

    With no `relationship` declared, a row offers every public relationship of the resource whose destination resource has a table, except manual relationships and those whose nested table would run a private read action. Once one is declared, a row offers exactly the declared ones, in the declared order.

    The nested table runs the relationship's own `read_action` when it names one, else the read action of the destination's table. That action has to be `public?`, and so has every read action Ash runs on the way to the related records: the one of a many-to-many's join resource, and of the resources a `through` path passes.
    """,
    examples: [
      "relationship :comments",
      """
      relationship :author do
        label "Written by"
      end
      """
    ],
    target: AshTable.Resource.Relationship,
    args: [:name],
    identifier: :name,
    schema: AshTable.Resource.Relationship.schema()
  }

  @action %Spark.Dsl.Entity{
    name: :action,
    describe: """
    A row action: an update or destroy action of the resource that a person runs on the record of a row, from a button in the last column of the table. The buttons stand in the declared order.

    An action without inputs, or with optional arguments only, runs when its button is used. One that accepts attributes or has a required argument without a default opens the action panel first, where the person gives its inputs.

    A row action is also offered for the rows a person has selected, to run on all of them at once, unless it says `bulk? false`.
    """,
    examples: [
      "action :archive",
      """
      action :reassign do
        label "Hand over"
      end
      """,
      """
      action :destroy do
        confirm "Delete this task? This cannot be undone."
      end
      """,
      """
      action :destroy do
        confirm "Delete this project, with all its tasks?"
        bulk? false
      end
      """
    ],
    target: AshTable.Resource.Action,
    args: [:name],
    identifier: :name,
    schema: AshTable.Resource.Action.schema()
  }

  @table %Spark.Dsl.Section{
    name: :table,
    describe: "How the resource is presented to people as a table.",
    examples: [
      """
      table do
        read_action :open
        paginate_with :keyset

        column :title
        column :comment_count
        column :project
      end
      """,
      """
      table do
        label_field :name
      end
      """
    ],
    schema: [
      read_action: [
        type: :atom,
        doc:
          "The read action behind the table: a `public?` read action. Defaults to the resource's primary read action, which then has to be `public?` too."
      ],
      paginate_with: [
        type: {:one_of, [:offset, :keyset]},
        doc:
          "The pagination strategy. Defaults to `:offset` if the read action supports it, else `:keyset`."
      ],
      update_action: [
        type: :atom,
        doc:
          "The update action behind inline editing: every column whose attribute this action accepts becomes editable. Without it, and without an `update_action` on a column, the table is read-only."
      ],
      create_action: [
        type: :atom,
        doc:
          "The create action behind the table's create button: a public create action of the resource. The button opens the action panel with the action's inputs, and the new record is shown as the first row of the page. Without it the table has no create button."
      ],
      on_forbidden: [
        type: {:one_of, [:not_found, :message]},
        default: :not_found,
        doc:
          "What a person is shown whose read the resource refuses outright. `:not_found` answers as if the page did not exist (404); `:message` shows a \"not allowed\" message in place of the rows."
      ],
      label_field: [
        type: :atom,
        doc:
          "The attribute a record of this resource is called by where it is shown as one value: in a reference cell of another table (a `column` naming a belongs-to relationship to this resource), and in the heading of a table limited to the records related to it. A public attribute."
      ],
      max_depth: [
        type: :non_neg_integer,
        default: 3,
        doc:
          "How deep a person can expand rows into nested tables, counted from the table on the page: its own nested tables are at depth 1. The tables at this depth have no expanders. It is the setting of the table on the page that counts for everything beneath it; `0` means the rows of this table never expand, wherever the table is shown."
      ]
    ],
    entities: [@column, @relationship, @action]
  }

  use Spark.Dsl.Extension,
    sections: [@table],
    verifiers: [
      AshTable.Resource.Verifiers.VerifyReadAction,
      AshTable.Resource.Verifiers.VerifyUpdateAction,
      AshTable.Resource.Verifiers.VerifyLabelField,
      AshTable.Resource.Verifiers.VerifyColumns,
      AshTable.Resource.Verifiers.VerifyComponents,
      AshTable.Resource.Verifiers.VerifyRelationships,
      AshTable.Resource.Verifiers.VerifyActions,
      AshTable.Resource.Verifiers.VerifyExposure
    ]
end
