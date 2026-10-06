import { expect, type APIRequestContext } from "@playwright/test"

// The data the tests run on: the demo's standard seed (Demo.Seeds), which
// gives the same records with the same ids every time. Only dates move, as
// they are relative to today, so no test names a date of the seed.

/**
 * Empties the database and seeds it again (under a second). It runs once
 * before the tests (actors.setup.ts) and after every test that says
 * `test.use({ writes: true })` (support/fixtures.ts). The route exists in
 * the e2e environment only (demo/e2e/server).
 */
export async function reseed(request: APIRequestContext): Promise<void> {
  const response = await request.post("/e2e/seed")
  expect(response.status(), "POST /e2e/seed: is the server running in MIX_ENV=e2e?").toBe(200)
  expect(await response.json()).toMatchObject({ profile: "standard", tasks: SEED.tasks.total })
}

/** Deletes a task behind the table's back, as another person's destroy would. */
export async function deleteTask(request: APIRequestContext, id: string): Promise<void> {
  const response = await request.delete(`/e2e/tasks/${id}`)
  expect(await response.json()).toEqual({ deleted: 1 })
}

/** What the standard seed holds, as far as the tests count on it. */
export const SEED = {
  tasks: { total: 400, acme: 320, globex: 80 },
  comments: { acme: 384 },
  projects: { acme: 6 },
  labels: { acme: 8 },
  specimens: 36,
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
