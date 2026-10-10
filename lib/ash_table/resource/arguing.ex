defmodule AshTable.Resource.Arguing do
  @moduledoc false
  # What a table has to be given before it reads, and by whom: the arguments
  # of the read action behind it, and those of the calculations its columns
  # show. Shared by the verifiers (which report a mistake) and the table
  # model (which builds on the answer).
  #
  # An argument of the read action is the person's to give: every public
  # one has an input in the argument line, and nothing is declared for it. A
  # private argument is never given from the outside.
  #
  # An argument of a calculation is given by the block: fixed with
  # `arguments`, or asked from the person with `ask`, which puts it on the
  # argument line as well. One that is given neither way is left to its
  # default in the resource.

  alias Ash.Resource.Info
  alias AshTable.Resource.Acting

  # The controls the argument line has: those of a cell and of a field of
  # the action panel that hold one value, or a list of such values. A value
  # made of fields (an embedded resource, a map) has none there.
  @controls [:text, :number, :boolean, :date, :datetime, :enum, :plain, :choices, :list]

  @type input :: Acting.input()

  @type reason ::
          {:no_input, :read, atom, input}
          | {:not_an_argument, atom, atom}
          | {:not_a_calculation, atom, :as | :arguments | :ask}
          | {:as_is_a_field, atom, atom}
          | {:unknown_argument, atom, atom, :arguments | :ask}
          | {:fixed_and_asked, atom, atom}
          | {:asked_twice, atom, atom}
          | {:invalid_value, atom, atom, term, :arguments | :default}
          | {:required_argument, atom, atom}
          | {:asked_without_default, atom, atom}
          | {:no_input, :ask, atom, input}

  @doc """
  The arguments of a read action that a person gives, in the action's order:
  its public arguments, each as an input with the control the argument line
  has for it (`editor`, nil when it has none).
  """
  @spec inputs(Ash.Resource.Actions.Read.t()) :: [input]
  def inputs(%{arguments: arguments}) do
    for %{public?: true} = argument <- arguments, do: input(argument)
  end

  @doc "An argument, of a read action or of a calculation, as an input of the argument line."
  @spec input(struct) :: input
  def input(argument) do
    input = Acting.argument(argument)
    %{input | editor: control(input)}
  end

  # a list of boxes that are ticked or not says nothing of how many there are
  defp control(%{editor: :list, cell_type: {:array, :boolean}}), do: nil
  defp control(%{editor: editor}) when editor in @controls, do: editor
  defp control(_input), do: nil

  @doc """
  The arguments of a read action that it cannot run without and that the
  argument line has no input for: public, not to be left empty, without a
  default. A table could never read through such an action.
  """
  @spec unanswerable(Ash.Resource.Actions.Read.t()) :: [input]
  def unanswerable(action) do
    for %{editor: nil, name: name} = input <- inputs(action), needed?(action, name), do: input
  end

  defp needed?(action, name), do: needed?(Enum.find(action.arguments, &(&1.name == name)))

  @doc "Whether an argument has to be given: it cannot be empty, and has no default."
  @spec needed?(struct) :: boolean
  def needed?(argument), do: argument.allow_nil? == false and is_nil(argument.default)

  @doc """
  What is wrong with the `argument`s a block declares, for the read action
  behind the table: one that names no public argument of it.
  """
  @spec declared_mistakes(Ash.Resource.Actions.Read.t(), [AshTable.Resource.Argument.t()]) ::
          [{AshTable.Resource.Argument.t(), reason}]
  def declared_mistakes(action, declared) do
    names = for %{public?: true, name: name} <- action.arguments, do: name

    for %{name: name} = declaration <- declared, name not in names do
      {declaration, {:not_an_argument, action.name, name}}
    end
  end

  @doc """
  What is wrong with how a column gives the arguments of its field, each
  with the option it is about. `column` is the column as written in the
  block, nil for a column of the default set.

  Only a calculation takes arguments, and only its column has another name
  (`as`). An argument is fixed or asked, not both, asked once, and is one
  the calculation has. A fixed value, and the default of an asked argument when
  it is a value, is one of the argument's type. An argument the calculation
  cannot be computed without is given one way or the other, and one that is
  asked and cannot be empty has a default: the block's, or the resource's.
  """
  @spec mistakes(Ash.Resource.t() | Spark.Dsl.t(), struct, AshTable.Resource.Column.t() | nil) ::
          [{:as | :arguments | :ask | nil, reason}]
  def mistakes(_resource, %Ash.Resource.Calculation{} = calculation, nil) do
    for %{name: name} = argument <- calculation.arguments, needed?(argument) do
      {nil, {:required_argument, calculation.name, name}}
    end
  end

  def mistakes(resource, %Ash.Resource.Calculation{} = calculation, column) do
    fixed = column.arguments || []
    asks = column.asks || []
    asked = Enum.map(asks, & &1.name)

    as =
      if column.as && Info.field(resource, column.as),
        do: [{:as, {:as_is_a_field, calculation.name, column.as}}],
        else: []

    unknown =
      for {option, names} <- [arguments: Keyword.keys(fixed), ask: asked],
          name <- names,
          is_nil(argument(calculation, name)) do
        {option, {:unknown_argument, calculation.name, name, option}}
      end

    both =
      for name <- Enum.uniq(asked),
          Keyword.has_key?(fixed, name),
          not is_nil(argument(calculation, name)) do
        {:ask, {:fixed_and_asked, calculation.name, name}}
      end

    twice =
      for name <- Enum.uniq(asked -- Enum.uniq(asked)) do
        {:ask, {:asked_twice, calculation.name, name}}
      end

    invalid_fixed =
      for {name, value} <- fixed,
          argument = argument(calculation, name),
          not value?(argument, value) do
        {:arguments, {:invalid_value, calculation.name, name, value, :arguments}}
      end

    asked_mistakes =
      for %{name: name} = ask <- asks,
          argument = argument(calculation, name),
          not Keyword.has_key?(fixed, name),
          reason <- ask_mistakes(calculation, argument, ask) do
        {:ask, reason}
      end

    missing =
      for %{name: name} = argument <- calculation.arguments,
          needed?(argument),
          not Keyword.has_key?(fixed, name),
          name not in asked do
        {nil, {:required_argument, calculation.name, name}}
      end

    as ++ unknown ++ both ++ twice ++ invalid_fixed ++ asked_mistakes ++ missing
  end

  def mistakes(_resource, %{name: name}, column) do
    for {option, given?} <- [
          as: not is_nil(column && column.as),
          arguments: not is_nil(column && column.arguments),
          ask: (column && column.asks) not in [nil, []]
        ],
        given? do
      {option, {:not_a_calculation, name, option}}
    end
  end

  defp ask_mistakes(calculation, argument, ask) do
    input = input(argument)

    cond do
      is_nil(input.editor) ->
        [{:no_input, :ask, calculation.name, input}]

      match?({:value, _value}, block_default(ask)) and
          not value?(argument, elem(block_default(ask), 1)) ->
        [
          {:invalid_value, calculation.name, argument.name, elem(block_default(ask), 1), :default}
        ]

      argument.allow_nil? == false and default(argument, ask) == :none ->
        [{:asked_without_default, calculation.name, argument.name}]

      true ->
        []
    end
  end

  @doc "The argument of that name of a calculation, or nil."
  @spec argument(Ash.Resource.Calculation.t(), atom) :: struct | nil
  def argument(%Ash.Resource.Calculation{arguments: arguments}, name),
    do: Enum.find(arguments, &(&1.name == name))

  @doc """
  What an asked argument is while the person has chosen nothing, the first
  that is there: the default of its `ask`, a value or a function of the
  assigns of the page, then the default the argument has in the resource,
  which may be computed as well. `:none` when it has neither.
  """
  @spec default(struct, AshTable.Resource.Ask.t()) ::
          {:value, term} | {:function, (map -> term)} | :none
  def default(argument, ask) do
    with :none <- block_default(ask) do
      case argument.default do
        nil ->
          :none

        fun when is_function(fun, 0) ->
          {:function, fn _assigns -> fun.() end}

        {module, function, args} = mfa ->
          if(mfa?(mfa), do: called(module, function, args), else: {:value, mfa})

        value ->
          {:value, value}
      end
    end
  end

  defp called(module, function, args),
    do: {:function, fn _assigns -> apply(module, function, args) end}

  defp block_default(%{default: nil}), do: :none
  defp block_default(%{default: fun}) when is_function(fun, 1), do: {:function, fun}

  defp block_default(%{default: {module, function, args} = default}) do
    if mfa?(default),
      do: {:function, fn assigns -> apply(module, function, [assigns | args]) end},
      else: {:value, default}
  end

  defp block_default(%{default: value}), do: {:value, value}

  defp mfa?({module, function, args}),
    do: is_atom(module) and is_atom(function) and is_list(args)

  # Whether a value the block gives is one the argument takes: what Ash
  # makes of it when the calculation is loaded with it. An expression is
  # known only when it is computed.
  defp value?(argument, value) do
    cond do
      Ash.Expr.expr?(value) ->
        Map.get(argument, :allow_expr?, false)

      is_nil(value) ->
        argument.allow_nil? != false

      true ->
        constraints = argument.constraints || []

        with {:ok, cast} <- Ash.Type.cast_input(argument.type, value, constraints),
             {:ok, cast} <- Ash.Type.apply_constraints(argument.type, cast, constraints) do
          not is_nil(cast) or argument.allow_nil? != false
        else
          _refused -> false
        end
    end
  end

  @doc "What is wrong, for a diagnostic."
  @spec message(reason) :: String.t()
  def message({:no_input, :read, action, %{name: name, type: {type, _constraints}}}),
    do:
      "The read action `#{action}` requires the argument `#{name}`, and a table has no input " <>
        "for its type (#{inspect(type)}), so it could never read. " <>
        controls() <>
        " Give the argument a default, or name another read action with `read_action`."

  def message({:no_input, :ask, calculation, %{name: name, type: {type, _constraints}}}),
    do:
      "The argument `#{name}` of the calculation `#{calculation}` cannot be asked: a table " <>
        "has no input for its type (#{inspect(type)}). " <>
        controls() <>
        " Fix its value with `arguments` instead."

  def message({:not_an_argument, action, name}),
    do:
      "The read action `#{action}` has no public argument named `#{name}`. An `argument` " <>
        "says what an argument of the read action behind the table is called."

  def message({:not_a_calculation, name, :as}),
    do:
      "`#{name}` is not a calculation, so `as` has no effect. `as` names the second column " <>
        "of a calculation that the table shows more than once, with other arguments."

  def message({:not_a_calculation, name, :arguments}),
    do: "`#{name}` is not a calculation. Only a calculation takes arguments."

  def message({:not_a_calculation, name, :ask}),
    do:
      "`#{name}` is not a calculation. Only an argument of a calculation can be asked; an " <>
        "argument of the read action is on the argument line without a declaration."

  def message({:as_is_a_field, calculation, as}),
    do:
      "`#{as}` is a field of the resource, so the column of `#{calculation}` cannot be " <>
        "called that. `as` gives a column a name that nothing else has."

  def message({:unknown_argument, calculation, name, _option}),
    do: "The calculation `#{calculation}` has no argument named `#{name}`."

  def message({:fixed_and_asked, calculation, name}),
    do:
      "The argument `#{name}` of `#{calculation}` is fixed with `arguments` and asked with " <>
        "`ask`. It is one or the other: to ask it and start with a value, say " <>
        "`ask :#{name}, default: …`."

  def message({:asked_twice, calculation, name}),
    do: "The argument `#{name}` of `#{calculation}` is asked more than once."

  def message({:invalid_value, calculation, name, value, :arguments}),
    do:
      "`#{inspect(value)}` is not a value of the argument `#{name}` of the calculation " <>
        "`#{calculation}`."

  def message({:invalid_value, calculation, name, value, :default}),
    do:
      "`#{inspect(value)}`, the default of `ask :#{name}`, is not a value of the argument " <>
        "`#{name}` of the calculation `#{calculation}`."

  def message({:required_argument, calculation, name}),
    do:
      "The calculation `#{calculation}` requires the argument `#{name}`, and the column gives " <>
        "it neither way. Fix it with `arguments #{name}: …`, or let the person give it with " <>
        "`ask :#{name}, default: …`."

  def message({:asked_without_default, calculation, name}),
    do:
      "The argument `#{name}` of `#{calculation}` is asked and cannot be empty, and has no " <>
        "default: neither on its `ask` nor in the resource. A column never starts without a " <>
        "value: say `ask :#{name}, default: …`."

  defp controls,
    do:
      "The argument line has inputs for text, numbers, booleans, dates, datetimes, choices, " <>
        "arrays of those, and values written as one line of text, such as a key."
end
