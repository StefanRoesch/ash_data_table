// The action panel (the island `AshPanel`, the part `panel`; the HEEx
// kit's is `Parts.Panel`): a native `<dialog>` over the page, or a region
// in it, with shadcn's look, around the form of the action. Drawn always,
// closed too, with its place (`Ids.panel_place/1`): what opens inside it
// (a picker a field opened, where the panel is over the page and the
// picker in it; the question's copy) is moved there by LiveView in the
// patch that opens it, so the place is there before (the React kit's
// note, C8 and Q2), and is never drawn again as another element. As it
// opens the island mounts the table's panel hook on it (`mountPanel`):
// focus in and back, Escape and Cancel, the question of an action, the
// rows of a list field, focus after a button the server names; as it
// closes it destroys it and closes the dialog. It draws the part's
// projection (`AshDataTable.Kit.Projection`), each key a prop of the
// island, a field each with what is in it.
//
// The form is the island's: LiveView hears its `phx-change` and
// `phx-submit` from its root, as it hears the argument line's. Its controls
// are uncontrolled: what is typed is the browser's, and what the server
// gives is set where it changes, unless the person is in the control
// (`useServerValue`), as LiveView patches a form. The rows of a list field
// are the hook's once drawn (as the HEEx kit's `phx-update="ignore"`):
// drawn once per opening, never again.
//
// A file field: LiveView's own file input is drawn beside the island, out
// of sight, in this form (`form=`); the island's control hands it the files
// a person chooses (`uploadTo`, LiveView's documented hook function, which
// live_react gives the island), and says how far each has come.
import * as React from "react"
import {mountPanel} from "ash_data_table"

import {attrs, type Bundle, type Message} from "./props"
import {Commits, ServerBox, Strict, useLive, useMountedWhile, useServerValue, type ServerBoxProps} from "./mounting"
import {usePart} from "./parts"
import {Template, type CountProps, type EditorProps, type Limits} from "./Editors"
import {closeDialog} from "./Picker"
import {box, button, input, select} from "./look"
import {cn} from "../lib/utils"

type Counted = {max: number; unit: string; "trim?": boolean; casing: string | null}
type Choice = {value: string; label: string; "chosen?": boolean}
// What a field is given of its texts, the last three for a list of groups
// only.
type FieldTexts = {
  required: string
  choose: string
  add_value: string
  kind: string
  remove_group: string
  will_be_cleared: string
  keep: string
  clear: string
  keep_value: string
  clear_value: string
  errors: string[]
  chosen: string[]
  remove_chosen: string[]
  value_position?: string[]
  remove_value?: string[]
  item_errors?: string[][]
}
// A hidden entry of a value made of fields: a bundle of its `name` and `value`,
// spread on an `<input type="hidden">` as the library gives it.
type Hidden = Bundle & {name: string}
type Members = {hidden: Hidden[]; fields: FieldProps[]}
type ListRow = {value: string; position: number | null; count: CountProps | null}

export type ListProps = {
  element: Bundle
  item: string | null
  limits: Limits
  typing: Bundle
  name: string
  template: ListRow
  rows: ListRow[]
  texts: {add_value: string; value_label: string; remove_label: string; value_position: string[]; remove_value: string[]}
}

export type ControlProps = {
  id: string
  name: string
  value: string
  editor: string
  "secret?": boolean
  "invalid?": boolean
  "required?": boolean
  described: string | null
  limits: Limits
  values: null | Choice[]
  typing: Bundle
}

export type FieldProps = {
  id: string
  name: string
  element: Bundle
  editor: string
  label: string
  "required?": boolean
  "secret?": boolean
  item: string | null
  values: null | Choice[]
  value: string | string[] | null | Record<string, unknown>
  boxless: string[]
  "invalid?": boolean
  places: string | null
  limits: Limits
  counted: Counted | null
  described: string | null
  "labelled?": boolean
  group_label: Bundle | null
  labelledby: string
  error: Bundle | null
  reference: null | {chosen: null | {element: Bundle; text: string}; choose: Bundle}
  references: null | {entries: {key: string; element: Bundle; text: string; unpick: Bundle}[]; choose: Bundle}
  list: ListProps | null
  file: null | {
    name: string
    ref: string
    accept: string | null
    "multiple?": boolean
    label: Bundle
    entries: {ref: string; name: string; progress: number; "done?": boolean; "cancelled?": boolean; "sending?": boolean}[]
  }
  component: null | {module: string; control: Bundle}
  control: ControlProps | null
  clear: null | {"asked?": boolean; cleared: Bundle | null; button: Bundle}
  count: CountProps | null
  group: null | {label: Bundle; members: Members | null; add: Bundle | null; remove: Bundle | null}
  groups: null | {
    label: Bundle
    items: {key: string; element: Bundle; label: Bundle; labelledby: string; error: Bundle | null; remove: Bundle; members: Members}[]
    hidden: Hidden[]
    add: Bundle
  }
  union: null | {
    label: Bundle
    hidden: Hidden[]
    kind: string
    choice: Bundle
    kind_label: Bundle
    select: Bundle
    "empty?": boolean
    kinds: Choice[]
    "own_errors?": boolean
    single: FieldProps | null
    members: Members | null
  }
  texts: FieldTexts
  messages: Record<string, Message | Message[] | null>
  locale: string
}

export type PanelProps = {
  panel: {
    "open?": boolean
    presentation: "modal" | "inline"
    "destructive?": boolean
    place: Bundle
    frame: Bundle | null
    form: Bundle | null
    title: Bundle
    errors: Bundle | null
    cancel: Bundle
    submit: Bundle
    fields: FieldProps[]
    texts: {title: string | null; submit: string | null; question: string | null; errors: string[]; cancel: string}
    messages: Record<string, Message | Message[] | null>
  }
}

export function AshPanel(props: PanelProps["panel"]) {
  const PanelPart = usePart("Panel")
  return (
    <Strict>
      <PanelPart panel={props} />
    </Strict>
  )
}

// The part `Panel`.
export function Panel({panel}: PanelProps) {
  const Field = usePart("Field")
  const live = useLive()
  const ref = React.useRef<HTMLElement>(null)
  const open = panel["open?"]
  const mounted = useMountedWhile(ref, open, mountPanel, live, closeDialog)
  const modal = panel.presentation === "modal"
  const Tag = modal ? "dialog" : "section"
  const {texts} = panel

  return (
    <Tag
      ref={ref as React.RefObject<HTMLDialogElement>}
      {...(open ? attrs(panel.frame) : {hidden: !modal})}
      className={modal ? "ash-react-dialog ash-react-side" : "ash-react-inline"}
    >
      <Commits mounted={mounted}>
        {open && (
          <form {...attrs(panel.form)}>
            <h2 {...attrs(panel.title)} className="mb-4 text-lg font-semibold">
              {texts.title}
            </h2>
            {/* what the action says that is about none of the fields */}
            {panel.errors && (
              <div {...attrs(panel.errors)} className="mb-4 text-sm font-medium">
                {texts.errors.map((message, at) => (
                  <p key={at}>{message}</p>
                ))}
              </div>
            )}
            {panel.fields.map(field => (
              <Field key={field.id} field={field} />
            ))}
            <div className="mt-6 flex justify-end gap-2">
              <button type="button" {...attrs(panel.cancel)} className={button("outline", "sm")}>
                {texts.cancel}
              </button>
              <button type="submit" {...attrs(panel.submit)} className={button(panel["destructive?"] ? "destructive" : "default", "sm")}>
                {texts.submit}
              </button>
            </div>
          </form>
        )}
      </Commits>
      {/* what opens inside it is moved in here */}
      <div {...attrs(panel.place)} className="contents"></div>
    </Tag>
  )
}

const text = (value: FieldProps["value"]) => (typeof value === "string" ? value : "")

const LABEL = "flex items-center gap-2 text-sm"

// The part `Field`: one field of the panel, its label, the control of its
// type, and the action's errors about it; inside a value made of fields
// the same for each field in it.
export function Field({field}: {field: FieldProps}) {
  const Control = usePart("Control")
  const ListPart = usePart("List")
  const PanelBox = usePart("PanelBox")
  const Group = usePart("Group")
  const Groups = usePart("Groups")
  const Union = usePart("Union")
  const FileField = usePart("FileField")
  const ComponentEditor = usePart("ComponentEditor")
  const Counter = usePart("Counter")
  const {id, editor, texts} = field
  const invalid = field["invalid?"]
  const describedBy = field.described ?? undefined
  const group = field.group || field.groups || field.union
  const {reference, references} = field

  return (
    <div className="mb-3 flex flex-col gap-1" {...attrs(field.element)}>
      {/* an unchecked box sends nothing: this says "false" for it */}
      {editor === "boolean" && <input type="hidden" name={field.name} value="false" />}
      {field["labelled?"] && (
        <label htmlFor={id} className={LABEL}>
          {editor === "boolean" && <PanelBox id={id} name={field.name} checked={field.value === "true"} invalid={invalid} describedBy={describedBy} />}
          <span data-label="">{field.label}</span>
          {field["required?"] && editor !== "boolean" && <span aria-hidden="true">*</span>}
        </label>
      )}
      {field.group_label && !reference && (
        <span {...attrs(field.group_label)} className="text-sm">
          <span data-label="">{field.label}</span>
        </span>
      )}
      {/* the key of a related record is not typed: what the record is
      called, and the button that opens the picker, as a group */}
      {reference && (
        <>
          <span {...attrs(field.group_label)} className="text-sm">
            <span data-label="">{field.label}</span>
            {field["required?"] && <span aria-hidden="true">*</span>}
            {field["required?"] && <span className="sr-only">{texts.required}</span>}
          </span>
          <div id={id} role="group" aria-labelledby={field.labelledby} aria-describedby={describedBy} className="flex items-center gap-2">
            <input type="text" name={field.name} value={text(field.value)} readOnly hidden data-key="" />
            {reference.chosen && (
              <span {...attrs(reference.chosen.element)} className="text-sm" data-chosen="">
                {reference.chosen.text}
              </span>
            )}
            <button type="button" {...attrs(reference.choose)} className={button("outline", "sm")}>
              {texts.choose}
            </button>
          </div>
        </>
      )}
      {references && (
        <div id={id} role="group" aria-labelledby={field.labelledby} aria-describedby={describedBy} data-references="" className="flex flex-col gap-1">
          <input type="text" name={`${field.name}[]`} value="" readOnly hidden data-own="" />
          {references.entries.map(entry => (
            <div key={entry.key} className="flex items-center gap-1" data-chosen-item="">
              <input type="text" name={`${field.name}[]`} value={entry.key} readOnly hidden data-key="" />
              <span {...attrs(entry.element)} className="text-sm" data-chosen="">
                {entry.text}
              </span>
              <button type="button" {...attrs(entry.unpick)} className={button("ghost", "xs")}>
                <span aria-hidden="true">✕</span>
              </button>
            </div>
          ))}
          <button type="button" {...attrs(references.choose)} className={button("outline", "sm", "self-start")}>
            {texts.choose}
          </button>
        </div>
      )}
      {(editor === "choices" || editor === "list") && (
        <div id={id} role="group" aria-labelledby={field.labelledby} aria-describedby={describedBy} data-invalid={field.places ?? undefined} className="flex flex-col gap-1">
          {/* a form sends nothing for a list without values: this entry is
          sent before the values in every case */}
          <input type="text" name={`${field.name}[]`} value="" readOnly hidden data-own="" />
          {editor === "choices" &&
            (field.values || []).map(choice => (
              <label key={choice.value} className={LABEL}>
                <PanelBox name={`${field.name}[]`} value={choice.value} checked={choice["chosen?"]} invalid={invalid} />
                {choice.label}
              </label>
            ))}
          {/* what the field holds that is none of the choices, sent back as it came */}
          {field.boxless.map(value => (
            <input key={value} type="hidden" name={`${field.name}[]`} value={value} />
          ))}
          {field.list && <ListPart list={field.list} />}
        </div>
      )}
      {field.group && <Group field={field} />}
      {field.groups && <Groups field={field} />}
      {field.union && <Union field={field} />}
      {field.file && <FileField field={field} />}
      {field.component && <ComponentEditor field={field} />}
      {/* a sensitive input, which is text or a number: typed hidden */}
      {field.control && <Control control={field.control} />}
      {/* a sensitive field the action may empty: "Clear", and "Keep" once asked */}
      {field.clear && field.clear["asked?"] && (
        <p {...attrs(field.clear.cleared)} className="text-sm" data-cleared="">
          {texts.will_be_cleared}
        </p>
      )}
      {field.clear && (
        <button type="button" {...attrs(field.clear.button)} className={button("outline", "sm", "self-start")}>
          {field.clear["asked?"] ? texts.keep : texts.clear}
        </button>
      )}
      {field.count && <Counter count={field.count} value={text(field.value)} className="self-end" />}
      {/* in the text colour: the error colour is too faint for small text */}
      {field.error && !group && (
        <div {...attrs(field.error)} className="mt-1 text-xs">
          {texts.errors.map((message: string, at: number) => (
            <p key={at} data-error="">
              {message}
            </p>
          ))}
        </div>
      )}
    </div>
  )
}

// The part `Counter`: the counter of a text, drawn anew where the server's
// value changes, as the server would draw it; the hook counts again as it
// is typed.
export function Counter({count, value, className}: {count: CountProps; value: string; className?: string}) {
  const Count = usePart("Count")
  return <Count key={value} count={count} className={className} />
}

// The part `PanelBox`: a checkbox of the panel, checked as the server says
// unless the person is in it.
export function PanelBox({value = "true", ...box}: Omit<ServerBoxProps, "value"> & {value?: string}) {
  return <ServerBox value={value} {...box} />
}

const INPUT: Record<string, string> = {number: "number", date: "date", datetime: "datetime-local"}
// any number, not only whole ones; a datetime to the second, as it is shown
const STEP: Record<string, string> = {number: "any", datetime: "1"}

// The part `Control`: the control of a field that is typed or chosen from
// a list: typed hidden where it is sensitive (it starts empty, and holds
// what was typed into it in this panel), a text in a textarea, a choice
// in a menu, anything else in an input of its type, with what the
// constraints of a number say of it (`limits`).
export function Control({control}: {control: ControlProps}) {
  // one ref for whichever of the three it draws: an input, a textarea or a select
  const ref = React.useRef<HTMLInputElement & HTMLTextAreaElement & HTMLSelectElement>(null)
  const value = control.value ?? ""
  useServerValue(ref, value)
  const common = {
    ref,
    id: control.id,
    name: control.name,
    defaultValue: value,
    "aria-required": control["required?"] ? ("true" as const) : undefined,
    "aria-invalid": control["invalid?"] ? ("true" as const) : undefined,
    "aria-describedby": control.described ?? undefined,
    ...attrs(control.typing),
  }

  if (control["secret?"]) return <input type="password" autoComplete="off" {...common} className={input("h-8 w-full text-sm")} />
  if (control.editor === "text") return <textarea rows={3} {...common} className={input("h-auto w-full py-1 text-sm")} />
  if (control.editor === "enum") {
    return (
      <select {...common} className={select("h-8 w-full text-sm")}>
        {(!control["required?"] || value === "") && <option value=""></option>}
        {(control.values || []).map(choice => (
          <option key={choice.value} value={choice.value}>
            {choice.label}
          </option>
        ))}
      </select>
    )
  }
  return (
    <input
      type={INPUT[control.editor] ?? "text"}
      step={control.limits.step ?? STEP[control.editor]}
      min={control.limits.min ?? undefined}
      max={control.limits.max ?? undefined}
      {...common}
      className={input("h-8 w-full text-sm")}
    />
  )
}

// The part `List`: the field of an array, value by value, its rows the
// hook's once drawn (it adds them from the template and takes them away):
// drawn once, never again while the panel is open.
export const List = React.memo(
  function List({list}: {list: ListProps}) {
    const ListItem = usePart("ListItem")
    const {texts} = list
    return (
      <div {...attrs(list.element)} className="flex flex-col items-stretch gap-1">
        <Template bundle={{}}>
          <ListItem list={list} row={list.template} valueLabel={null} removeLabel={null} />
        </Template>
        {list.rows.map((row, at) => (
          <ListItem key={at} list={list} row={row} valueLabel={texts.value_position[at]} removeLabel={texts.remove_value[at]} />
        ))}
        <button type="button" data-add="" className={button("outline", "sm", "self-start")}>
          {texts.add_value}
        </button>
      </div>
    )
  },
  () => true,
)

// The part `ListItem`: one value of a list field, with its remove button;
// the template's (no position), which the hook adds a value from.
export function ListItem({list, row, valueLabel, removeLabel}: {list: ListProps; row: ListRow; valueLabel: string | null; removeLabel: string | null}) {
  const Count = usePart("Count")
  const kind = list.item
  const {name} = list
  const label = valueLabel ?? undefined
  return (
    <div data-item="" className="flex items-center gap-1">
      {kind === "boolean" && <input type="hidden" name={name} value={String(row.value === "true")} />}
      {kind === "boolean" && <input type="checkbox" defaultChecked={row.value === "true"} aria-label={label} className={box()} />}
      {kind === "text" && <textarea rows={1} name={name} defaultValue={row.value} aria-label={label} aria-describedby={(row.count?.element.id as string | undefined) ?? undefined} {...attrs(list.typing)} className={input("h-auto min-h-0 flex-1 py-1 text-sm")} />}
      {kind === "text" && row.count && <Count count={row.count} />}
      {(kind === "number" || kind === "date" || kind === "datetime") && (
        <input
          type={INPUT[kind]}
          step={list.limits.step ?? STEP[kind]}
          min={list.limits.min ?? undefined}
          max={list.limits.max ?? undefined}
          name={name}
          defaultValue={row.value}
          aria-label={label}
          {...attrs(list.typing)}
          className={input("h-8 flex-1 text-sm")}
        />
      )}
      <button type="button" data-remove="" aria-label={removeLabel ?? undefined} className={button("ghost", "xs")}>
        <span aria-hidden="true">✕</span>
      </button>
    </div>
  )
}

// The part `MembersOf`: the fields of one value made of fields: its hidden entries (that it is
// there, the keys it sends back as they came), and a field per input.
export function MembersOf({members}: {members: Members}) {
  const Field = usePart("Field")
  return (
    <>
      <HiddenEntries entries={members.hidden} />
      {members.fields.map(inner => (
        <Field key={inner.id} field={inner} />
      ))}
    </>
  )
}

// The hidden entries a value made of fields sends beside its fields, as the library names them.
function HiddenEntries({entries}: {entries: Hidden[]}) {
  return (
    <>
      {entries.map(entry => (
        <input key={entry.name} type="hidden" {...attrs(entry)} />
      ))}
    </>
  )
}

// The part `Errors`: what the action says about a group or one value of it,
// in its element (`error`).
export function Errors({error, errors}: {error: Bundle | null; errors: string[]}) {
  return (
    <div {...attrs(error)} className="mb-1 text-xs">
      {errors.map((message, at) => (
        <p key={at} data-error="">
          {message}
        </p>
      ))}
    </div>
  )
}

// The part `GroupLabel`: the label of a group or a union.
export function GroupLabel({field, label}: {field: FieldProps; label: Bundle}) {
  return (
    <span {...attrs(label)} className="text-sm">
      <span data-label="">{field.label}</span>
      {field["required?"] && <span aria-hidden="true">*</span>}
      {field["required?"] && <span className="sr-only">{field.texts.required}</span>}
    </span>
  )
}

// The part `Group`: a value made of fields, its fields while it holds one, the button that
// takes it away where it may be left out, else the one that adds it.
export function Group({field}: {field: FieldProps}) {
  const GroupLabel = usePart("GroupLabel")
  const Errors = usePart("Errors")
  const MembersOf = usePart("MembersOf")
  const {id, texts} = field
  const group = field.group!
  return (
    <div id={id} role="group" aria-labelledby={field.labelledby} aria-describedby={(field.error?.id as string | undefined) ?? undefined} data-group="">
      <div className="flex items-center gap-1">
        <GroupLabel field={field} label={group.label} />
        {group.remove && (
          <button type="button" {...attrs(group.remove)} aria-label={texts.remove_group} className={button("ghost", "xs")}>
            <span aria-hidden="true">✕</span>
          </button>
        )}
      </div>
      {field.error && <Errors error={field.error} errors={texts.errors} />}
      {group.members && (
        <div className="ps-4">
          <MembersOf members={group.members} />
        </div>
      )}
      {group.add && (
        <button type="button" {...attrs(group.add)} className={button("outline", "sm")}>
          {texts.add_value}
        </button>
      )}
    </div>
  )
}

// The part `Groups`: a list of values made of fields: a group per value, each under a number
// of its own, with the button that takes it away; then the one that adds one.
export function Groups({field}: {field: FieldProps}) {
  const Errors = usePart("Errors")
  const MembersOf = usePart("MembersOf")
  const {id, texts} = field
  const groups = field.groups!
  return (
    <div id={id} role="group" aria-labelledby={field.labelledby} aria-describedby={(field.error?.id as string | undefined) ?? undefined} data-groups="">
      <span {...attrs(groups.label)} className="text-sm">
        <span data-label="">{field.label}</span>
      </span>
      {field.error && <Errors error={field.error} errors={texts.errors} />}
      <HiddenEntries entries={groups.hidden} />
      {groups.items.map((item, index) => (
        <div key={item.key} {...attrs(item.element)} role="group" aria-labelledby={item.labelledby} aria-describedby={(item.error?.id as string | undefined) ?? undefined} data-group-item="" className="mb-2">
          <div className="flex items-center gap-1">
            <span {...attrs(item.label)} className="text-sm">
              {texts.value_position?.[index]}
            </span>
            <button type="button" {...attrs(item.remove)} aria-label={texts.remove_value?.[index]} className={button("ghost", "xs")}>
              <span aria-hidden="true">✕</span>
            </button>
          </div>
          {item.error && <Errors error={item.error} errors={texts.item_errors?.[index] || []} />}
          <div className="ps-4">
            <MembersOf members={item.members} />
          </div>
        </div>
      ))}
      <button type="button" {...attrs(groups.add)} className={button("outline", "sm")}>
        {texts.add_value}
      </button>
    </div>
  )
}

// The part `Union`: a union, the choice of its kind and, under it, that kind's value.
export function Union({field}: {field: FieldProps}) {
  const Field = usePart("Field")
  const GroupLabel = usePart("GroupLabel")
  const Errors = usePart("Errors")
  const MembersOf = usePart("MembersOf")
  const {id, texts} = field
  const union = field.union!
  const own = union["own_errors?"]
  const ref = React.useRef<HTMLSelectElement>(null)
  useServerValue(ref, union.kind)
  return (
    <div id={id} role="group" aria-labelledby={field.labelledby} aria-describedby={own ? ((field.error?.id as string | undefined) ?? undefined) : undefined} data-union="">
      <GroupLabel field={field} label={union.label} />
      {own && <Errors error={field.error} errors={texts.errors} />}
      <div className="ps-4">
        <HiddenEntries entries={union.hidden} />
        <div className="mb-3 flex flex-col gap-1" {...attrs(union.choice)}>
          <label {...attrs(union.kind_label)} className={LABEL}>
            <span data-label="">{texts.kind}</span>
          </label>
          <select ref={ref} {...attrs(union.select)} defaultValue={union.kind} className={select("h-8 w-full text-sm")}>
            {union["empty?"] && <option value=""></option>}
            {union.kinds.map(choice => (
              <option key={choice.value} value={choice.value}>
                {choice.label}
              </option>
            ))}
          </select>
        </div>
        {union.single && <Field key={union.single.id} field={union.single} />}
        {union.members && <MembersOf members={union.members} />}
      </div>
    </div>
  )
}

// The part `FileField`: a file, the island's own file input, which hands the files chosen to
// LiveView's input of the field (`uploadTo`, with the panel's form, which
// that input names), and a bar per file while it is sent.
export function FileField({field}: {field: FieldProps}) {
  const live = useLive()
  const upload = field.file!
  const ref = React.useRef<HTMLInputElement>(null)
  // a file is given once: where the server holds none of it any more (it
  // was sent, or taken back), the control is empty again, as LiveView's is
  const held = upload.entries.length
  React.useLayoutEffect(() => {
    if (held === 0 && ref.current && ref.current.value !== "") ref.current.value = ""
  }, [held])
  const handed = (e: React.SyntheticEvent<HTMLInputElement>) => {
    // the files are LiveView's input's to send: this one tells the form nothing
    e.stopPropagation()
    const el = e.currentTarget
    if (e.type === "change" && el.files && el.form) live.uploadTo(el.form, upload.name, el.files)
  }
  return (
    <>
      <label htmlFor={field.id} className={LABEL}>
        <span data-label="">{field.label}</span>
        {field["required?"] && <span aria-hidden="true">*</span>}
      </label>
      <input
        ref={ref}
        type="file"
        id={field.id}
        accept={upload.accept ?? undefined}
        multiple={upload["multiple?"]}
        aria-required={field["required?"] ? "true" : undefined}
        aria-invalid={field["invalid?"] ? "true" : undefined}
        aria-describedby={field.described ?? undefined}
        onChange={handed}
        onInput={handed}
        className={cn(input("h-8 w-full py-1 text-sm"), "file:me-2 file:border-0 file:bg-transparent file:text-sm")}
      />
      {upload.entries
        .filter(entry => entry["sending?"])
        .map(entry => (
          <progress key={entry.ref} value={entry.progress} max={100} aria-label={entry.name} className="mt-1 w-full">
            {entry.progress}%
          </progress>
        ))}
    </>
  )
}

// The part `ComponentEditor`: a field whose column's component edits, that component's editor (by its
// module, `reactKit({editors})`, as in a cell), on its control the field's
// id, name and what says it is required or wrong (`component.control`),
// else the control of its type, with a warning in development.
export function ComponentEditor({field}: {field: FieldProps}) {
  const components = usePart("editors")
  const component = field.component!
  const Component = components[component.module] ?? null
  const value = text(field.value)
  if (!Component) {
    if (process.env.NODE_ENV !== "production") console.warn(`ash_data_table: the React kit has no editor for ${component.module}; the field is typed as text`)
    return <input type="text" {...attrs(component.control)} defaultValue={value} className={input("h-8 w-full text-sm")} />
  }
  const editor: EditorProps = {
    name: field.name,
    label: field.label,
    required: field["required?"],
    limits: field.limits,
    control: {...component.control, defaultValue: value},
    value,
  }
  return <Component editor={editor} />
}
