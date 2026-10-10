defmodule Demo.Tracker.Client do
  @moduledoc """
  Who a project is for: an embedded resource, with another one inside it.
  A table shows it on one line and edits it in the side panel, field by
  field.
  """
  use Ash.Resource, data_layer: :embedded

  validations do
    validate match(:email, ~r/^[^@\s]+@[^@\s]+$/) do
      where present(:email)
      message "must be an email address"
    end
  end

  attributes do
    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 2, max_length: 60
    end

    attribute :email, :string, public?: true

    attribute :key_account?, :boolean do
      allow_nil? false
      default false
      public? true
    end

    # An embedded resource inside an embedded resource.
    attribute :address, Demo.Tracker.Address, public?: true

    # Private on purpose: never shown, never asked for.
    attribute :credit_note, :string
  end
end
