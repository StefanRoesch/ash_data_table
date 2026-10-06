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

          column :title

          column :status do
            label "State"
            sortable? false
            filterable? false
          end
        end
      end

  The `table` block is optional: with the extension listed and no block, the
  table shows the resource's public attributes, read through its primary read
  action.

  With no `column`, the table shows the default set: the public attributes in
  the order `Ash.Resource.Info.public_attributes/1` returns them. Once one
  `column` is declared, the table is exactly the declared columns in the
  declared order. Calculations and aggregates appear only when named.

  Every column the resource allows to be filtered has a filter of its type in
  the filter row under the header. `filterable? false` leaves a column
  without one; nothing switches a filter on that the resource does not allow.

  Page size and default sort are not part of the block. They live on the read
  action (`pagination default_limit: …` and `prepare build(sort: …)`).
  """

  @column %Spark.Dsl.Entity{
    name: :column,
    describe: "A column of the table, showing one field of the resource.",
    examples: [
      "column :title",
      """
      column :status do
        label "State"
        sortable? false
      end
      """
    ],
    target: AshTable.Resource.Column,
    args: [:name],
    identifier: :name,
    schema: AshTable.Resource.Column.schema()
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
      end
      """
    ],
    schema: [
      read_action: [
        type: :atom,
        doc: "The read action behind the table. Defaults to the resource's primary read action."
      ],
      paginate_with: [
        type: {:one_of, [:offset, :keyset]},
        doc:
          "The pagination strategy. Defaults to `:offset` if the read action supports it, else `:keyset`."
      ]
    ],
    entities: [@column]
  }

  use Spark.Dsl.Extension,
    sections: [@table],
    verifiers: [
      AshTable.Resource.Verifiers.VerifyReadAction,
      AshTable.Resource.Verifiers.VerifyColumns
    ]
end
