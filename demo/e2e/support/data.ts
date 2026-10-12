import { expect, type APIRequestContext } from "@playwright/test"

// The data the tests run on: the demo's standard seed (Demo.Seeds), which
// gives the same records with the same ids and values every time, in
// whatever VM it runs: `mix run priv/repo/seeds.exs` when the server starts,
// and `POST /e2e/seed` in the server afterwards. Only dates move, as they
// are relative to today, so no test names a date of the seed.

/**
 * Empties the worker's database and seeds it again (half a second). It runs once
 * before the tests (actors.setup.ts) and after every test that says
 * `test.use({ writes: true })` (support/fixtures.ts). The route exists in
 * the e2e environment only (demo/e2e/server).
 */
export async function reseed(request: APIRequestContext): Promise<void> {
  const response = await request.post("/e2e/seed")
  expect(response.status(), "POST /e2e/seed: is the server running in MIX_ENV=e2e?").toBe(200)
  expect(await response.json()).toMatchObject({ profile: "standard", tasks: SEED.tasks.total })
}

/**
 * Runs `whileBroken` with the comments out of the database's reach, so that
 * every read of them fails as a database that is down would fail it, and
 * puts them back. Seeding puts them back as well.
 */
export async function withCommentsBroken(
  request: APIRequestContext,
  whileBroken: () => Promise<void>,
): Promise<void> {
  expect((await request.post("/e2e/comments/break")).status()).toBe(200)
  try {
    await whileBroken()
  } finally {
    expect((await request.post("/e2e/comments/mend")).status()).toBe(200)
  }
}

/** Deletes a task behind the table's back, as another person's destroy would. */
export async function deleteTask(request: APIRequestContext, id: string): Promise<void> {
  const response = await request.delete(`/e2e/tasks/${id}`)
  expect(await response.json()).toEqual({ deleted: 1 })
}

/** What the standard seed holds, as far as the tests count on it. */
export const SEED = {
  tasks: { total: 400, acme: 320, globex: 80 },
  /**
   * Comments of Acme: all of them, those whose body has an "a", and those
   * that say "Moved to the next sprint.", which are two keyset pages of 20.
   */
  comments: { acme: 384, withAnA: 311, nextSprint: 27 },
  projects: { acme: 6 },
  /** Projects of Acme by primary key. */
  project: {
    /** "Mobile app": 57 tasks, three offset pages of 25; 7 of them have "Fix" in their title */
    mobileApp: "72f2d7c8-f124-4435-9f12-15b4956af76b",
  },
  labels: { acme: 8 },
  taskLabels: { acme: 396 },
  specimens: {
    total: 36,
    /** how many have "Alpha" as their `a_ci_string` */
    alpha: 9,
    /** the first row of /specimens, "Specimen 001": every column of it has a value but `opt_string` */
    first: "2b63fed9-48ab-4270-aa82-3d81c7cbafae",
  },
  /**
   * The first rows of /task_labels (by task, then by label), by the two
   * parts of their key. The first three are labels of one task.
   */
  taskLabel: {
    first: "00a93d01-b260-4126-9715-9ae8e9340287-13eeb792-2564-48dd-b1aa-f7f74a3ddd7a",
    second: "00a93d01-b260-4126-9715-9ae8e9340287-7290c04a-9873-4058-b97b-ebc307a5d6b9",
    third: "00a93d01-b260-4126-9715-9ae8e9340287-f20780ce-3392-4203-aace-d0020a980647",
  },
  /**
   * Tasks of Acme on the first page of /tasks (newest first), by primary
   * key. The policies make them differ for the member:
   */
  task: {
    /** the first row. Neither assigned to the member nor reported by them. */
    first: "3f649715-4294-4816-9e2a-02c24949cef5",
    /** the second row, a task that is still to do */
    second: "fa6be352-2a29-4e47-bd81-e41941ab0f6d",
    /** the third row */
    third: "f6652ba6-2947-4920-8d83-2985df497966",
    /** assigned to the member: they see its estimate and may change it */
    membersOwn: "bc362be6-fa62-4282-83de-ca8676131bb4",
  },
} as const

/**
 * The values made of fields in the standard seed (maps.spec.ts): what the
 * cells of a few projects and tasks show. A project's client and its
 * milestones follow from its id, and a task's recurrence from the task's,
 * so they are the same in every seed; no date of them is named.
 */
export const MAPS = {
  project: {
    /** a client with an address; no milestone */
    customerPortal: {
      id: "0c70bdb6-7e47-41e2-be1e-985629d47bbb",
      client:
        "Name: Hafen & Söhne, Email: office@hafensohne.test, Key account?: Yes, Address: Street: Ernstweg 48, City: München, Postcode: 60948",
    },
    /** no client; two milestones, "First release" and "Review" */
    dataWarehouse: "f1892901-0837-4a04-9104-34fd12a9bb05",
    /** a client without an address; three milestones */
    internalTools: {
      id: "4b870188-0603-4a3d-9f75-d6610a951637",
      client: "Name: Nordwind GmbH, Email: office@nordwindgmbh.test, Key account?: No",
    },
  },
  task: {
    /** the second row of /tasks: comes round every four weeks, with no end */
    weekly: { id: SEED.task.second, recurrence: "Every: 4, Unit: Week" },
    /** the first row: does not come round */
    once: SEED.task.first,
  },
} as const
