defmodule AshDataTable.Live.Drawing do
  @moduledoc false
  # What `AshDataTable.attached/1` draws (part 4): every table of one
  # `AshDataTable.Table`, through its kit (`AshDataTable.Kit`). It turns
  # what the core holds into the values each
  # part is given (`AshDataTable.Present`, the uploads of the panel, the
  # links), and calls the kit's parts in their order; the markup is the
  # kit's. The table on the page, its nested tables (each in a portal) and
  # the tables of its pickers (in the picker) are drawn with the kit of the
  # table on the page.
  use Phoenix.Component

  alias AshDataTable.Ids
  alias AshDataTable.Kit
  alias AshDataTable.Kit.Words
  alias AshDataTable.Live.Core.Files
  alias AshDataTable.Live.Core.Opener
  alias AshDataTable.Live.Core.Selection
  alias AshDataTable.Live.Core.Url
  alias AshDataTable.Live.Registry
  alias AshDataTable.Parts
  alias AshDataTable.Present
  alias AshDataTable.Routes

  # The table on the page, and after it the portals of the tables shown in
  # its rows and in theirs: each drawn here, at the top
  # of the template, where it follows its entry, and moved by the browser
  # into the cell of the row it belongs to (`<.portal>`), parents before
  # their children (`AshDataTable.Live.Registry.portals/1`). The two
  # elements around a nested table pin it to the left edge of the scroll
  # area around it (`data-ash-data-table-portal`, which names the cell:
  # what a test reads the page by, as the markup LiveView makes of a portal
  # is LiveView's own) and make it as wide as that area
  # (`data-ash-data-table-view`): the kit styles both by these markers (the
  # root's rules of `Kit.Default`), and gives the portal's wrapper its
  # class (`class(:portal, …)`, `display: contents` in `Kit.Default`).
  #
  # The root element of every table is the kit's `root/1`'s: of the table
  # on the page, of each nested table and of each picker's table. Only the
  # tag's live component, whose root must be a static tag, draws a plain
  # element around it (`AshDataTable.Live.Embedded`).
  attr :table, :any, required: true
  attr :streams, :any, required: true
  attr :uploads, :any, required: true

  def drawn(assigns) do
    ~H"""
    <.body
      entry={@table.entry}
      options={@table.options}
      time_zone={@table.caller.time_zone}
      rows={rows(@streams, @table.entry)}
      chooser={chooser(@table.entries, @table.entry.id, @table.entry.picker)}
      chooser_rows={rows(@streams, chooser(@table.entries, @table.entry.id, @table.entry.picker))}
      myself={@table.options.target}
      uploads={@uploads}
      router={@table.options.router}
    />
    <.nested
      :for={{entry, rows, placed} <- portals(@table, @streams)}
      :key={entry.id}
      entry={entry}
      rows={rows}
      placed={placed}
      uploads={@uploads}
    />
    """
  end

  # The two portals of a nested table: the table into the cell under its
  # line, and its heading line onto that line (`heading_target`), where
  # the line names it: the line of a nested table is its heading line, the
  # same as a table on the page has above its grid (the kit's
  # `heading/1`). Both are marked with the place they go into
  # (`data-ash-data-table-portal`).
  attr :entry, :any, required: true
  attr :rows, :any, required: true
  attr :placed, :any, required: true
  attr :uploads, :any, required: true

  defp nested(assigns) do
    ~H"""
    <.portal id={"#{@entry.id}-portal"} target={"[id='#{@entry.target}']"} class={@placed.class}>
      <div data-ash-data-table-portal={@entry.target}>
        <div data-ash-data-table-view>
          <.body
            :if={!@entry.gone?}
            entry={@entry}
            options={@placed.options}
            time_zone={@placed.time_zone}
            rows={@rows}
            chooser={@placed.chooser}
            chooser_rows={@placed.chooser_rows}
            myself={@placed.myself}
            uploads={@uploads}
            router={@placed.router}
          />
          <div :if={@entry.gone?} id={@entry.id} hidden></div>
        </div>
      </div>
    </.portal>
    <.portal
      :if={@entry.heading_target}
      id={"#{@entry.id}-heading-portal"}
      target={"[id='#{@entry.heading_target}']"}
      class={@placed.class}
    >
      <div data-ash-data-table-portal={@entry.heading_target}>
        <.heading
          :if={!@entry.gone?}
          entry={@entry}
          kit={@placed.options.kit}
          myself={@placed.myself}
        />
      </div>
    </.portal>
    """
  end

  # The heading line of a table (the kit's `heading/1`): above the grid of
  # the table on the page, on its line for a nested table.
  attr :entry, :any, required: true
  attr :kit, :atom, required: true
  attr :myself, :any, required: true
  attr :heading, :any, default: false

  defp heading(assigns) do
    ~H"""
    <Kit.part
      part={:heading}
      kit={@kit}
      heading={@heading}
      id={@entry.id}
      arguments={Kit.arguments(@entry.id, @entry.model, @entry.lines, @entry.state, @entry.refused)}
      label={@entry.label}
      model={@entry.model}
      myself={@myself}
      nested?={@entry.nested?}
      offered={@entry.offered}
      page={@entry.page}
      related={@entry.related}
      state={@entry.state}
    />
    """
  end

  # The uploads of the panel's file fields. A function component sees only
  # what it is given, and LiveView's uploads are not the table's to assign
  # a page that draws a table whose panel takes a file must give them.
  defp files!(entry, nil) do
    if AshDataTable.Panel.file_inputs(entry.panel) != [] do
      raise ArgumentError,
            "the action panel of the table #{inspect(entry.id)} takes a file, and " <>
              "AshDataTable.attached/1 was given no uploads: pass " <>
              "`uploads={assigns[:uploads]}` to `AshDataTable.attached`."
    end

    Files.panel_files(entry, nil)
  end

  defp files!(entry, uploads), do: Files.panel_files(entry, uploads)

  # The nested tables, parents first, each with the items of its stream and
  # what it is placed with (`placed`): a portal is rendered again only when
  # its table, its stream or what it is placed with changed. Nothing in the
  # portal reads `@table`, which changes with every table of the tree: each
  # portal's values are made here, and LiveView compares them portal by
  # portal (the variables of a keyed comprehension), so an event of one
  # table sends and patches that table's portal only.
  #
  # LiveView keeps a comprehension's variables until the next render, a
  # portal's stream among them: the rows a nested table was last sent with
  # stay in LiveView's change tracking until then. The table itself keeps
  # no rows.
  defp portals(table, streams) do
    options = %{table.options | url: nil, heading: false, mounted?: false}
    class = table.options.kit.class(:portal, %{})

    for entry <- Registry.portals(table) do
      chooser = chooser(table.entries, entry.id, entry.picker)

      {entry, streams[entry.stream],
       %{
         options: options,
         class: class,
         time_zone: table.caller.time_zone,
         chooser: chooser,
         chooser_rows: rows(streams, chooser),
         myself: table.options.target,
         router: table.options.router
       }}
    end
  end

  # The items of a table's stream, given to its grid whenever the table
  # changes: the grid's comprehension over them is then rendered again, with
  # nothing new in it but what the stream holds, as it was while every
  # table was a component of its own (`Phoenix.LiveViewTest` keeps the rows
  # of a stream where they are only then).
  defp rows(_streams, nil), do: nil

  defp rows(streams, entry), do: streams[entry.stream]

  # The table of the entry's open picker, which is moved into its place: of
  # the fields it is made of, so that LiveView draws what is given it again
  # only when one of them changes.
  defp chooser(_entries, _id, nil), do: nil
  defp chooser(entries, id, picker), do: Map.get(entries, "#{id}-pick-#{picker.name}")

  # The parts of one table, inside its root element: the table on the
  # page's, a nested table's in its portal, a picker's table in its picker.
  attr :entry, :any, required: true
  attr :options, :any, required: true
  attr :chooser, :any, required: true
  attr :chooser_rows, :any, required: true
  attr :time_zone, :any, required: true
  attr :rows, :any, required: true
  attr :myself, :any, required: true
  attr :uploads, :any, required: true
  attr :router, :any, required: true

  defp body(assigns) do
    ~H"""
    <Kit.part
      part={:root}
      kit={@options.kit}
      id={@entry.id}
      nested?={length(@entry.path) > 1}
      page={@entry.page}
      look={Kit.look(@options.kit, @options.look)}
    >
      <%!-- a nested table's heading line is on its line (`nested/1`) --%>
      <.heading
        :if={not @entry.nested?}
        entry={@entry}
        kit={@options.kit}
        myself={@myself}
        heading={@options.heading}
      />
      <Kit.part
        :if={@entry.related}
        part={:related}
        kit={@options.kit}
        id={@entry.id}
        via={@entry.related.via}
        title={@entry.related_title}
        parent={
          Routes.table(
            @router,
            @entry.related.via.source,
            @entry.related.via.source_table,
            @entry.authorize_given
          )
        }
        clear={Url.path(@options.url, @entry.id, %{})}
        create={@entry.page && @entry.model.create}
        actions={if @entry.page, do: @entry.offered, else: []}
        target={@myself}
        texts={Words.texts(:related, %{via: @entry.related.via, title: @entry.related_title})}
        messages={Words.messages(:related, %{via: @entry.related.via, title: @entry.related_title})}
      />
      <Kit.part
        part={:selection_line}
        kit={@options.kit}
        bulk={@entry.bulk}
        choose={@entry.choose}
        id={@entry.id}
        model={@entry.model}
        myself={@myself}
        nested?={@entry.nested?}
        notice?={@entry.notice?}
        page={@entry.page}
        row_count={@entry.row_count}
        running={@entry.running && @entry.running.action}
        selecting={@entry.selecting}
        selected={length(@entry.selected)}
        all?={@entry.all?}
        whole_page?={Selection.whole_page?(@entry)}
        state={@entry.state}
        texts={
          Words.texts(:selection_line, %{
            page: @entry.page,
            selected: length(@entry.selected),
            all?: @entry.all?
          })
        }
        messages={
          Words.messages(:selection_line, %{
            page: @entry.page,
            selected: length(@entry.selected),
            all?: @entry.all?
          })
        }
      />
      <Kit.part
        part={:status}
        kit={@options.kit}
        announcement={@entry.announcement}
        announcements={@entry.announcements}
        id={@entry.id}
        result={@entry.result}
        texts={Words.texts(:status, %{announcement: @entry.announcement, result: @entry.result})}
        messages={
          Words.messages(:status, %{announcement: @entry.announcement, result: @entry.result})
        }
      />
      <Kit.part
        part={:grid}
        kit={@options.kit}
        open={@entry.open_label}
        asks?={Opener.draws?(%{controlled: @options.controlled}, :confirm)}
        busy?={@entry.busy?}
        choose={@entry.choose}
        expandable?={@entry.expandable?}
        full_view={@entry.full_view}
        geometry={@entry.geometry}
        filters={filters(@entry.model, @entry.rejected, @entry.pending, @entry.state)}
        id={@entry.id}
        label={@entry.label}
        labelledby={@entry.labelledby}
        model={@entry.model}
        myself={@myself}
        nested?={@entry.nested?}
        page={@entry.page}
        pages?={Parts.Pagination.pages?(@entry.page, @entry.model)}
        row_count={@entry.row_count}
        rows={@rows}
        running={@entry.running && @entry.running.action}
        selecting={@entry.selecting}
        state={@entry.state}
        summary={@entry.summary}
        summing?={@entry.summing?}
        time_zone={@time_zone}
        editors={Kit.editors(@entry.model)}
        texts={Words.texts(:grid, %{label: @entry.label, columns: @entry.model.columns})}
        messages={Words.messages(:grid, %{label: @entry.label, columns: @entry.model.columns})}
      />
      <%!-- keyed by its kind: a message of another kind is another
      element, drawn anew, not the one before it changed --%>
      <Kit.part
        :for={
          {kind, message} <-
            Parts.Messages.messages(@entry.error, @entry.fill, @entry.loading?, @entry.row_count)
        }
        :key={kind}
        part={:message}
        kit={@options.kit}
        id={@entry.id}
        kind={kind}
        message={Words.message(:message, %{message: message})}
        text={Words.text(:message, %{message: message})}
        nested?={@entry.nested?}
      />
      <Kit.part
        :if={not @entry.nested? and Parts.Pagination.pages?(@entry.page, @entry.model)}
        part={:pagination}
        kit={@options.kit}
        id={@entry.id}
        nested?={false}
        page={@entry.page}
        model={@entry.model}
        state={@entry.state}
        row_count={@entry.row_count}
        label={@entry.label}
        target={@myself}
        pages={Words.value(:pagination, %{page: @entry.page, state: @entry.state})}
        texts={
          Words.texts(:pagination, %{
            page: @entry.page,
            row_count: @entry.row_count,
            state: @entry.state,
            label: @entry.label
          })
        }
        messages={
          Words.messages(:pagination, %{
            page: @entry.page,
            row_count: @entry.row_count,
            state: @entry.state,
            label: @entry.label
          })
        }
      />
      <:opened>
        <Kit.part
          part={:confirm}
          kit={@options.kit}
          bulk={@entry.bulk}
          id={@entry.id}
          model={@entry.model}
          presentation={presentation(@options, :confirm)}
          place={nil}
          texts={Words.texts(:confirm)}
          messages={Words.messages(:confirm)}
        />
        <%!-- The panel and the picker are drawn always, nil while closed:
        a kit that draws in the browser draws them, and the places inside
        them, ahead (C8). What opens inside one is moved into its place
        (`Phoenix.Component.portal/1`) no later than the patch that opens
        it. --%>
        <.panel
          id={@entry.id}
          held={@entry.panel}
          drawn?={Opener.draws?(%{controlled: @options.controlled}, :panel)}
          uploads={@uploads}
          kit={@options.kit}
          presentation={presentation(@options, :panel)}
          myself={@myself}
        />
        <.portal
          :if={
            @entry.panel != nil and Opener.draws?(@options, :panel) and
              (in_panel?(@options) or asked_in?(@options, :panel))
          }
          id={"#{@entry.id}-panel-portal"}
          target={"[id='#{Ids.panel_place(@entry.id)}']"}
          class={@options.kit.class(:portal, %{})}
        >
          <div data-ash-data-table-portal={Ids.panel_place(@entry.id)}>
            <.picker
              :if={in_panel?(@options)}
              entry={@entry}
              options={@options}
              chooser={@chooser}
              chooser_rows={@chooser_rows}
              time_zone={@time_zone}
              myself={@myself}
              uploads={@uploads}
              router={@router}
            />
            <.asked_in
              :if={asked_in?(@options, :panel)}
              entry={@entry}
              options={@options}
              place={:panel}
            />
          </div>
        </.portal>
        <%!-- After the panel, and so on top of it when both are open: a picker
        that a field of the panel has opened. While the panel is open over the
        page and the picker opens in it, the picker is drawn in the panel. --%>
        <.picker
          :if={not (@entry.panel != nil and Opener.draws?(@options, :panel) and in_panel?(@options))}
          entry={@entry}
          options={@options}
          chooser={@chooser}
          chooser_rows={@chooser_rows}
          time_zone={@time_zone}
          myself={@myself}
          uploads={@uploads}
          router={@router}
        />
      </:opened>
    </Kit.part>
    """
  end

  # The action panel, nil while it is closed (or the host draws it), with
  # what each of its fields is drawn with. Given what it is made of, field
  # by field (`held`, the entry's panel; `drawn?`, whether the table draws
  # it, `Opener.draws?/2` asked of the options' `controlled` alone), so
  # that LiveView draws it again only when one of them changes, not with
  # every change of its table: a kit that draws in the browser is sent its
  # props again only then. (LiveView marks an attribute changed when what
  # it reads changed: given all the options, `drawn?` would be marked with
  # every change of the URL, and the part drawn again.)
  attr :id, :string, required: true
  attr :held, :any, required: true
  attr :drawn?, :boolean, required: true
  attr :uploads, :any, required: true
  attr :kit, :atom, required: true
  attr :presentation, :atom, required: true
  attr :myself, :any, required: true

  defp panel(assigns) do
    ~H"""
    <Kit.part
      part={:panel}
      kit={@kit}
      id={@id}
      panel={open_panel(@id, @held, @drawn?, @uploads)}
      fields={
        Kit.fields(
          @id,
          open_panel(@id, @held, @drawn?, @uploads),
          files(@id, @held, @drawn?, @uploads)
        )
      }
      target={@myself}
      presentation={@presentation}
      texts={Words.texts(:panel, %{panel: open_panel(@id, @held, @drawn?, @uploads)})}
      messages={Words.messages(:panel, %{panel: open_panel(@id, @held, @drawn?, @uploads)})}
    />
    """
  end

  # The picker, with the table a record is chosen from in it.
  attr :entry, :any, required: true
  attr :options, :any, required: true
  attr :chooser, :any, required: true
  attr :chooser_rows, :any, required: true
  attr :time_zone, :any, required: true
  attr :myself, :any, required: true
  attr :uploads, :any, required: true
  attr :router, :any, required: true

  defp picker(assigns) do
    ~H"""
    <.picker_part
      id={@entry.id}
      held={@entry.picker}
      drawn?={Opener.draws?(%{controlled: @options.controlled}, :picker)}
      kit={@options.kit}
      presentation={presentation(@options, :picker)}
      takes?={!!@chooser and !@chooser.gone? and Selection.in_view(@chooser) != []}
      myself={@myself}
    />
    <%!-- its table, moved into its place --%>
    <.portal
      :if={@entry.picker != nil and Opener.draws?(@options, :picker)}
      id={"#{@entry.id}-picker-portal"}
      target={"[id='#{Ids.picker_place(@entry.id)}']"}
      class={@options.kit.class(:portal, %{})}
    >
      <div data-ash-data-table-portal={Ids.picker_place(@entry.id)}>
        <.body
          :if={@chooser && !@chooser.gone?}
          entry={@chooser}
          options={%{@options | url: nil, heading: false, mounted?: false}}
          chooser={nil}
          chooser_rows={nil}
          time_zone={@time_zone}
          rows={@chooser_rows}
          myself={@myself}
          uploads={@uploads}
          router={@router}
        />
        <div :if={@chooser && @chooser.gone?} id={@chooser.id} hidden></div>
        <.asked_in
          :if={asked_in?(@options, :picker)}
          entry={@entry}
          options={@options}
          place={:picker}
        />
      </div>
    </.portal>
    """
  end

  # The picker part, given what it is made of field by field, as the panel is.
  attr :id, :string, required: true
  attr :held, :any, required: true
  attr :drawn?, :boolean, required: true
  attr :kit, :atom, required: true
  attr :presentation, :atom, required: true
  attr :takes?, :boolean, required: true
  attr :myself, :any, required: true

  defp picker_part(assigns) do
    ~H"""
    <Kit.part
      part={:picker}
      kit={@kit}
      id={@id}
      picker={open_picker(@held, @drawn?)}
      target={@myself}
      presentation={@presentation}
      takes?={@takes?}
      texts={Words.texts(:picker, %{picker: open_picker(@held, @drawn?)})}
      messages={Words.messages(:picker, %{picker: open_picker(@held, @drawn?)})}
    />
    """
  end

  # The question once more inside a panel or picker that is open over the
  # page, where the question is asked in the page: the page under it is
  # inert, so a question it asks is shown in it (`place`, ids ending in
  # `-in-panel`, `-in-picker`). The hook asks there; the server leaves it
  # alone.
  attr :entry, :any, required: true
  attr :options, :any, required: true
  attr :place, :atom, required: true

  defp asked_in(assigns) do
    ~H"""
    <Kit.part
      part={:confirm}
      kit={@options.kit}
      bulk={@entry.bulk}
      id={@entry.id}
      model={@entry.model}
      presentation={:inline}
      place={@place}
      texts={Words.texts(:confirm)}
      messages={Words.messages(:confirm)}
    />
    """
  end

  # Whether `thing`, open over the page, holds a copy of the question, which
  # is asked in the page.
  defp asked_in?(options, thing),
    do: presentation(options, thing) == :modal and presentation(options, :confirm) == :inline

  # Whether a picker is drawn inside the open action panel: the panel opens
  # over the page and the picker in it. The page under a modal panel is
  # inert, so a picker a field of it opens is drawn where it can be used.
  # Elsewhere it is drawn after the panel, where the kit's `root/1` puts
  # what opens.
  defp in_panel?(options),
    do: presentation(options, :panel) == :modal and presentation(options, :picker) == :inline

  # What `AshDataTable.Panel.shown/2` gives of the open panel the table
  # draws (`held`, the entry's), nil for none: closed, or the host draws it
  # (controlled mode, `drawn?` false).
  defp open_panel(id, held, drawn?, uploads) do
    if held != nil and drawn?,
      do: AshDataTable.Panel.shown(held, Files.files_said(%{id: id, panel: held}, uploads))
  end

  # What `Present.picker/1` gives of the open picker the table draws, nil
  # for none.
  defp open_picker(held, drawn?),
    do: if(held != nil and drawn?, do: Present.picker(held))

  # The uploads of the open panel's file fields, by name.
  defp files(id, held, drawn?, uploads) do
    if held != nil and drawn?,
      do: files!(%{id: id, panel: held}, uploads),
      else: %{}
  end

  # Whether `thing` opens over the page or in it: as the table was told,
  # else as its kit says.
  defp presentation(options, thing),
    do: Keyword.get(options.presentation, thing) || options.kit.presentation(thing)

  # What the filter of each column shows: what was typed and rejected, else
  # what the filter row was last sent, else the filter that applies
  # (`AshDataTable.Parts.Filter.shown_filter/4`).
  defp filters(model, rejected, pending, state) do
    for column <- model.columns, into: %{} do
      {column.name,
       %{
         filter: Parts.Filter.shown_filter(rejected, pending, state, column.name),
         rejected?: is_map_key(rejected, column.name),
         applied?: is_map_key(state.filters, column.name)
       }}
    end
  end
end
