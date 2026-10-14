defmodule AshDataTable.Components.Image do
  @moduledoc """
  A component that shows a picture: the image at the location a text column
  holds.

      column :avatar_url do
        component AshDataTable.Components.Image
      end

  It only shows: an editable column keeps the table's own text editor, in
  which the location is typed.

  ## What it needs

  A column whose field is text, holding where the picture is:

    * a web address that starts with `http://` or `https://`, or
    * a path on the host's own site that starts with one `/`
      (`/uploads/ada.png`).

  A value that is neither is shown as the text it is, and no picture is
  asked for: a `javascript:` or `data:` address never becomes the source of
  an image, nor does an address of another site without its scheme
  (`//example.com/a.png`). On a field that is no text the compiler warns,
  and the table refuses to be built.

  The component is given the value and nothing else of the record, so it
  cannot turn a stored key into an address: the column has to hold the
  address itself, or be a calculation that makes one.

  ## How it looks

  The picture at the height of a line of the table's text, as wide as its
  proportions make it and never wider than six times its height. The row is
  as high as a row without it. The browser asks for a picture when its row
  comes near the screen (`loading="lazy"`).

  The picture's text alternative is the column's label ("Avatar"): the
  component knows nothing else to call it by. A record without a value has
  an empty cell, as in every column.
  """
  use AshDataTable.Component

  @impl true
  def verify(%{cell_type: :text}), do: :ok

  def verify(%{cell_type: cell_type}) do
    {:error,
     "a picture is shown from the location a text holds, and this field is shown as " <>
       "#{AshDataTable.Component.shown_as(cell_type)}. It needs a text: a `:string` that holds " <>
       "an `http://` or `https://` address, or a path that starts with `/`."}
  end

  attr :value, :any, required: true, doc: "the value as the record holds it"
  attr :text, :string, required: true, doc: "what the table itself would show for it"

  attr :column, AshDataTable.Component.Column,
    required: true,
    doc: "what the resource knows about the field"

  @impl true
  def cell(assigns) do
    assigns = assign(assigns, :source, source(assigns.text))

    ~H"""
    <img
      :if={@source}
      src={@source}
      alt={@column.label}
      loading="lazy"
      decoding="async"
      class="inline-block h-5 w-auto max-w-30 object-contain align-top"
    />{if is_nil(@source), do: @text}
    """
  end

  @doc """
  Where the picture of a value is asked for: the value itself when it is an
  `http://` or `https://` address with a host, or a path that starts with
  one `/`. Nil for everything else, which is then shown as text.
  """
  @spec source(String.t()) :: String.t() | nil
  def source(text) when is_binary(text) do
    text = String.trim(text)

    cond do
      # nothing a browser would read as something else: no space, no control
      # character, no backslash (which a browser takes for a slash)
      text =~ ~r/[\s\\\x00-\x1f]/ -> nil
      String.starts_with?(text, "/") and not String.starts_with?(text, "//") -> text
      web?(text) -> text
      true -> nil
    end
  end

  def source(_other), do: nil

  defp web?(text) do
    case URI.new(text) do
      {:ok, %URI{scheme: scheme, host: host}} when scheme in ["http", "https"] ->
        is_binary(host) and host != ""

      _other ->
        false
    end
  end
end
