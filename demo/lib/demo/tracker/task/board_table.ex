defmodule Demo.Tracker.Task.BoardTable do
  @moduledoc """
  The board of the tasks, in a file of its own: a named table of
  `Demo.Tracker.Task`, which lists this module as a fragment.

  A second table of the same resource, for another purpose than the one at
  `/tasks`: four columns, of which the title and the state are edited in
  place, and one row action. It is mounted at `/tasks/board`.

  Its rows expand into two relationships, and each says which of the
  destination's tables it shows:

    * the comments in their compact table, which is mounted too
      (`/comments/compact`), so the nested table links to its full view;
    * the labels in their short table, which is mounted nowhere, so that
      nested table has no such link.
  """
  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshDataTable.Resource]

  tables do
    table :board do
      update_action :update
      max_depth 1

      column :title

      column :status do
        label "State"
      end

      column :assignee
      column :due_on

      # a row action of this table: the default table's are not taken over
      action :archive

      relationship :comments do
        table :compact
      end

      relationship :labels do
        table :short
      end
    end
  end
end
