defmodule Demo.Tracker.Comment do
  @moduledoc """
  A comment on a task. Its primary read is keyset-only.

  It has two tables: the default one below, and a named one, `:compact`, in
  `Demo.Tracker.Comment.CompactTable`.

  As with `Demo.Tracker.Project`, its read is refused outright for an
  anonymous visitor. Its table says so (`on_forbidden :message`), where the
  one of projects answers as a page that does not exist.
  """
  use Ash.Resource,
    otp_app: :demo,
    domain: Demo.Tracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource],
    # A second table of the comments, declared in a file of its own:
    # `comment/compact_table.ex`.
    fragments: [Demo.Tracker.Comment.CompactTable],
    # The default sort of a table lives on its read action, on purpose.
    primary_read_warning?: false

  postgres do
    table "comments"
    repo Demo.Repo

    references do
      reference :organization, on_delete: :delete
      reference :task, on_delete: :delete
      reference :author, on_delete: :delete
    end

    custom_indexes do
      index [:task_id, :inserted_at]
    end
  end

  resource do
    plural_name :comments
  end

  # No `column`: the table shows the public attributes, and edits the one its
  # `update` action accepts, the body. A person whose read is refused is told
  # so, in place of the rows.
  table do
    update_action :update
    on_forbidden :message

    # Live updates, also where the comments are nested under a task.
    live? true

    # "Rows per page", here and where the comments are nested under a task:
    # 20 is the `default_limit` of the read action.
    page_sizes [10, 20, 50]

    action :destroy do
      confirm "Delete this comment?"
    end

    # "New comment". Under a task, the table gives `task_id` itself: the
    # action accepts it, and the comments of a task are a has-many.
    create_action :create
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      pagination keyset?: true, default_limit: 20, max_page_size: 100, required?: false
      prepare build(sort: [inserted_at: :desc, id: :desc])
    end

    create :create do
      primary? true
      accept [:body, :task_id]
      change relate_actor(:author)
    end

    update :update do
      primary? true
      accept [:body]
    end
  end

  policies do
    policy action_type(:read) do
      description "Refused outright, not filtered, when nobody is logged in."
      access_type :strict
      authorize_if actor_present()
    end

    policy action_type(:read) do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end

    policy action_type(:create) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :member)
    end

    policy action_type([:update, :destroy]) do
      description "Admins, and the comment's own author unless they are a viewer."
      forbid_if actor_attribute_equals(:role, :viewer)
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(author_id == ^actor(:id))
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
    global? true
  end

  attributes do
    uuid_primary_key :id

    attribute :body, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 2000
    end

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Demo.Tracker.Organization, allow_nil?: false

    belongs_to :task, Demo.Tracker.Task do
      allow_nil? false
      public? true
      attribute_public? true
    end

    belongs_to :author, Demo.Tracker.User do
      allow_nil? false
      public? true
      attribute_public? true
    end
  end
end
