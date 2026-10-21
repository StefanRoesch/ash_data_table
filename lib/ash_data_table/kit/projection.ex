defmodule AshDataTable.Kit.Projection do
  @moduledoc """
  What a part of a table is given to draw (ADR 0004): one finished,
  plain-data projection per part, made by the table and the same for
  every kit, so that a kit only draws. A projection holds values (looked
  up already), texts and the messages they are made of, bundles (the
  attribute maps of `AshDataTable.Attrs`, string keys, which a kit
  spreads on an element), the facts derived from them, and the
  projections of the parts drawn inside it. It never holds a record, a
  form, an `AshDataTable.Model`, an `AshDataTable.State` or a struct of
  `AshDataTable.Present`, nor a value of a sensitive field, and it goes to
  JSON as it is, but for a column's component (`component`: its `module`
  and `column`, an `AshDataTable.Component.Column`, the component's own
  contract), which a bridge encodes as a stream item's component value is
  (ADR 0002).

  A part is given its projection an assign per key (`AshDataTable.Kit`,
  "What a part is given"): the table makes each key of what that key is
  made of, so that LiveView sends a key again only when what it is made of
  changed. The parts drawn inside another are given their projections by
  the part that draws them, out of its own (the cells of `grid`'s `head`,
  the fields of `panel`, …). The rows are not in any projection: they are
  the table's stream (`AshDataTable.Item`).

  Wherever a projection shows words it has `texts` (by name, the finished
  strings in the person's language) and `messages` (the same names, each
  the message `%{key:, values:}` of `AshDataTable.Messages` it was made
  of; a name may hold a list, and nil where nothing is shown there), or
  `text` and `message` alone in a projection of one text; `locale` where a
  value is shown. A bundle's id, nil and false are left out where it is
  spread; nil stands for "none" where a key may hold nothing.

  ## Drawn once per table

  ### `root`

    * `element` - the root's bundle (`data-read` once it has read)
    * `skip_target` - where "Skip table" jumps to, after the table
    * `nested?` - whether the table is shown inside another (nested in a
      row, or a picker's)
    * `look` - the table's look, every option of it (`AshDataTable.Kit`,
      "The look of a table")

  ### `heading`

    * `shown?` - whether the line is drawn at all
    * `nested?` - whether it is a nested table's, on its line
    * `element` - the line's bundle
    * `title` - the table's name: `element`, `level` (a heading's level,
      nil for a plain element) and `text`; nil for none
    * `columns` - the projection of `columns`, nil where no column can be
      hidden
    * `argument_line` - the projection of `argument_line`, nil for a table
      without arguments
    * `acts?` - whether it offers create or table actions
    * `create` - create's `label` and `button`, nil for none
    * `actions` - the table actions, each its `name`, `label` and `button`

  ### `related`

    * `element`, `heading` - the bundles of the part and its heading
    * `record` - the record the heading names: `id`, `path` (of its own
      table's page, nil for none) and `title`; nil where the heading does
      not name it
    * `create`, `actions` - as `heading`'s
    * `clear` - "Show all records": `id` and `path`
    * `texts`, `messages` - `relationship`, `heading`, `heading_before`,
      `heading_after` (its words before and after the record),
      `show_all_records`

  ### `selection_line`

    * `shown?` - whether anything is on the line
    * `nested?` - whether it is a nested table's
    * `selection` - where several rows are selected: the bundles `group`,
      `selected`, `controls`, `select_all`, `clear`; `inline`, the actions
      on the line (each its `name`, `label`, `destroys?` and `button`);
      `more`, the menu of the others (`button`, `menu`, `actions`), nil for
      none; `running?`, whether an action runs on the selection; else nil
    * `notice` - the notice of changes, its `element` and the `read_again`
      button; nil for none
    * `clear_filters` - "Clear filters", nil while no filter is set
    * `texts`, `messages` - `select_all`, `selected_rows`, `selected` (nil
      for nothing), `clear_selection`, `more_actions`, `clear_filters`,
      `changed_records`, `read_again`

  ### `status`

    * `region` - the live region's bundle
    * `again?` - whether the announcement ends in a no-break space (a live
      region is read out when what it holds changes)
    * `result` - a run's result, its `id`; nil for none
    * `texts`, `messages` - `announcement`, `summary`, `failures`

  ### `grid`

    * `nested?` - whether it is a nested table's
    * `sender`, `skip`, `scrollbar` - the bundles of the grid's sender, its
      skip link and the scrollbar at the bottom edge of the window
    * `filter_form` - the filter row's form, nil for none
    * `grid`, `table` - the bundles of the grid's hook's element and the
      `role=table` element
    * `head` - the header row: `row`, `select` (the box's header: its
      `element` and `page?`, whether a box stands for the page; nil for
      none), `expander` and `actions` (bundles, nil for none), `cells` (a
      `header_cell` projection per column), `texts`, `messages`
    * `filters` - the filter row, nil for none: `row`, `select`,
      `expander`, `actions` (bundles, nil for none), `cells` (a
      `filter_cell` projection per column)
    * `row` - the projection of `row`, which every row is drawn with
    * `footer` - the projection of `footer`, nil for none
    * `editors` - per editable column its template: `name`, `template`
      (its bundle), `editor` (the projection of `editor`, nil where the
      cell has no editor of the kit's in it) and `component` (a component's
      editor: `module`, `column`, `label`, `limits`, `control`; else nil)
    * `failure` - the failure template: `template`, `text`, `message`; nil
      where nothing is edited or acted on
    * `texts`, `messages` - `skip_table`, `select_page`, `select_row`,
      `related_records`, `actions`, `show_whole`, `show_less`,
      `show_whole_of`, `show_less_of`, `hidden_value`, `show`, `hide`,
      `show_value` and `hide_value` (one per column, nil where it is not
      sensitive), `not_available`, `yes`, `no`

  ### `message`

  One per message said in place of the rows:

    * `kind` - `:error`, `:loading`, `:fill` or `:empty`
    * `element` - its bundle (`role=alert` of an error)
    * `nested?` - whether it is a nested table's
    * `text`, `message`

  ### `pagination`

    * `nested?` - whether it is a nested table's (in its footer)
    * `element` - its bundle
    * `range` - the range's bundle
    * `previous`, `next` - their buttons' bundles
    * `pages` - the page numbers, where pages are counted: each its
      `number`, `current?` and `button`
    * `sizes` - "Rows per page": `form`, `label`, `select` (bundles) and
      `options` (each `size` and `chosen?`); nil for none
    * `texts`, `messages` - `label`, `range`, `previous`, `next`,
      `rows_per_page`, `go_to_page` (one per page number)

  ### `confirm`

    * `asks?` - whether the table asks anything at all
    * `presentation` - `:modal` or `:inline`
    * `holder`, `dialog`, `question` - the bundles of what holds the
      dialog (a patch leaves it alone), the dialog and where the hook
      writes the question
    * `texts`, `messages` - `cancel`, `confirm`

  ### `panel`

    * `open?` - whether the panel is open (drawn closed too)
    * `presentation` - `:modal` or `:inline`
    * `destructive?` - whether its action destroys
    * `place` - where what opens inside it is moved into
    * `frame`, `form` - its bundle and its form's, nil while closed
    * `title`, `cancel`, `submit` - their bundles
    * `errors` - the element of what is said of none of its fields, nil
      for none
    * `fields` - a `field` projection per field
    * `texts`, `messages` - `title`, `submit`, `question`, `errors`,
      `cancel`

  ### `picker`

    * `open?`, `presentation`, `place`, `frame` - as `panel`'s
    * `title`, `cancel` - their bundles
    * `error` - where a choice named no record this person may read, nil
      for none
    * `none`, `take` - "None" and "Choose", nil for none
    * `texts`, `messages` - `title`, `question`, `error`, `cancel`,
      `choose_none`, `choose`

  ### `full_view`

    * `row`, `cell` - the bundles of its row and its cell
    * `link` - the link: `id` and `path`
    * `texts`, `messages` - `full_view`, `full_view_of`

  ## Drawn inside another

  ### `columns`

    * `control`, `button`, `text`, `count`, `list`, `status`, `reset` -
      the bundles of its elements
    * `label` - the label column's entry, `label` and `width`; nil for none
    * `entries` - per column that can be hidden: `name`, `label`, `flag`
      (what it says while hidden, nil for nothing), `entry`, `box` and
      `width` (bundles)
    * `least`, `most` - the least and the most a width field takes
    * `texts`, `messages` - `columns`, `columns_name`, `columns_with`,
      `columns_hidden`, `columns_filtered`, `columns_sorted`,
      `column_hidden`, `column_shown`, `width_of`, `label_width`,
      `reset_widths`, `flags`

  ### `argument_line`

    * `form` - the form's bundle
    * `nested?` - whether it is a nested table's
    * `arguments` - an `argument` projection per argument

  ### `argument`

    * `id`, `named`, `name` - its control's id, what it is called in the
      page's ids, what it is sent under
    * `label`, `editor`, `item`, `required?` - its label, its control, an
      array's values' type, whether it is required
    * `values` - an enum's values (`value`, `label`), nil for none
    * `value` - what it holds: text, or of an array the list of its values
    * `invalid?` - whether Ash refused it
    * `limits`, `counted` - the limits of a number, the counter of a text
    * `element` - its bundle (`data-argument`)
    * `described` - what its control names as its description, nil for
      nothing
    * `error` - its errors' element, nil for none
    * `count` - its counter's projection, nil for none
    * `group` - an array's group: `label` (bundle) and `labelledby`; nil
    * `rows` - of an array given value by value, per value its `value`,
      `id`, `described`, `count` and `remove` (bundle)
    * `add` - the button that adds a value, nil for none
    * `texts`, `messages` - `add_value`, `errors`, `value_position`,
      `remove_value`

  ### `count`

    * `element` - its bundle (`data-count`, `data-max`, …, `data-over`)
    * `length`, `max` - how long the text is, as Ash counts it, and the
      most it may be
    * `over?` - whether it is too long

  ### `header_cell`

    * `element` - its bundle (id, place, name, `aria-sort`, …)
    * `label` - the column's label
    * `button` - the sort button's bundle, nil where it does not sort
    * `mark` - the mark of the sort
    * `resizer` - the projection of `resizer`
    * `texts`, `messages` - `read_only` (the lock's name, nil for none)

  ### `resizer`

    * `element` - its bundle

  ### `filter_cell`

    * `element` - its bundle (`data-filter` where the column filters)
    * `filter` - the projection of `filter`, nil where it does not filter

  ### `filter`

    * `cell_type` - what the column's values are (an array's
      `%{array: item}`)
    * `takes` - what its operator takes: `:none`, `:one`, `:many`, `:range`
    * `yes_no`, `operators`, `choice` - a boolean's menu, the operators'
      menu, an enum's menu: each `select` (bundle) and `options` (`value`,
      `label`, `chosen?`); nil for none
    * `input` - the typed value's bundle, nil for none
    * `range` - the two ends of a range, each its `word` and `input`; nil
    * `several` - several values: the button (`button`), what it says
      (`says`) and the values that apply (`hidden`, bundles); nil
    * `clear` - the clear button, nil for none
    * `error` - the element of what is said of a value it refused, nil
    * `texts`, `messages` - `filter`, `filter_operator`, `any`,
      `operators`, `range_from`, `range_to`, `filter_from`, `filter_to`,
      `clear_filter`, `invalid_filter`, `chosen`

  ### `row`

    * `selecting` - `:single`, `:multi` or nil
    * `radio` - the name of the radio buttons' group, nil
    * `expandable?`, `lead` - whether rows expand, the expander's place
    * `columns` - per column the projection of `cell`
    * `actions` - the actions cell: `colindex`, `open` ("Open", nil for
      none) and `buttons` (each `name`, `label`, `attrs`); nil for none
    * `relationships` - the lines' relationships: `name`, `label`, `cell`
      (the line's cell's bundle)
    * `colspan` - how wide a line is
    * `texts`, `messages` - `select_row`, `related_records`

  ### `cell`

  What a cell of a column is drawn with, the same on every row, beside the
  item's cell:

    * `name`, `label` - the column's
    * `colindex` - where it stands
    * `header?` - whether it is the row's header (the label column)
    * `cell_type`, `editor`, `max_lines` - what its values are, what it is
      edited with, how many lines it shows
    * `sensitive?` - whether its cells are masked
    * `values` - an enum's values (`value`, `label`, `chosen?`), nil
    * `attrs` - its cells' attributes that are the column's
    * `component` - the component that draws its cells: `module` and
      `column`; nil
    * `typed` - what a failed cell shows of what was typed, by what was
      typed; nil where it shows it as it is
    * `texts`, `messages` - `hidden_value`, `show`, `hide`, `show_value`,
      `hide_value`, `not_available`
    * `locale`

  ### `actions_cell`

    * `colindex`, `open`, `buttons` - as `row`'s `actions`

  ### `detail`

    * `relationships`, `colspan` - as `row`'s

  ### `line`

    * `relationship` - as `row`'s `relationships`
    * `line` - the item's line (`open`, `count`, `text`, …)
    * `colspan` - how wide it is
    * `table` - the nested table's id

  ### `footer`

    * `element` - its bundle (`hidden` while it shows nothing)
    * `summaries` - the row of the summaries: `row`, `select`, `expander`,
      `actions` (bundles, nil for none) and `cells` (a `summary_cell`
      projection per column); nil for none
    * `pager` - a nested table's pages: `row`, `cell` and `pagination` (the
      projection of `pagination`); nil
    * `full_view` - the projection of `full_view`, nil

  ### `summary_cell`

    * `element` - its bundle
    * `summary?` - whether the column has a summary
    * `state` - `:ok`, `:unavailable`, or nil while there is no answer yet
    * `value`, `text` - the summary's value and its words
    * `texts`, `messages` - `kind`, `not_available`
    * `locale`

  ### `editor`

    * `id` - its template's id
    * `label`, `editor`, `required?`, `sensitive?`, `values` - the
      column's
    * `limits`, `counted` - the limits of a number, the counter of a text
    * `count` - the counter's projection, nil
    * `control` - the control's bundle where the table gives one, nil
    * `clearable?` - whether a sensitive cell can be emptied
    * `texts`, `messages` - `clear`, `clear_value`

  ### `failure`

    * `text`, `message`

  ### `field`

    * `id`, `name`, `path` - its control's id, what it is sent under, the
      names on the way to it
    * `element` - its bundle (`data-field`)
    * `editor`, `label`, `required?`, `secret?`, `item` - its control, its
      label, whether it is required, typed hidden, an array's values' type
    * `values` - an enum's values (`value`, `label`, `chosen?`), nil
    * `value` - what it holds as its form sends it (of a sensitive field
      what was typed into it in this panel)
    * `boxless` - what a multiple choice holds that is none of its values
    * `invalid?`, `places` - whether something is said at it, the places
      of an array's values it is about (`data-invalid`), nil
    * `limits`, `counted` - the limits of a number, the counter of a text
    * `described` - what its control names as its description, nil
    * `labelled?` - whether its label is for one control
    * `group_label`, `labelledby` - a group's label (bundle, nil) and its id
    * `error` - its errors' element, nil
    * `reference` - one key chosen: `chosen` (its `element` and `text`, nil)
      and `choose`; nil
    * `references` - several: `entries` (each `key`, `element`, `text`,
      `unpick`) and `choose`; nil
    * `list` - the projection of `list`, nil
    * `file` - a file: `name` (its upload's, among the part's `uploads`),
      `ref`, `accept`, `multiple?`, `label` and `entries` (each `ref`,
      `name`, `progress`, `done?`, `cancelled?`, `sending?`); nil
    * `component` - a component's editor: `module`, `column` and `control`;
      nil
    * `control` - the projection of `control`, nil
    * `clear` - a sensitive field's Clear: `asked?`, `cleared` and `button`;
      nil
    * `count` - its counter's projection, nil
    * `group` - a value made of fields: `label`, `members` (its `hidden`
      entries and `fields`, nil for no value), `add`, `remove`; nil
    * `groups` - a list of them: `label`, `items` (each `key`, `element`,
      `label`, `labelledby`, `error`, `remove`, `members`), `hidden`, `add`;
      nil
    * `union` - a union: `label`, `hidden`, `kind`, `choice`,
      `kind_label`, `select`, `empty?`, `kinds` (`value`, `label`,
      `chosen?`), `own_errors?`, `single` (a field) and `members`; nil
    * `texts`, `messages` - `required`, `choose`, `add_value`, `kind`,
      `remove_group`, `will_be_cleared`, `keep`, `clear`, `keep_value`,
      `clear_value`, `errors`, `chosen`, `remove_chosen`, and of a list of
      groups `value_position`, `remove_value`, `item_errors`
    * `locale`

  ### `control`

    * `id`, `name`, `value`, `editor` - as its field's
    * `secret?`, `invalid?`, `required?`, `described`, `limits`, `values` -
      as its field's

  ### `list`

    * `element` - its bundle (`data-list`, which a patch leaves alone)
    * `item`, `limits`, `name` - what its values are, their limits, what
      each is sent under
    * `template`, `rows` - the template's row and a row per value, each its
      `value`, `position` and `count`
    * `texts`, `messages` - `add_value`, `value_label`, `remove_label`,
      `value_position`, `remove_value`
  """

  alias AshDataTable.Kit.Projection

  @parts %{
    status: Projection.Status,
    message: Projection.Message,
    confirm: Projection.Confirm,
    pagination: Projection.Pagination,
    picker: Projection.Picker,
    related: Projection.Related,
    full_view: Projection.FullView,
    selection_line: Projection.SelectionLine,
    heading: Projection.Heading,
    panel: Projection.Panel,
    grid: Projection.Grid,
    root: Projection.Root
  }

  @doc false
  # The projection of `part`, made of `inputs`: the entry fields that part
  # depends on. `{part, key}` is one key of it, made of the inputs that key
  # depends on, which the drawing gives one by one: LiveView sends a key
  # again only when what it is made of changed. `:message` gives a list,
  # one per message the table says now.
  def of({part, key}, inputs) do
    module = Map.fetch!(@parts, part)
    inputs = plain(inputs)

    if keyed?(module),
      do: module.key(key, inputs),
      else: Map.fetch!(module.of(inputs), key)
  end

  def of(part, inputs) do
    module = Map.fetch!(@parts, part)
    inputs = plain(inputs)

    if keyed?(module),
      do: Map.new(module.keys(), &{&1, module.key(&1, inputs)}),
      else: module.of(inputs)
  end

  # The component the events go to (`phx-target`, a table placed with the
  # tag: LiveView's `@myself`) as the number LiveView writes of it, so that
  # a bundle holds plain data and goes to JSON as it is; LiveView takes the
  # number for the component, in an attribute and in a `JS.push`.
  defp plain(%{target: %_{} = target} = inputs), do: plain(%{inputs | target: number(target)})
  defp plain(%{myself: %_{} = myself} = inputs), do: plain(%{inputs | myself: number(myself)})
  defp plain(inputs), do: inputs

  defp number(component), do: component |> to_string() |> String.to_integer()

  # The parts drawn inside another, whose projections are in that one's
  # (question 25 of the design note): the keys of each.
  @inner %{
    columns: [
      :control,
      :button,
      :text,
      :count,
      :list,
      :status,
      :label,
      :entries,
      :reset,
      :least,
      :most,
      :texts,
      :messages
    ],
    argument_line: [:form, :nested?, :arguments],
    argument: [
      :id,
      :named,
      :name,
      :label,
      :editor,
      :item,
      :required?,
      :values,
      :value,
      :invalid?,
      :limits,
      :counted,
      :element,
      :described,
      :error,
      :count,
      :group,
      :rows,
      :add,
      :texts,
      :messages
    ],
    count: [:element, :length, :max, :over?],
    field: [
      :id,
      :name,
      :path,
      :element,
      :editor,
      :label,
      :required?,
      :secret?,
      :item,
      :values,
      :value,
      :boxless,
      :invalid?,
      :places,
      :limits,
      :counted,
      :described,
      :labelled?,
      :group_label,
      :labelledby,
      :error,
      :reference,
      :references,
      :list,
      :file,
      :component,
      :control,
      :clear,
      :count,
      :group,
      :groups,
      :union,
      :texts,
      :messages,
      :locale
    ],
    control: [
      :id,
      :name,
      :value,
      :editor,
      :secret?,
      :invalid?,
      :required?,
      :described,
      :limits,
      :values
    ],
    list: [:element, :item, :limits, :name, :template, :rows, :texts, :messages],
    header_cell: [:element, :label, :button, :mark, :resizer, :texts, :messages],
    resizer: [:element],
    filter_cell: [:element, :filter],
    filter: [
      :cell_type,
      :takes,
      :yes_no,
      :operators,
      :choice,
      :input,
      :range,
      :several,
      :clear,
      :error,
      :texts,
      :messages
    ],
    row: [
      :selecting,
      :radio,
      :expandable?,
      :lead,
      :columns,
      :actions,
      :relationships,
      :colspan,
      :texts,
      :messages
    ],
    cell: [
      :name,
      :label,
      :colindex,
      :header?,
      :cell_type,
      :editor,
      :max_lines,
      :sensitive?,
      :values,
      :attrs,
      :component,
      :typed,
      :texts,
      :messages,
      :locale
    ],
    actions_cell: [:colindex, :open, :buttons],
    detail: [:relationships, :colspan],
    line: [:relationship, :line, :colspan, :table],
    footer: [:element, :summaries, :pager, :full_view],
    summary_cell: [:element, :summary?, :state, :value, :text, :texts, :messages, :locale],
    editor: [
      :id,
      :label,
      :editor,
      :required?,
      :sensitive?,
      :values,
      :limits,
      :counted,
      :count,
      :control,
      :clearable?,
      :texts,
      :messages
    ],
    failure: [:text, :message]
  }

  @doc false
  # The parts given a projection.
  def parts, do: Map.keys(@parts) ++ Map.keys(@inner)

  @doc false
  # The keys of the projection of `part`.
  def keys(part) when is_map_key(@inner, part), do: Map.fetch!(@inner, part)
  def keys(part), do: Map.fetch!(@parts, part).keys()

  # Whether a part's projection is made key by key (`key/2`), else whole
  # (`of/1`, a part drawn seldom, whose keys all change together).
  defp keyed?(module), do: Code.ensure_loaded!(module) && function_exported?(module, :key, 2)
end
