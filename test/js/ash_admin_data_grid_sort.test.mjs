// The stock dataGrid's sort marks follow the sort state in the data model.
// The header reads its sort from `sort.path`, a path in a static prop, not a
// bound one; the A2UI data model notifies only the subscribers of a path
// that changed, so without a subscription of its own the grid kept the old
// marks whenever the server's sort reply left the bound rows as they were.

import test from "node:test";
import assert from "node:assert/strict";

import {admin, mergedCatalog} from "./catalogs.mjs";
import {mountHook} from "./harness.mjs";
import {feedback} from "../../priv/js/ash_a2ui_protocol.js";

async function settle() {
  for (let i = 0; i < 5; i++) await new Promise((resolve) => setTimeout(resolve, 0));
}

function deep(root, selector) {
  const found = root.querySelector(selector);
  if (found) return found;
  for (const node of root.querySelectorAll("*")) {
    const inner = node.shadowRoot && deep(node.shadowRoot, selector);
    if (inner) return inner;
  }
  return null;
}

const rows = [
  {id: "r1", title: "One"},
  {id: "r2", title: "Two"},
];

async function mountGrid(sort = null) {
  const hook = mountHook({catalogs: [mergedCatalog, admin]});
  hook.processMessages([
    {
      version: "1.0",
      createSurface: {
        surfaceId: "s1",
        catalogId: admin.id,
        components: [
          {id: "root", component: "Column", children: ["grid"]},
          {
            id: "grid",
            component: "dataGrid",
            columns: [
              {label: "Title", path: "title", sortable: true},
              {label: "Id", path: "id", sortable: true},
            ],
            rows: {"@path": "/records"},
            rowId: "id",
            sort: {path: "/query/sort", action: {name: "query", context: {}}},
          },
        ],
        dataModel: {records: rows, query: {page: 1, sort}, ui: {feedback: feedback()}},
      },
    },
  ]);
  const element = document.createElement("a2ui-surface");
  document.body.replaceChildren(element);
  element.surface = hook.processor.getSurface("s1");
  await settle();
  const grid = deep(element, "ash-admin-data-grid");
  assert.ok(grid, "the grid renders");
  return {hook, element, grid};
}

const marks = (grid) =>
  Object.fromEntries(
    [...grid.renderRoot.querySelectorAll("thead th")].map((th) => [
      th.querySelector(".sort-button span").textContent,
      th.getAttribute("aria-sort"),
    ]),
  );

const write = (hook, path, value) =>
  hook.processMessages([{version: "1.0", updateDataModel: {surfaceId: "s1", path, value}}]);

test("the marks follow a new sort written over the whole query, the rows unchanged", async () => {
  const {hook, grid} = await mountGrid();
  assert.deepEqual(marks(grid), {Title: "none", Id: "none"});

  write(hook, "/query", {page: 1, sort: {field: "title", dir: "desc"}});
  await settle();
  assert.deepEqual(marks(grid), {Title: "descending", Id: "none"});

  write(hook, "/query", {page: 1, sort: null});
  await settle();
  assert.deepEqual(marks(grid), {Title: "none", Id: "none"});
});

test("the marks follow a write to the sort path itself", async () => {
  const {hook, grid} = await mountGrid({field: "title", dir: "asc"});
  assert.deepEqual(marks(grid), {Title: "ascending", Id: "none"});

  write(hook, "/query/sort", {field: "id", dir: "asc"});
  await settle();
  assert.deepEqual(marks(grid), {Title: "none", Id: "ascending"});
});

test("a removed grid stops listening to the sort path", async () => {
  const {hook, element, grid} = await mountGrid();
  let updates = 0;
  const requestUpdate = grid.requestUpdate.bind(grid);
  grid.requestUpdate = (...args) => {
    updates++;
    return requestUpdate(...args);
  };

  element.remove();
  await settle();
  updates = 0;

  write(hook, "/query/sort", {field: "title", dir: "asc"});
  await settle();
  assert.equal(updates, 0, "no update after the grid left the page");
});
