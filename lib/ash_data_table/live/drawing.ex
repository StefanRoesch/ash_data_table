defmodule AshDataTable.Live.Drawing do
  @moduledoc false
  # What `AshDataTable.attached/1` draws (part 4): every table of one
  # `AshDataTable.Table`, through its kit (`AshDataTable.Kit`, the design
  # note of stage 7, D8). It turns what the core holds into the values each
  # part is given (`AshDataTable.Present`, the uploads of the panel, the
  # links), and calls the kit's parts in their order; the markup is the
  # kit's. The table on the page, its nested tables (each in a portal) and
  # the tables of its pickers (in the picker) are drawn with the kit of the
  # table on the page.
  use Phoenix.Component

  alias AshDataTable.Kit
  alias AshDataTable.Kit.Words
  alias AshDataTable.Live.Core.Files
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
      chooser={chooser(@table, @table.entry)}
      chooser_rows={rows(@streams, chooser(@table, @table.entry))}
      myself={@table.options.target}
      uploads={@uploads}
      router={@table.options.router}
    />
    <.portal
      :for={{entry, rows} <- portals(@table, @streams)}
      :key={entry.id}
      id={"#{entry.id}-portal"}
      target={"[id='#{entry.target}']"}
      class={@table.options.kit.class(:portal, %{})}
    >
      <div data-ash-data-table-portal={entry.target}>
        <div data-ash-data-table-view>
          <.body
            :if={!entry.gone?}
            entry={entry}
            options={%{@table.options | url: nil, heading: false, mounted?: false}}
            time_zone={@table.caller.time_zone}
            rows={rows}
            chooser={chooser(@table, entry)}
            chooser_rows={rows(@streams, chooser(@table, entry))}
            myself={@table.options.target}
            uploads={@uploads}
            router={@table.options.router}
          />
          <div :if={entry.gone?} id={entry.id} hidden></div>
        </div>
      </div>
    </.portal>
    """
  end

  # The uploads of the panel's file fields. A function component sees only
  # what it is given, and LiveView's uploads are not the table's to assign
  # (D5): a page that draws a table whose panel takes a file must give them.
  defp files!(entry, nil) do
    if Files.file_inputs(entry.panel) != [] do
      raise ArgumentError,
            "the action panel of the table #{inspect(entry.id)} takes a file, and " <>
              "AshDataTable.attached/1 was given no uploads: pass " <>
              "`uploads={assigns[:uploads]}` to `AshDataTable.attached`."
    end

    Files.panel_files(entry, nil)
  end

  defp files!(entry, uploads), do: Files.panel_files(entry, uploads)

  # The nested tables, parents first, each with the items of its stream:
  # a portal is rendered again only when its table or its stream changed.
  defp portals(table, streams),
    do: for(entry <- Registry.portals(table), do: {entry, streams[entry.stream]})

  # The items of a table's stream, given to its grid whenever the table
  # changes: the grid's comprehension over them is then rendered again, with
  # nothing new in it but what the stream holds, as it was while every
  # table was a component of its own (`Phoenix.LiveViewTest` keeps the rows
  # of a stream where they are only then).
  defp rows(_streams, nil), do: nil

  defp rows(streams, entry), do: streams[entry.stream]

  # The table of the entry's open picker, which is drawn in its dialog.
  defp chooser(_table, %{picker: nil}), do: nil

  defp chooser(table, %{id: id, picker: picker}),
    do: Map.get(table.entries, "#{id}-pick-#{picker.name}")

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
    >
      <Kit.part
        part={:heading}
        kit={@options.kit}
        heading={@options.heading}
        id={@entry.id}
        label={@entry.label}
        model={@entry.model}
        myself={@myself}
        nested?={@entry.nested?}
        offered={@entry.offered}
        page={@entry.page}
        related={@entry.related}
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
        part={:argument_line}
        kit={@options.kit}
        id={@entry.id}
        lines={@entry.lines}
        model={@entry.model}
        myself={@myself}
        nested?={@entry.nested?}
        refused={@entry.refused}
        state={@entry.state}
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
        state={@entry.state}
        texts={Words.texts(:selection_line, %{page: @entry.page})}
        messages={Words.messages(:selection_line, %{page: @entry.page})}
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
        acting?={@entry.acting?}
        open={@entry.open_label}
        asks?={:confirm not in @options.controlled}
        busy?={@entry.busy?}
        choose={@entry.choose}
        creates={@entry.creates}
        editing?={@entry.editing?}
        expandable?={@entry.expandable?}
        full_view={@entry.full_view}
        filters={filters(@entry.model, @entry.rejected, @entry.pending, @entry.state)}
        id={@entry.id}
        label={@entry.label}
        label_column={@entry.label_column}
        labelledby={@entry.labelledby}
        lead={@entry.lead}
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
        summarised?={@entry.summarised?}
        summary={@entry.summary}
        summing?={@entry.summing?}
        time_zone={@time_zone}
        texts={Words.texts(:grid)}
        messages={Words.messages(:grid)}
      />
      <Kit.part part={:whole_text} kit={@options.kit} id={@entry.id} />
      <Kit.part
        :for={
          {kind, message} <-
            Parts.Messages.messages(@entry.error, @entry.fill, @entry.loading?, @entry.row_count)
        }
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
          texts={Words.texts(:confirm)}
          messages={Words.messages(:confirm)}
        />
        <Kit.part
          :if={panel?(@entry, @options)}
          part={:panel}
          kit={@options.kit}
          id={@entry.id}
          panel={Present.panel(@entry.panel, Files.files_said(@entry, @uploads))}
          files={files!(@entry, @uploads)}
          target={@myself}
          presentation={presentation(@options, :panel)}
          texts={Words.texts(:panel, %{panel: Present.panel(@entry.panel)})}
          messages={Words.messages(:panel, %{panel: Present.panel(@entry.panel)})}
        >
          <.picker
            :if={picker_in_panel?(@entry, @options)}
            entry={@entry}
            options={@options}
            chooser={@chooser}
            chooser_rows={@chooser_rows}
            time_zone={@time_zone}
            myself={@myself}
            uploads={@uploads}
            router={@router}
          />
        </Kit.part>
        <%!-- After the panel, and so on top of it when both are open: a picker
        that a field of the panel has opened. --%>
        <.picker
          :if={picker?(@entry, @options) && not picker_in_panel?(@entry, @options)}
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
    <Kit.part
      part={:picker}
      kit={@options.kit}
      id={@entry.id}
      picker={Present.picker(@entry.picker)}
      target={@myself}
      presentation={presentation(@options, :picker)}
      texts={Words.texts(:picker, %{picker: Present.picker(@entry.picker)})}
      messages={Words.messages(:picker, %{picker: Present.picker(@entry.picker)})}
    >
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
    </Kit.part>
    """
  end

  # Whether the table draws the action panel: it is open, and not a
  # request the host draws (controlled mode).
  defp panel?(entry, options),
    do: entry.panel != nil and not AshDataTable.Live.Core.Requests.host?(options, entry, :panel)

  # Whether the picker is drawn inside the action panel: a field of a panel
  # that is open over the page opened it, and it opens in the page. The page
  # under a modal panel is inert, so the picker is drawn where it can be
  # used. Elsewhere it is drawn after the panel, where the kit's `root/1`
  # puts what opens.
  defp picker_in_panel?(entry, options) do
    picker?(entry, options) and panel?(entry, options) and presentation(options, :panel) == :modal and
      presentation(options, :picker) == :inline
  end

  # Whether the table draws the picker: it is open, and not a request the
  # host draws (controlled mode).
  defp picker?(entry, options),
    do: entry.picker != nil and not AshDataTable.Live.Core.Requests.host?(options, entry, :picker)

  # Whether `thing` opens over the page or in it: as the table was told,
  # else as its kit says (the design note of stage 7, D11).
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
