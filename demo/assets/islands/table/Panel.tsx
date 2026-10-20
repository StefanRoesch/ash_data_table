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
// closes it destroys it and closes the dialog.
//
// The form is the island's: LiveView hears its `phx-change` and
// `phx-submit` from its root, as it hears the argument line's. Its controls
// are uncontrolled: what is typed is the browser's, and what the server
// gives is set where it changes, unless the person is in the control
// (`useServerValue`), as LiveView patches a form. Each field is what the
// table gives its `field` part (`DemoWeb.ReactKit.Props`), a value made of
// fields with its fields in it. The rows of a list field are the hook's
// once drawn (as the HEEx kit's `phx-update="ignore"`): drawn once per
// opening, never again.
//
// A file field: LiveView's own file input is drawn beside the island, out
// of sight, in this form (`form=`); the island's control hands it the files
// a person chooses (`uploadTo`, LiveView's documented hook function, which
// live_react gives the island), and says how far each has come.
import * as React from "react"
import {count, ids, mountPanel} from "ash_data_table"
import {useLiveReact} from "live_react"

import {attrs, type Bundle} from "./props"
import {Commits, Strict, useMountedWhile, useServerChecked, useServerValue, type Live} from "./mounting"
import {usePart} from "./parts"
import {Template, type EditorProps} from "./Editors"
import {closeDialog} from "./Picker"
import {box, button, input, select} from "./look"
import {cn} from "../lib/utils"

type Counted = {max: number; unit: string; "trim?": boolean; casing: string | null}
type Limits = {min: string | null; max: string | null; step: string | null}
type Members = {name: string; keys: {name: string; value: string}[]; fields: FieldProps[]}

export type FieldProps = {
  id: string
  name: string
  path: string
  editor: string
  label: string
  required: boolean
  sensitive: boolean
  item: string | null
  values: null | {value: string; label: string}[]
  value: string | string[] | null
  boxless: string[]
  invalid: boolean
  places: false | string
  limits: Limits
  counted: Counted | null
  count: Bundle | false | null
  clear: null | "offered" | "asked"
  clear_button: Bundle | false | null
  choose: Bundle | false
  chosen: null | {key: string; unpick: Bundle}[]
  component: string | false
  upload: null | {
    name: string
    ref: string
    accept: string | null
    multiple: boolean
    entries: {ref: string; name: string; progress: number; done: boolean; cancelled: boolean}[]
  }
  add: Bundle | false
  remove: Bundle | false
  members: Members | null
  items: {key: string; id: string; remove: Bundle; members: Members}[]
  kind: string | null
  kinds: null | {value: string; label: string}[]
  single: FieldProps | null
  texts: Record<string, any>
  list: false | {add_value: string; value_label: string; remove_label: string; value_position: string[]; remove_value: string[]}
}

export type PanelProps = {
  panel: {
    id: string
    open: boolean
    presentation: "modal" | "inline"
    place: string
    frame: Bundle | null
    form: Bundle | null
    title: string | null
    errors: false | null | string[]
    destructive: boolean
    cancel: {attrs: Bundle; text: string}
    submit: {id: string; text: string | null}
    fields: FieldProps[]
  }
}

export function AshPanel(props: PanelProps) {
  const PanelPart = usePart("Panel")
  return (
    <Strict>
      <PanelPart {...props} />
    </Strict>
  )
}

// The part `Panel`.
export function Panel({panel}: PanelProps) {
  const Field = usePart("Field")
  const live = useLiveReact() as unknown as Live
  const ref = React.useRef<HTMLElement>(null)
  const mounted = useMountedWhile(ref, panel.open, mountPanel, live, closeDialog)
  const modal = panel.presentation === "modal"
  const Tag = modal ? "dialog" : "section"
  const {open, id} = panel

  return (
    <Tag
      ref={ref as any}
      {...(open ? attrs(panel.frame) : {hidden: !modal})}
      className={modal ? "ash-react-dialog ash-react-side" : "ash-react-inline"}
    >
      <Commits mounted={mounted}>
        {open && (
          <form {...attrs(panel.form)}>
            <h2 id={`${id}-panel-title`} className="mb-4 text-lg font-semibold">
              {panel.title}
            </h2>
            {/* what the action says that is about none of the fields */}
            {panel.errors && (
              <div id={`${id}-panel-errors`} role="alert" className="mb-4 text-sm font-medium">
                {panel.errors.map((message, at) => (
                  <p key={at}>{message}</p>
                ))}
              </div>
            )}
            {panel.fields.map(field => (
              <Field key={field.id} field={field} />
            ))}
            <div className="mt-6 flex justify-end gap-2">
              <button type="button" {...attrs(panel.cancel.attrs)} className={button("outline", "sm")}>
                {panel.cancel.text}
              </button>
              <button type="submit" id={panel.submit.id} className={button(panel.destructive ? "destructive" : "default", "sm")}>
                {panel.submit.text}
              </button>
            </div>
          </form>
        )}
      </Commits>
      {/* what opens inside it is moved in here */}
      <div id={panel.place} className="contents"></div>
    </Tag>
  )
}

// What a control names as its description: the ids of what says something of it.
const described = (...given: (string | false | null | undefined)[]) => given.filter(Boolean).join(" ") || undefined

const text = (value: FieldProps["value"]) => (typeof value === "string" ? value : "")
const list = (value: FieldProps["value"]) => (Array.isArray(value) ? value : [])

const LABEL = "flex items-center gap-2 text-sm"
const TYPED = ["text", "enum", "number", "date", "datetime", "plain"]

// The part `Field`: one field of the panel, its label, the control of its
// type, and the action's errors about it; inside a value made of fields
// the same for each field in it.
export function Field({field}: {field: FieldProps}) {
  const Control = usePart("Control")
  const ListPart = usePart("List")
  const {id, editor, texts} = field
  const array = editor === "choices" || editor === "list"
  const group = editor === "group" || editor === "groups" || editor === "union"
  const file = editor === "file" && field.upload
  const reference = editor === "reference"
  const references = editor === "references"
  const counter = field.counted && editor === "text" ? `${id}-count` : null
  const error = field.invalid ? ids.error(id) : null
  const describedBy = described(error, counter)
  const secret = field.sensitive
  const called = reference ? texts.chosen?.[0] : null

  return (
    <div className="mb-3 flex flex-col gap-1" data-field={field.path}>
      {/* an unchecked box sends nothing: this says "false" for it */}
      {editor === "boolean" && <input type="hidden" name={field.name} value="false" />}
      {!array && !reference && !references && !group && !file && (
        <label htmlFor={id} className={LABEL}>
          {editor === "boolean" && <PanelBox id={id} name={field.name} checked={field.value === "true"} invalid={field.invalid} describedBy={describedBy} />}
          <span data-label="">{field.label}</span>
          {field.required && editor !== "boolean" && <span aria-hidden="true">*</span>}
        </label>
      )}
      {(array || references) && (
        <span id={`${id}-label`} className="text-sm">
          <span data-label="">{field.label}</span>
        </span>
      )}
      {/* the key of a related record is not typed: what the record is
      called, and the button that opens the picker, as a group */}
      {reference && (
        <>
          <span id={`${id}-label`} className="text-sm">
            <span data-label="">{field.label}</span>
            {field.required && <span aria-hidden="true">*</span>}
            {field.required && <span className="sr-only">{texts.required}</span>}
          </span>
          <div id={id} role="group" aria-labelledby={`${id}-label`} aria-describedby={describedBy} className="flex items-center gap-2">
            <input type="text" name={field.name} value={text(field.value)} readOnly hidden data-key="" />
            {called && (
              <span id={`${id}-chosen`} className="text-sm" data-chosen="">
                {called}
              </span>
            )}
            <button type="button" id={ids.choose(id)} aria-describedby={called ? `${id}-chosen` : undefined} {...attrs(field.choose)} className={button("outline", "sm")}>
              {texts.choose}
            </button>
          </div>
        </>
      )}
      {references && (
        <div id={id} role="group" aria-labelledby={`${id}-label`} aria-describedby={describedBy} data-references="" className="flex flex-col gap-1">
          <input type="text" name={`${field.name}[]`} value="" readOnly hidden data-own="" />
          {(field.chosen || []).map((chosen, at) => (
            <div key={chosen.key} className="flex items-center gap-1" data-chosen-item="">
              <input type="text" name={`${field.name}[]`} value={chosen.key} readOnly hidden data-key="" />
              <span id={`${id}-c-${at}`} className="text-sm" data-chosen="">
                {texts.chosen[at]}
              </span>
              <button type="button" id={ids.unpick(id, at)} {...attrs(chosen.unpick)} aria-label={texts.remove_chosen[at]} className={button("ghost", "xs")}>
                <span aria-hidden="true">✕</span>
              </button>
            </div>
          ))}
          <button type="button" id={ids.choose(id)} {...attrs(field.choose)} className={button("outline", "sm", "self-start")}>
            {texts.choose}
          </button>
        </div>
      )}
      {array && (
        <div id={id} role="group" aria-labelledby={`${id}-label`} aria-describedby={described(error)} data-invalid={field.places || undefined} className="flex flex-col gap-1">
          {/* a form sends nothing for a list without values: this entry is
          sent before the values in every case */}
          <input type="text" name={`${field.name}[]`} value="" readOnly hidden data-own="" />
          {editor === "choices" &&
            (field.values || []).map(choice => (
              <label key={choice.value} className={LABEL}>
                <PanelBox name={`${field.name}[]`} value={choice.value} checked={list(field.value).includes(choice.value)} invalid={field.invalid} />
                {choice.label}
              </label>
            ))}
          {/* what the field holds that is none of the choices, sent back as it came */}
          {field.boxless.map(value => (
            <input key={value} type="hidden" name={`${field.name}[]`} value={value} />
          ))}
          {editor === "list" && <ListPart field={field} />}
        </div>
      )}
      {editor === "group" && <Group field={field} />}
      {editor === "groups" && <Groups field={field} />}
      {editor === "union" && <Union field={field} />}
      {file && <FileField field={field} describedBy={described(error)} />}
      {editor === "component" && <ComponentEditor field={field} describedBy={describedBy} />}
      {/* a sensitive input, which is text or a number: typed hidden */}
      {((secret && field.clear !== "asked") || (!secret && TYPED.includes(editor))) && <Control field={field} describedBy={describedBy} />}
      {/* a sensitive field the action may empty: "Clear", and "Keep" once asked */}
      {field.clear === "asked" && (
        <p id={`${id}-cleared`} className="text-sm" data-cleared="">
          {texts.will_be_cleared}
        </p>
      )}
      {field.clear && (
        <button
          type="button"
          id={ids.clear(id)}
          aria-label={field.clear === "asked" ? texts.keep_value : texts.clear_value}
          aria-describedby={field.clear === "asked" ? `${id}-cleared` : undefined}
          {...attrs(field.clear_button)}
          className={button("outline", "sm", "self-start")}
        >
          {field.clear === "asked" ? texts.keep : texts.clear}
        </button>
      )}
      {counter && <Counter id={counter} field={field} value={text(field.value)} className="self-end" />}
      {/* in the text colour: the error colour is too faint for small text */}
      {field.invalid && !group && (
        <div id={ids.error(id)} className="mt-1 text-xs">
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

// The counter of a text: drawn anew where the server's value changes, as
// the server would draw it; the hook counts again as it is typed.
function Counter({id, field, value, className}: {id: string; field: FieldProps; value: string; className?: string}) {
  const Count = usePart("Count")
  const counted = field.counted!
  return <Count key={value} id={id} bundle={field.count} text={`${count(value, counted)}/${counted.max}`} className={className} />
}

function PanelBox({id, name, value = "true", checked, invalid, describedBy}: {id?: string; name: string; value?: string; checked: boolean; invalid: boolean; describedBy?: string}) {
  const ref = React.useRef<HTMLInputElement>(null)
  useServerChecked(ref, checked)
  return <input ref={ref} type="checkbox" id={id} name={name} value={value} aria-invalid={invalid ? "true" : undefined} aria-describedby={describedBy} className={box()} />
}

const INPUT: Record<string, string> = {number: "number", date: "date", datetime: "datetime-local"}
// any number, not only whole ones; a datetime to the second, as it is shown
const STEP: Record<string, string> = {number: "any", datetime: "1"}

// The part `Control`: the control of a field that is typed or chosen from
// a list: typed hidden where it is sensitive (it starts empty, and holds
// what was typed into it in this panel), a text in a textarea, a choice
// in a menu, anything else in an input of its type, with what the
// constraints of a number say of it (`limits`).
export function Control({field, describedBy}: {field: FieldProps; describedBy?: string}) {
  const ref = React.useRef<any>(null)
  const value = text(field.value)
  useServerValue(ref, value)
  const common = {
    ref,
    id: field.id,
    name: field.name,
    defaultValue: value,
    "aria-required": field.required ? ("true" as const) : undefined,
    "aria-invalid": field.invalid ? ("true" as const) : undefined,
    "aria-describedby": describedBy,
  }

  if (field.sensitive) return <input type="password" autoComplete="off" {...common} className={input("h-8 w-full text-sm")} />
  if (field.editor === "text") return <textarea rows={3} {...common} className={input("h-auto w-full py-1 text-sm")} />
  if (field.editor === "enum") {
    return (
      <select {...common} className={select("h-8 w-full text-sm")}>
        {(!field.required || value === "") && <option value=""></option>}
        {(field.values || []).map(choice => (
          <option key={choice.value} value={choice.value}>
            {choice.label}
          </option>
        ))}
      </select>
    )
  }
  return (
    <input
      type={INPUT[field.editor] ?? "text"}
      step={field.limits.step ?? STEP[field.editor]}
      min={field.limits.min ?? undefined}
      max={field.limits.max ?? undefined}
      {...common}
      className={input("h-8 w-full text-sm")}
    />
  )
}

// The part `List`: the field of an array, value by value, its rows the
// hook's once drawn (it adds them from the template and takes them away):
// drawn once, never again while the panel is open.
export const List = React.memo(
  function List({field}: {field: FieldProps}) {
    const texts = field.list || {add_value: "", value_label: "", remove_label: "", value_position: [], remove_value: []}
    const listId = `${field.id}-values`
    const values = list(field.value)
    const item = (value: string, position: number | null) => (
      <ListItem field={field} listId={listId} value={value} position={position} valueLabel={position ? texts.value_position[position - 1] : null} removeLabel={position ? texts.remove_value[position - 1] : null} />
    )
    return (
      <div id={listId} data-list="" data-value-label={texts.value_label} data-remove-label={texts.remove_label} className="flex flex-col items-stretch gap-1">
        <Template bundle={{}}>{item("", null)}</Template>
        {values.map((value, at) => (
          <React.Fragment key={at}>{item(value, at + 1)}</React.Fragment>
        ))}
        <button type="button" data-add="" className={button("outline", "sm", "self-start")}>
          {texts.add_value}
        </button>
      </div>
    )
  },
  () => true,
)

function ListItem({field, listId, value, position, valueLabel, removeLabel}: {
  field: FieldProps
  listId: string
  value: string
  position: number | null
  valueLabel: string | null
  removeLabel: string | null
}) {
  const Count = usePart("Count")
  const kind = field.item
  const name = `${field.name}[]`
  const countId = field.counted && position ? `${listId}-count-${position}` : undefined
  const label = valueLabel ?? undefined
  return (
    <div data-item="" className="flex items-center gap-1">
      {kind === "boolean" && <input type="hidden" name={name} value={String(value === "true")} />}
      {kind === "boolean" && <input type="checkbox" defaultChecked={value === "true"} aria-label={label} className={box()} />}
      {kind === "text" && <textarea rows={1} name={name} defaultValue={value} aria-label={label} aria-describedby={countId} className={input("h-auto min-h-0 flex-1 py-1 text-sm")} />}
      {kind === "text" && field.counted && <Count id={countId ?? ""} bundle={field.count} text={`${count(value, field.counted)}/${field.counted.max}`} />}
      {(kind === "number" || kind === "date" || kind === "datetime") && (
        <input
          type={INPUT[kind]}
          step={field.limits.step ?? STEP[kind]}
          min={field.limits.min ?? undefined}
          max={field.limits.max ?? undefined}
          name={name}
          defaultValue={value}
          aria-label={label}
          className={input("h-8 flex-1 text-sm")}
        />
      )}
      <button type="button" data-remove="" aria-label={removeLabel ?? undefined} className={button("ghost", "xs")}>
        <span aria-hidden="true">✕</span>
      </button>
    </div>
  )
}

// The fields of one value made of fields: the entry that says it is there,
// the keys it sends back as they came, and a field per input.
function MembersOf({members}: {members: Members}) {
  const Field = usePart("Field")
  return (
    <>
      <input type="hidden" name={`${members.name}[_present]`} value="" />
      {members.keys.map(key => (
        <input key={key.name} type="hidden" name={key.name} value={key.value} />
      ))}
      {members.fields.map(inner => (
        <Field key={inner.id} field={inner} />
      ))}
    </>
  )
}

function Errors({id, errors}: {id: string; errors: string[]}) {
  return (
    <div id={ids.error(id)} className="mb-1 text-xs">
      {errors.map((message, at) => (
        <p key={at} data-error="">
          {message}
        </p>
      ))}
    </div>
  )
}

function GroupLabel({field}: {field: FieldProps}) {
  return (
    <span id={`${field.id}-label`} className="text-sm">
      <span data-label="">{field.label}</span>
      {field.required && <span aria-hidden="true">*</span>}
      {field.required && <span className="sr-only">{field.texts.required}</span>}
    </span>
  )
}

// A value made of fields: its fields while it holds one, the button that
// takes it away where it may be left out, else the one that adds it.
function Group({field}: {field: FieldProps}) {
  const {id, texts} = field
  return (
    <div id={id} role="group" aria-labelledby={`${id}-label`} aria-describedby={field.invalid ? ids.error(id) : undefined} data-group="">
      <div className="flex items-center gap-1">
        <GroupLabel field={field} />
        {field.members && field.remove && (
          <button type="button" id={`${id}-remove`} {...attrs(field.remove)} aria-label={texts.remove_group} className={button("ghost", "xs")}>
            <span aria-hidden="true">✕</span>
          </button>
        )}
      </div>
      {field.invalid && <Errors id={id} errors={texts.errors} />}
      {field.members && (
        <div className="ps-4">
          <MembersOf members={field.members} />
        </div>
      )}
      {!field.members && (
        <button type="button" id={`${id}-add`} {...attrs(field.add)} className={button("outline", "sm")}>
          {texts.add_value}
        </button>
      )}
    </div>
  )
}

// A list of values made of fields: a group per value, each under a number
// of its own, with the button that takes it away; then the one that adds one.
function Groups({field}: {field: FieldProps}) {
  const {id, texts} = field
  return (
    <div id={id} role="group" aria-labelledby={`${id}-label`} aria-describedby={field.invalid ? ids.error(id) : undefined} data-groups="">
      <span id={`${id}-label`} className="text-sm">
        <span data-label="">{field.label}</span>
      </span>
      {field.invalid && <Errors id={id} errors={texts.errors} />}
      <input type="hidden" name={`${field.name}[_present]`} value="" />
      {field.items.map((item, index) => {
        const errors: string[] = texts.item_errors?.[index] || []
        return (
          <div key={item.key} id={item.id} role="group" aria-labelledby={`${item.id}-label`} aria-describedby={errors.length > 0 ? ids.error(item.id) : undefined} data-group-item="" className="mb-2">
            <div className="flex items-center gap-1">
              <span id={`${item.id}-label`} className="text-sm">
                {texts.value_position?.[index]}
              </span>
              <button type="button" id={`${item.id}-remove`} {...attrs(item.remove)} aria-label={texts.remove_value?.[index]} className={button("ghost", "xs")}>
                <span aria-hidden="true">✕</span>
              </button>
            </div>
            {errors.length > 0 && <Errors id={item.id} errors={errors} />}
            <div className="ps-4">
              <MembersOf members={item.members} />
            </div>
          </div>
        )
      })}
      <button type="button" id={`${id}-add`} {...attrs(field.add)} className={button("outline", "sm")}>
        {texts.add_value}
      </button>
    </div>
  )
}

// A union: the choice of its kind and, under it, that kind's value.
function Union({field}: {field: FieldProps}) {
  const Field = usePart("Field")
  const {id, texts} = field
  const kind = field.kind ?? ""
  const own: string[] = field.single ? [] : texts.errors
  const ref = React.useRef<HTMLSelectElement>(null)
  useServerValue(ref, kind)
  return (
    <div id={id} role="group" aria-labelledby={`${id}-label`} aria-describedby={own.length > 0 ? ids.error(id) : undefined} data-union="">
      <GroupLabel field={field} />
      {own.length > 0 && <Errors id={id} errors={own} />}
      <div className="ps-4">
        <input type="hidden" name={`${field.name}[_of]`} value={kind} />
        <div className="mb-3 flex flex-col gap-1" data-field={`${field.path}._union_type`}>
          <label htmlFor={`${id}-kind`} className={LABEL}>
            <span data-label="">{texts.kind}</span>
          </label>
          <select ref={ref} id={`${id}-kind`} name={`${field.name}[_union_type]`} defaultValue={kind} aria-required={field.required ? "true" : undefined} className={select("h-8 w-full text-sm")}>
            {(!field.required || kind === "") && <option value=""></option>}
            {(field.kinds || []).map(choice => (
              <option key={choice.value} value={choice.value}>
                {choice.label}
              </option>
            ))}
          </select>
        </div>
        {field.single && <Field key={field.single.id} field={field.single} />}
        {field.members && <MembersOf members={field.members} />}
      </div>
    </div>
  )
}

// A file: the island's own file input, which hands the files chosen to
// LiveView's input of the field (`uploadTo`, with the panel's form, which
// that input names), and a bar per file while it is sent.
function FileField({field, describedBy}: {field: FieldProps; describedBy?: string}) {
  const live = useLiveReact() as unknown as Live & {uploadTo: (target: Element, name: string, files: FileList) => void}
  const upload = field.upload!
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
        {field.required && <span aria-hidden="true">*</span>}
      </label>
      <input
        ref={ref}
        type="file"
        id={field.id}
        accept={upload.accept ?? undefined}
        multiple={upload.multiple}
        aria-required={field.required ? "true" : undefined}
        aria-invalid={field.invalid ? "true" : undefined}
        aria-describedby={describedBy}
        onChange={handed}
        onInput={handed}
        className={cn(input("h-8 w-full py-1 text-sm"), "file:me-2 file:border-0 file:bg-transparent file:text-sm")}
      />
      {upload.entries
        .filter(entry => entry.progress > 0 && !entry.done && !entry.cancelled)
        .map(entry => (
          <progress key={entry.ref} value={entry.progress} max={100} aria-label={entry.name} className="mt-1 w-full">
            {entry.progress}%
          </progress>
        ))}
    </>
  )
}

// A field whose column's component edits: that component's editor (by its
// module, `reactKit({editors})`, as in a cell), on its control the field's
// id, name and value, else the control of its type, with a warning in
// development.
function ComponentEditor({field, describedBy}: {field: FieldProps; describedBy?: string}) {
  const components = usePart("editors")
  const Component = field.component ? components[field.component] : null
  const control: Bundle & Record<string, any> = {
    id: field.id,
    name: field.name,
    "data-control": true,
    ...(field.required ? {"aria-required": "true"} : {}),
    ...(field.invalid ? {"aria-invalid": "true"} : {}),
    ...(describedBy ? {"aria-describedby": describedBy} : {}),
  }
  if (!Component) {
    if (process.env.NODE_ENV !== "production") console.warn(`ash_data_table: the React kit has no editor for ${field.component}; the field is typed as text`)
    return <input type="text" {...attrs(control)} defaultValue={text(field.value)} className={input("h-8 w-full text-sm")} />
  }
  const editor = {
    name: field.name,
    label: field.label,
    required: field.required,
    limits: field.limits,
    control: {...control, defaultValue: text(field.value)},
  } as unknown as EditorProps
  return <Component editor={editor} />
}
