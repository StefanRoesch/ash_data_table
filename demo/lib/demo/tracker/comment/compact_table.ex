defmodule Demo.Tracker.Comment.CompactTable do
  @moduledoc """
  The compact table of the comments, in a file of its own: a named table of
  `Demo.Tracker.Comment`, which lists this module as a fragment.

  It shows less than the default table of the comments and changes nothing:
  three columns, no editing, no row actions, no "New comment", and rows that
  never expand. It is mounted at `/comments/compact`, and it is the table the
  board of the tasks (`Demo.Tracker.Task.BoardTable`) nests under a task.

  Nothing of the default table carries over: the `on_forbidden` is said once
  more here. What a comment is called (`label_field`) is the resource's, and
  is not said per table.
  """
  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshTable.Resource]

  tables do
    table :compact do
      on_forbidden :message
      max_depth 0

      # Up to three lines of a comment, with its line breaks: a row is as
      # high as its comment needs. What is cut off after that is shown
      # under the cell while the cell has the focus or the pointer.
      column :body do
        max_lines 3
      end

      # a reference cell: the author's name
      column :author
      column :inserted_at
    end
  end
end
