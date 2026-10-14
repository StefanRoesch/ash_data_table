defmodule AshDataTable.Model.Limits do
  @moduledoc false
  # What the constraints of an input's type say that its native control can
  # say too: the smallest and the largest number it takes, and the steps
  # between them. The table puts them on the control (`min`, `max`, `step`),
  # so that a person meets the limit before saving: the arrows of a number
  # input stop at it, and a screen reader reads it.
  #
  # They are a description and never a check: nothing in the browser refuses
  # a value because of them. What is typed is given to the action as it is,
  # and Ash says what is wrong with it.
  #
  # Only what a browser means exactly as Ash does is here:
  #
  #   * `min` and `max` of an integer, a float and a decimal, which include
  #     the bound itself in Ash and in HTML alike;
  #   * `step` is "1" for an integer, which takes whole numbers only, and
  #     "any" for a float and a decimal.
  #
  # Left out on purpose, as HTML has no attribute that means the same:
  #
  #   * `greater_than` and `less_than` of a float and a decimal, which
  #     exclude the bound: `min` and `max` would let the bound itself pass;
  #   * `max_length` and `min_length` of text: a browser counts UTF-16 code
  #     units of the text as it was typed, Ash counts codepoints, graphemes
  #     or bytes (`length_count`) of the text once it is trimmed. `maxlength`
  #     would stop a person from typing a value Ash takes, without a word.
  #     The most a text can be long is said beside its control instead, by
  #     a counter ("12/30"): see `counted/1` below;
  #   * `match` of text: the pattern is a regular expression of Erlang's,
  #     which a browser reads by other rules, and is matched after trimming;
  #   * `precision` and `scale` of a decimal, and how many values an array
  #     takes (`min_length`, `max_length`).
  #
  # The limits of an array are those of each of its values (`items`). A type
  # made of another (`Ash.Type.NewType`) has the limits of what it is made
  # of, with the constraints it gives it.

  @type t :: %{min: String.t() | nil, max: String.t() | nil, step: String.t() | nil}

  @none %{min: nil, max: nil, step: nil}

  @doc """
  The limits of an input, a field of a map cell, an argument or a column:
  anything that has a `type`, the Ash type with its constraints.
  """
  @spec of(%{:type => {Ash.Type.t() | nil, keyword}, optional(atom) => term}) :: t
  def of(%{type: {type, constraints}}), do: of(type, constraints)

  @doc "The limits of an Ash type with its constraints."
  @spec of(Ash.Type.t() | nil, keyword) :: t
  def of({:array, type}, constraints), do: of(type, constraints[:items] || [])
  def of(nil, _constraints), do: @none

  def of(type, constraints) do
    type = Ash.Type.get_type(type)

    cond do
      type == Ash.Type.Integer ->
        bounds(constraints, "1")

      type in [Ash.Type.Float, Ash.Type.Decimal] ->
        bounds(constraints, "any")

      is_atom(type) and Ash.Type.NewType.new_type?(type) ->
        of(type.subtype_of(), Ash.Type.NewType.constraints(type, constraints))

      true ->
        @none
    end
  end

  # ## The length of text
  #
  # A text with a `max_length` has a counter beside its control: how long
  # the text is now, and the most it can be ("12/30"). It describes as the
  # limits of a number do, and stops nothing: a longer text is typed, sent
  # and refused by Ash. It is there for a maximum only, and says nothing of
  # `min_length` or `match`.
  #
  # The counter counts as Ash does, so that the two never disagree
  # (`Ash.Type.String`, `Ash.Type.CiString`, ash 3.34): the text is trimmed
  # first unless `trim?` is false, a `:ci_string` with a `casing` is folded
  # before that, and what is left is counted in the unit of `length_count`:
  # graphemes, codepoints or bytes. Without one it is Ash's default, which
  # the application configures (`config :ash, :default_string_length_count`:
  # `Ash.Type.String.default_length_count/0`). The browser counts the same
  # way while a person types (the grid's hook), from what `counted/1` says.

  @typedoc """
  How the length of a text is counted, and the most it can be: `max`, in
  `unit`s, of the text once it is trimmed (`trim?`) and, for a `:ci_string`
  that folds its case, folded (`casing`).
  """
  @type counted :: %{
          max: non_neg_integer,
          unit: :graphemes | :codepoints | :bytes,
          trim?: boolean,
          casing: :lower | :upper | nil
        }

  @doc """
  How the text of an input, a field of a map cell, an argument or a column
  is counted, where its type says the most it can be long (`max_length`).
  Nil for everything else. For an array, that of each of its values.
  """
  @spec counted(%{:type => {Ash.Type.t() | nil, keyword}, optional(atom) => term}) ::
          counted | nil
  def counted(%{type: {type, constraints}}), do: counted(type, constraints)

  @doc "The same, of an Ash type with its constraints."
  @spec counted(Ash.Type.t() | nil, keyword) :: counted | nil
  def counted({:array, type}, constraints), do: counted(type, constraints[:items] || [])
  def counted(nil, _constraints), do: nil

  def counted(type, constraints) do
    type = Ash.Type.get_type(type)

    cond do
      type in [Ash.Type.String, Ash.Type.CiString] ->
        with max when is_integer(max) <- constraints[:max_length] do
          %{
            max: max,
            unit: constraints[:length_count] || Ash.Type.String.default_length_count(),
            trim?: Keyword.get(constraints, :trim?, true),
            casing: if(type == Ash.Type.CiString, do: constraints[:casing])
          }
        end

      is_atom(type) and Ash.Type.NewType.new_type?(type) ->
        counted(type.subtype_of(), Ash.Type.NewType.constraints(type, constraints))

      true ->
        nil
    end
  end

  @doc """
  How long a text is, counted as `counted` says: as Ash counts it when it
  checks `max_length`. What is no text is as long as nothing.
  """
  @spec count(term, counted) :: non_neg_integer
  def count(%Ash.CiString{} = text, counted), do: count(Ash.CiString.value(text), counted)

  def count(text, %{unit: unit, trim?: trim?, casing: casing}) when is_binary(text) do
    text =
      case casing do
        :lower -> String.downcase(text)
        :upper -> String.upcase(text)
        nil -> text
      end

    text = if trim?, do: String.trim(text), else: text

    Ash.Query.Function.StringLength.string_length(text, unit)
  end

  def count(_no_text, _counted), do: 0

  defp bounds(constraints, step) do
    %{min: number(constraints[:min]), max: number(constraints[:max]), step: step}
  end

  # A number as HTML writes one: digits, with a point where it has a
  # fraction. Anything else is no bound a control could have.
  defp number(number) when is_integer(number), do: Integer.to_string(number)
  defp number(number) when is_float(number), do: Float.to_string(number)

  defp number(%Decimal{coef: coef} = number) when is_integer(coef),
    do: Decimal.to_string(number, :normal)

  defp number(_none), do: nil
end
