defmodule Demo.Tracker.Milestone do
  @moduledoc """
  A point a project has to reach: an embedded resource, of which a project
  holds a list. Its primary key is public, so Ash can tell which milestone
  of the list is which when the list is saved, and updates the ones that
  are still there.
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints min_length: 3, max_length: 60
    end

    attribute :due_on, :date, public?: true

    attribute :reached?, :boolean do
      allow_nil? false
      default false
      public? true
    end
  end
end
