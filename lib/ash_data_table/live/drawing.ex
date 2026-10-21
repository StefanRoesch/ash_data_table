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
  alias AshDataTable.Kit.Projection
  alias AshDataTable.Live.Core.Files
  alias AshDataTable.Live.Core.Opener
  alias AshDataTable.Live.Core.Selection
  alias AshDataTable.Live.Core.Url
  alias AshDataTable.Live.Registry
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
    <.whole
      part={:heading}
      kit={@kit}
      id={@entry.id}
      inputs={%{
        id: @entry.id,
        heading: @heading,
        label: @entry.label,
        model: @entry.model,
        offered: @entry.offered,
        page: @entry.page,
        related: @entry.related,
        nested?: @entry.nested?,
        myself: @myself,
        state: @entry.state,
        lines: @entry.lines,
        refused: @entry.refused
      }}
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
      element={Projection.of({:root, :element}, %{id: @entry.id, page: @entry.page})}
      skip_target={Projection.of({:root, :skip_target}, %{id: @entry.id})}
      nested?={Projection.of({:root, :nested?}, %{nested?: length(@entry.path) > 1})}
      look={Projection.of({:root, :look}, %{look: Kit.look(@options.kit, @options.look)})}
    >
      <%!-- a nested table's heading line is on its line (`nested/1`) --%>
      <.heading
        :if={not @entry.nested?}
        entry={@entry}
        kit={@options.kit}
        myself={@myself}
        heading={@options.heading}
      />
      <.whole
        :if={@entry.related}
        part={:related}
        kit={@options.kit}
        id={@entry.id}
        inputs={%{
          id: @entry.id,
          via: @entry.related.via,
          title: @entry.related_title,
          parent:
            Routes.table(
              @router,
              @entry.related.via.source,
              @entry.related.via.source_table,
              @entry.authorize_given
            ),
          clear: Url.path(@options.url, @entry.id, %{}),
          page: @entry.page,
          create: @entry.model.create,
          offered: @entry.offered,
          target: @myself
        }}
      />
      <.whole
        part={:selection_line}
        kit={@options.kit}
        id={@entry.id}
        inputs={%{
          id: @entry.id,
          bulk: @entry.bulk,
          choose: @entry.choose,
          myself: @myself,
          nested?: @entry.nested?,
          notice?: @entry.notice?,
          page: @entry.page,
          row_count: @entry.row_count,
          running: @entry.running && @entry.running.action,
          selecting: @entry.selecting,
          selected: length(@entry.selected),
          all?: @entry.all?,
          whole_page?: Selection.whole_page?(@entry),
          state: @entry.state
        }}
      />
      <Kit.part
        part={:status}
        kit={@options.kit}
        id={@entry.id}
        region={Projection.of({:status, :region}, %{id: @entry.id})}
        again?={Projection.of({:status, :again?}, %{announcements: @entry.announcements})}
        result={Projection.of({:status, :result}, %{id: @entry.id, result: @entry.result})}
        texts={
          Projection.of({:status, :texts}, %{
            announcement: @entry.announcement,
            result: @entry.result
          })
        }
        messages={
          Projection.of({:status, :messages}, %{
            announcement: @entry.announcement,
            result: @entry.result
          })
        }
      />
      <Kit.part
        part={:grid}
        kit={@options.kit}
        id={@entry.id}
        rows={@rows}
        nested?={Projection.of({:grid, :nested?}, %{nested?: @entry.nested?})}
        sender={Projection.of({:grid, :sender}, %{id: @entry.id})}
        skip={Projection.of({:grid, :skip}, %{id: @entry.id})}
        scrollbar={Projection.of({:grid, :scrollbar}, %{id: @entry.id})}
        filter_form={
          Projection.of({:grid, :filter_form}, %{
            id: @entry.id,
            geometry: @entry.geometry,
            myself: @myself
          })
        }
        grid={
          Projection.of({:grid, :grid}, %{
            id: @entry.id,
            myself: @myself,
            geometry: @entry.geometry,
            selecting: @entry.selecting,
            choose: @entry.choose
          })
        }
        table={
          Projection.of({:grid, :table}, %{
            id: @entry.id,
            label: @entry.label,
            labelledby: @entry.labelledby,
            geometry: @entry.geometry,
            page: @entry.page,
            busy?: @entry.busy?,
            running: @entry.running && @entry.running.action
          })
        }
        head={
          Projection.of({:grid, :head}, %{
            id: @entry.id,
            model: @entry.model,
            state: @entry.state,
            geometry: @entry.geometry,
            selecting: @entry.selecting,
            expandable?: @entry.expandable?,
            myself: @myself
          })
        }
        filters={
          Projection.of({:grid, :filters}, %{
            id: @entry.id,
            model: @entry.model,
            geometry: @entry.geometry,
            selecting: @entry.selecting,
            expandable?: @entry.expandable?,
            myself: @myself,
            rejected: @entry.rejected,
            pending: @entry.pending,
            state: @entry.state
          })
        }
        row={
          Projection.of({:grid, :row}, %{
            id: @entry.id,
            model: @entry.model,
            geometry: @entry.geometry,
            selecting: @entry.selecting,
            expandable?: @entry.expandable?,
            open: @entry.open_label,
            asks?: Opener.draws?(%{controlled: @options.controlled}, :confirm)
          })
        }
        footer={
          Projection.of({:grid, :footer}, %{
            id: @entry.id,
            model: @entry.model,
            page: @entry.page,
            state: @entry.state,
            geometry: @entry.geometry,
            selecting: @entry.selecting,
            expandable?: @entry.expandable?,
            row_count: @entry.row_count,
            label: @entry.label,
            full_view: @entry.full_view,
            summary: @entry.summary,
            summing?: @entry.summing?,
            time_zone: @time_zone,
            nested?: @entry.nested?,
            myself: @myself
          })
        }
        editors={
          Projection.of({:grid, :editors}, %{
            id: @entry.id,
            model: @entry.model,
            asks?: Opener.draws?(%{controlled: @options.controlled}, :confirm)
          })
        }
        failure={
          Projection.of({:grid, :failure}, %{
            id: @entry.id,
            model: @entry.model,
            geometry: @entry.geometry
          })
        }
        texts={Projection.of({:grid, :texts}, %{label: @entry.label, model: @entry.model})}
        messages={Projection.of({:grid, :messages}, %{label: @entry.label, model: @entry.model})}
      />
      <%!-- keyed by its kind: a message of another kind is another
      element, drawn anew, not the one before it changed --%>
      <Kit.part
        :for={
          message <-
            Projection.of(:message, %{
              id: @entry.id,
              error: @entry.error,
              fill: @entry.fill,
              loading?: @entry.loading?,
              row_count: @entry.row_count,
              nested?: @entry.nested?
            })
        }
        :key={message.kind}
        part={:message}
        kit={@options.kit}
        id={@entry.id}
        kind={message.kind}
        element={message.element}
        nested?={message.nested?}
        text={message.text}
        message={message.message}
      />
      <.pagination
        :if={not @entry.nested? and Projection.Pagination.pages?(@entry.page, @entry.model)}
        kit={@options.kit}
        id={@entry.id}
        page={@entry.page}
        model={@entry.model}
        state={@entry.state}
        row_count={@entry.row_count}
        label={@entry.label}
        target={@myself}
      />
      <:opened>
        <.confirm
          kit={@options.kit}
          id={@entry.id}
          model={@entry.model}
          bulk={@entry.bulk}
          presentation={presentation(@options, :confirm)}
          place={nil}
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
    <.whole
      part={:panel}
      kit={@kit}
      id={@id}
      uploads={uploads(files(@id, @held, @drawn?, @uploads))}
      inputs={%{
        id: @id,
        panel: open_panel(@id, @held, @drawn?, @uploads),
        files: files(@id, @held, @drawn?, @uploads),
        target: @myself,
        presentation: @presentation
      }}
    />
    """
  end

  # A part whose projection is made whole (`Projection.of/2`: the heading
  # line, the line of a table of related records, the selection line, the
  # panel; parts whose keys change together): made once of the `inputs`
  # it is given, and handed on an attribute per key. LiveView draws it
  # again when an input changes (what the `inputs` attribute reads), and
  # the part keeps LiveView's change tracking: given its projection as a
  # spread (`{map}`), the part would be drawn as if for the first time,
  # and a kit that draws in the browser would be told nothing changed
  # (LiveReact reads its props' changes from LiveView's).
  attr :part, :atom, required: true
  attr :kit, :atom, required: true
  attr :id, :string, required: true
  attr :inputs, :map, required: true
  attr :uploads, :map, default: nil

  defp whole(%{part: :heading} = assigns) do
    assigns = assign(assigns, :projection, Projection.of(:heading, assigns.inputs))

    ~H"""
    <Kit.part
      part={:heading}
      kit={@kit}
      id={@id}
      shown?={@projection.shown?}
      nested?={@projection.nested?}
      element={@projection.element}
      title={@projection.title}
      columns={@projection.columns}
      argument_line={@projection.argument_line}
      acts?={@projection.acts?}
      create={@projection.create}
      actions={@projection.actions}
    />
    """
  end

  defp whole(%{part: :related} = assigns) do
    assigns = assign(assigns, :projection, Projection.of(:related, assigns.inputs))

    ~H"""
    <Kit.part
      part={:related}
      kit={@kit}
      id={@id}
      element={@projection.element}
      heading={@projection.heading}
      record={@projection.record}
      create={@projection.create}
      actions={@projection.actions}
      clear={@projection.clear}
      texts={@projection.texts}
      messages={@projection.messages}
    />
    """
  end

  defp whole(%{part: :selection_line} = assigns) do
    assigns = assign(assigns, :projection, Projection.of(:selection_line, assigns.inputs))

    ~H"""
    <Kit.part
      part={:selection_line}
      kit={@kit}
      id={@id}
      shown?={@projection.shown?}
      nested?={@projection.nested?}
      selection={@projection.selection}
      notice={@projection.notice}
      clear_filters={@projection.clear_filters}
      texts={@projection.texts}
      messages={@projection.messages}
    />
    """
  end

  defp whole(%{part: :panel} = assigns) do
    assigns = assign(assigns, :projection, Projection.of(:panel, assigns.inputs))

    ~H"""
    <Kit.part
      part={:panel}
      kit={@kit}
      id={@id}
      uploads={@uploads}
      open?={@projection.open?}
      presentation={@projection.presentation}
      destructive?={@projection.destructive?}
      place={@projection.place}
      frame={@projection.frame}
      form={@projection.form}
      title={@projection.title}
      errors={@projection.errors}
      cancel={@projection.cancel}
      submit={@projection.submit}
      fields={@projection.fields}
      texts={@projection.texts}
      messages={@projection.messages}
    />
    """
  end

  # LiveView's uploads of the open panel's file fields, by the name of each
  # (what a file field's projection names its upload by).
  defp uploads(files),
    do:
      for(
        {_field, %{upload: upload}} <- files,
        upload,
        into: %{},
        do: {to_string(upload.name), upload}
      )

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
      open?={Projection.of({:picker, :open?}, %{picker: open_picker(@held, @drawn?)})}
      presentation={Projection.of({:picker, :presentation}, %{presentation: @presentation})}
      place={Projection.of({:picker, :place}, %{id: @id})}
      frame={
        Projection.of({:picker, :frame}, %{
          id: @id,
          picker: open_picker(@held, @drawn?),
          presentation: @presentation,
          target: @myself
        })
      }
      title={Projection.of({:picker, :title}, %{id: @id})}
      error={Projection.of({:picker, :error}, %{id: @id, picker: open_picker(@held, @drawn?)})}
      cancel={Projection.of({:picker, :cancel}, %{id: @id})}
      none={Projection.of({:picker, :none}, %{id: @id, picker: open_picker(@held, @drawn?)})}
      take={
        Projection.of({:picker, :take}, %{
          id: @id,
          picker: open_picker(@held, @drawn?),
          takes?: @takes?
        })
      }
      texts={Projection.of({:picker, :texts}, %{picker: open_picker(@held, @drawn?)})}
      messages={Projection.of({:picker, :messages}, %{picker: open_picker(@held, @drawn?)})}
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
    <.confirm
      kit={@options.kit}
      id={@entry.id}
      model={@entry.model}
      bulk={@entry.bulk}
      presentation={:inline}
      place={@place}
    />
    """
  end

  # The question (the kit's `confirm/1`), each key of its projection made
  # of what it depends on.
  attr :kit, :atom, required: true
  attr :id, :string, required: true
  attr :model, :any, required: true
  attr :bulk, :list, required: true
  attr :presentation, :atom, required: true
  attr :place, :atom, required: true

  defp confirm(assigns) do
    ~H"""
    <Kit.part
      part={:confirm}
      kit={@kit}
      id={@id}
      asks?={Projection.of({:confirm, :asks?}, %{model: @model, bulk: @bulk})}
      presentation={Projection.of({:confirm, :presentation}, %{presentation: @presentation})}
      holder={Projection.of({:confirm, :holder}, %{id: @id, place: @place})}
      dialog={
        Projection.of({:confirm, :dialog}, %{id: @id, presentation: @presentation, place: @place})
      }
      question={Projection.of({:confirm, :question}, %{id: @id, place: @place})}
      texts={Projection.of({:confirm, :texts}, %{})}
      messages={Projection.of({:confirm, :messages}, %{})}
    />
    """
  end

  # The pages of the table on the page (the kit's `pagination/1`; a nested
  # table's are in its grid's footer), each key of its projection made of
  # what it depends on.
  attr :kit, :atom, required: true
  attr :id, :string, required: true
  attr :page, :any, required: true
  attr :model, :any, required: true
  attr :state, :any, required: true
  attr :row_count, :any, required: true
  attr :label, :any, required: true
  attr :target, :any, required: true

  defp pagination(assigns) do
    ~H"""
    <Kit.part
      part={:pagination}
      kit={@kit}
      id={@id}
      nested?={false}
      element={Projection.of({:pagination, :element}, %{id: @id, label: @label, nested?: false})}
      range={Projection.of({:pagination, :range}, %{id: @id})}
      previous={Projection.of({:pagination, :previous}, %{id: @id, page: @page, target: @target})}
      next={Projection.of({:pagination, :next}, %{id: @id, page: @page, target: @target})}
      pages={
        Projection.of({:pagination, :pages}, %{
          id: @id,
          page: @page,
          state: @state,
          model: @model,
          target: @target
        })
      }
      sizes={
        Projection.of({:pagination, :sizes}, %{
          id: @id,
          model: @model,
          state: @state,
          target: @target
        })
      }
      texts={
        Projection.of({:pagination, :texts}, %{
          page: @page,
          row_count: @row_count,
          state: @state,
          label: @label
        })
      }
      messages={
        Projection.of({:pagination, :messages}, %{
          page: @page,
          row_count: @row_count,
          state: @state,
          label: @label
        })
      }
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
end
