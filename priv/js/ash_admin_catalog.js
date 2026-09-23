/**
 * Ash admin catalog v1 — semantic Lit components for the `@a2ui/lit`
 * renderer.
 *
 * `createAshAdminCatalog(deps)` builds a `@a2ui/web_core` Catalog
 * registered under the admin catalog id
 * (`https://ash-a2ui.dev/catalogs/admin/v1`) so a surface whose
 * `createSurface.catalogId` matches resolves these components. Registration
 * under a custom catalog id is first-class in the renderer:
 * `MessageProcessor.processCreateSurfaceMessage` resolves
 * `catalogs.find(c => c.id === catalogId)` by exact match (see
 * web_core `processing/message-processor.js`), and the renderer looks every
 * component type up via `catalog.components.get(type).tagName` (see @a2ui/lit
 * `surface/render-a2ui-node.js`). No merging into the basic catalog is
 * involved — the admin catalog is a sibling the host registers alongside it:
 *
 *     import {z} from "zod";
 *     import {Catalog} from "@a2ui/web_core/v0_9";
 *     import {basicCatalog, A2uiLitElement, A2uiController} from "@a2ui/lit/v0_9";
 *     import {html, css, nothing} from "lit";
 *     import {createAshAdminCatalog} from "../../deps/ash_a2ui/priv/js/ash_admin_catalog.js";
 *
 *     const adminCatalog = createAshAdminCatalog({
 *       Catalog, basicCatalog, A2uiLitElement, A2uiController,
 *       lit: {html, css, nothing},
 *       // `z` is OPTIONAL since issue #5: binding-capable props are built
 *       // from @a2ui/web_core's own exported schema builders (web_core's
 *       // zod 3), so the host zod is no longer consumed. If you still pass
 *       // `z`, it must be the same zod MAJOR as @a2ui/web_core (zod 3) —
 *       // a foreign major throws immediately.
 *       z,
 *     });
 *     configureAshA2ui({MessageProcessor, catalogs: [basicCatalog, adminCatalog]});
 *
 * The catalog EXTENDS the basic catalog (contract: "admin adds semantic
 * components; it does not remove primitives"): every component of
 * `deps.basicCatalog` is carried over — pass the stock `basicCatalog` or the
 * merged `createAshA2uiCatalog` result to inherit its upgrades — plus the
 * ten semantic components:
 *
 *   entityPage, dataGrid, emptyState, pagination, recordPanel, fieldDisplay,
 *   formSection, actionBar, statusBanner, confirmDialog
 *
 * (camelCase names are the wire contract, pinned by A2UI-101B/AC-1 and
 * `priv/a2ui/admin_v1/catalog.json`.)
 *
 * ## Events
 *
 * Every dispatched action reuses the existing envelopes byte-for-byte:
 *
 *   - row actions / ConfirmDialog confirm → the flat envelope the encoder
 *     emits (`{label, action: <name>, context: {...}}`), with
 *     `{"path": "id"}`-style leaves resolved against the clicked row's base
 *     path — the same resolution the basic catalog's templated buttons
 *     perform;
 *   - ActionBar primary → the `action` envelope prop (emitted as the frozen
 *     `submit_form` event), dispatched through the GenericBinder's own
 *     action resolution exactly like a basic Button; a reconstructed
 *     `{values: /form, recordId: /form/id[, query][, contexts]}` fallback
 *     covers envelope-less emissions;
 *   - Pagination prev/next → the `previousAction`/`nextAction` bare event
 *     objects the encoder emits (`{"name": "query", "context": {...}}`),
 *     resolved and dispatched with pageDelta ∓1/±1; a derivation fallback
 *     covers envelope-less emissions.
 *
 * ## A11y-hardened basic inputs
 *
 * The core basic-catalog inputs render adjacent validation errors but do not
 * wire `aria-invalid`/`aria-describedby` (verified against @a2ui/lit 0.10.x
 * `TextField.js`/`CheckBox.js`). To satisfy the renderer quality contract,
 * this catalog REPLACES TextField, CheckBox, ChoicePicker and DateTimeInput
 * (inside admin surfaces only — the basic catalog registered under its own id
 * is untouched) with equivalent components that associate a real `<label>`,
 * read the AshA2ui form-error state (`/errors/<field>`, derived from each
 * input's `/form/<field>` value binding), and render the error adjacent to
 * the control with the aria wiring. FormSection pairs the encoder's sibling
 * `form_error_<field>` Texts with their inputs so messages are never
 * double-rendered (see that component below).
 *
 * ## Design tokens
 *
 * See `ash_admin_tokens.js` — the public `--ash-admin-*` surface with
 * `--a2ui-*` fallbacks and restrained literal defaults. No CSS framework
 * dependencies; light-mode first, dark-mode coherent whenever the host
 * themes the `--a2ui-*` layer (e.g. via `ash_a2ui_theme.css`).
 *
 * ## Contract with the host bundle
 *
 * Same discipline as `ash_a2ui_catalog.js`: no bundled dependencies, the
 * host passes the single `lit` / `@a2ui` instance in. Verified against
 * @a2ui/lit 0.10.1 / @a2ui/web_core 0.11.0 / lit 3.x.
 *
 * ## Schema provenance (issue #5)
 *
 * `@a2ui/web_core`'s GenericBinder classifies binding-capable props by
 * introspecting **zod 3 internals** (`_def.typeName`, `_def.shape()` — see
 * its `scrapeSchemaBehavior`). This file used to build its ten component
 * schemas with the host's `z`; under a host zod 4 every node scraped as
 * STATIC, so reserved-path bindings rendered `[object Object]` and grids
 * stayed empty. The schemas are therefore now composed from web_core's own
 * exported builders (`DynamicStringSchema`, `DynamicValueSchema`,
 * `ActionSchema`, `ChildListSchema`, ... — imported from
 * `@a2ui/web_core/v0_9`, the SAME module instance the binder uses):
 * binder-visible under any host zod. Static (non-binding) props derive
 * their primitives from web_core's exported schemas via public zod-3
 * accessors, so the host's `z` is no longer consumed at all — passing it
 * is optional, and when it IS passed its major is checked loudly (see the
 * guard in `createAshAdminCatalog`).
 */

import {
  createAdminStyles,
  resolveEventContext,
  getByPath,
  formatDisplayValue,
  applyWeight,
  childRefs,
} from "./ash_admin_tokens.js";

// Schema builders from web_core's OWN zod (3.x) — the instance the
// GenericBinder introspects. Importing the module directly (rather than
// receiving builders through `deps`) guarantees instance identity: the
// host bundle resolves the same specifier the renderer uses, so there is
// no dual-zod hazard regardless of which zod the host itself bundles.
import {
  ActionSchema,
  AnyComponentSchema,
  CheckableSchema,
  ChildListSchema,
  ComponentIdSchema,
  CreateSurfaceMessageSchema,
  DataBindingSchema,
  DynamicBooleanSchema,
  DynamicNumberSchema,
  DynamicStringSchema,
  DynamicValueSchema,
  FunctionCallSchema,
} from "@a2ui/web_core/v0_9";

/** The admin catalog id a surface must declare to resolve here. */
const ADMIN_CATALOG_ID = "https://ash-a2ui.dev/catalogs/admin/v1";

/** Wire kinds (camelCase — pinned by the A2UI-101B contract) → tag names. */
const TAGS = {
  entityPage: "ash-admin-entity-page",
  dataGrid: "ash-admin-data-grid",
  emptyState: "ash-admin-empty-state",
  pagination: "ash-admin-pagination",
  recordPanel: "ash-admin-record-panel",
  fieldDisplay: "ash-admin-field-display",
  formSection: "ash-admin-form-section",
  actionBar: "ash-admin-action-bar",
  statusBanner: "ash-admin-status-banner",
  confirmDialog: "ash-admin-confirm-dialog",
};

/** Basic input kinds this catalog replaces with a11y-hardened elements. */
const INPUT_OVERRIDE_KINDS = ["TextField", "CheckBox", "ChoicePicker", "DateTimeInput"];
const INPUT_OVERRIDE_TAGS = {
  TextField: "ash-admin-textfield",
  CheckBox: "ash-admin-checkbox",
  ChoicePicker: "ash-admin-choicepicker",
  DateTimeInput: "ash-admin-datetimeinput",
};

// Responsive breakpoint: the DataGrid renders a real table at ≥ 48rem and a
// card list below it (CSS container query on the grid host).
const GRID_TABLE_MIN = "48rem";
void GRID_TABLE_MIN;

/**
 * Builds the admin catalog. See the module docs for the `deps` contract:
 * `{Catalog, basicCatalog, A2uiLitElement, A2uiController, z,
 * lit: {html, css, nothing}}`.
 *
 * @returns {object} a `@a2ui/web_core` Catalog registered under the admin
 *   catalog id, extending `deps.basicCatalog`.
 */
export function createAshAdminCatalog(deps) {
  const {Catalog, basicCatalog, A2uiLitElement, A2uiController, lit, z} = deps || {};

  // Loud guard (issue #5 defense): a foreign-zod `z` was the root cause of
  // reserved-path bindings rendering "[object Object]" — the GenericBinder
  // scrapes zod-3 internals, and under a different major every binding prop
  // scrapes STATIC. Binding schemas are now built from web_core's own
  // builders and `z` is optional, but any residual host-z usage must be
  // same-major or the catalog refuses to build with a message naming the
  // fix. (`z.string()._def?.typeName` is "ZodString" on zod 3; on zod 4
  // there is no typeName, so the optional chain short-circuits to undefined.)
  if (z && z.string()._def?.typeName !== "ZodString") {
    throw new Error(
      "createAshAdminCatalog: `z` must be the same zod major as @a2ui/web_core " +
        "(zod 3); binding schemas are now built from web_core's own builders — " +
        "upgrade or stop passing z for binding props",
    );
  }

  if (
    !Catalog ||
    !basicCatalog ||
    !A2uiLitElement ||
    !A2uiController ||
    !lit ||
    !lit.html ||
    !lit.css ||
    !lit.nothing
  ) {
    throw new Error(
      "createAshAdminCatalog: missing deps. Pass {Catalog, basicCatalog, " +
        "A2uiLitElement, A2uiController, lit: {html, css, nothing}} — Catalog is " +
        "the @a2ui/web_core Catalog class. `z` is optional (binding schemas are " +
        "built from @a2ui/web_core's own builders); if passed it must be zod 3.",
    );
  }

  const schemas = buildSchemas();
  const adminApis = Object.fromEntries(
    Object.keys(TAGS).map((kind) => [kind, {name: kind, schema: schemas[kind], tagName: TAGS[kind]}]),
  );

  defineAdminElements(deps, {adminApis});

  // The admin catalog extends the basic catalog: carry every basic component
  // (or the host's merged/overridden version of it), swapping the four input
  // kinds for the a11y-hardened elements, then add the ten semantic kinds.
  const components = [...basicCatalog.components.values()].map((component) =>
    INPUT_OVERRIDE_KINDS.includes(component.name)
      ? {...component, tagName: INPUT_OVERRIDE_TAGS[component.name]}
      : component,
  );

  return new Catalog(
    ADMIN_CATALOG_ID,
    [...components, ...Object.values(adminApis)],
    [...basicCatalog.functions.values()],
    basicCatalog.themeSchema,
  );
}

// ---------------------------------------------------------------------------
// Wire schemas
// ---------------------------------------------------------------------------

/**
 * Builds the zod schemas for the ten admin kinds.
 *
 * Every BEHAVIOR-BEARING (binding-capable) prop is composed from
 * `@a2ui/web_core`'s own exported builders — `DynamicStringSchema`,
 * `DynamicNumberSchema`, `DynamicBooleanSchema`, `DynamicValueSchema`,
 * `ChildListSchema`, `ActionSchema` — which are built on web_core's zod 3
 * and stamped with the `REF:common_types.json#/$defs/...` descriptions the
 * GenericBinder's `scrapeSchemaBehavior` keys on first. (The hand-built
 * host-z unions this file used before classified only via the binder's
 * zod-3 union-shape fallback, so they silently degraded to STATIC under a
 * host zod 4 — the issue #5 root cause.) Static props (plain strings,
 * numbers, booleans, enums, records) derive their primitives from
 * web_core's exported schemas too, via public zod-3 accessors, so the
 * whole schema tree is binder-visible regardless of the host zod.
 *
 * Exported for host-side verification (the binder classification repro).
 *
 * Schemas are deliberately NOT `.strict()` and tolerate `nil` wherever the
 * contract allows it, so the Elixir encoder can add props without breaking
 * component validation.
 */
export function buildSchemas() {
  // --- static primitives on web_core's own zod ------------------------------
  // Derived once from web_core's exported schemas via public zod-3
  // accessors (`.shape`, `.unwrap()`, static `.create()`), so static props
  // need no host `z`. Each primitive classifies STATIC in the binder (plain
  // ZodString/Number/Boolean/Any/Record — `ComponentIdSchema` is a plain
  // ZodString whose `component-id` child-ref stamp only matters inside
  // ChildList classification, which these positions never reach).
  const EmptyObject = DataBindingSchema.pick({});
  const Str = ComponentIdSchema;
  const Num = AnyComponentSchema.shape.weight.unwrap();
  const Bool = CreateSurfaceMessageSchema.shape.createSurface.shape.sendDataModel.unwrap();
  const Any = CreateSurfaceMessageSchema.shape.createSurface.shape.theme.unwrap();
  const RecordAny = FunctionCallSchema.shape.args;
  const ArrayOf = (element) => CheckableSchema.shape.checks.unwrap().constructor.create(element);
  const EnumOf = (values) => CreateSurfaceMessageSchema.shape.version.constructor.create(values);

  const formatEnum = () => EnumOf(["text", "datetime", "boolean", "number"]).optional();

  // Bare event objects exactly as `admin_page_action/3` emits them:
  // {"name": "query", "context": {...}} with absolute path refs.
  // Deliberately NOT a union with an event-shaped option — that would trip
  // the GenericBinder's ACTION detection and silently mis-dispatch these
  // values (dispatchAction drops payloads without an `event`).
  const bareEvent = () => EmptyObject.extend({name: Str, context: RecordAny.optional()});

  return {
    entityPage: EmptyObject.extend({
      title: DynamicStringSchema,
      description: DynamicStringSchema.nullable().optional(),
      children: ChildListSchema.optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    dataGrid: EmptyObject.extend({
      // `format` per column is optional (not pinned by the contract): when
      // the encoder provides it, cells format like FieldDisplay.
      columns: ArrayOf(
        EmptyObject.extend({
          label: Str,
          path: Str,
          format: formatEnum(),
        }),
      ),
      // Row arrays / a "/rows" binding / a function call — DynamicValue's
      // union covers the literal array, the {path} binding and the
      // {call} envelope, so the whole prop classifies DYNAMIC like the
      // hand-built union did.
      rows: DynamicValueSchema.optional(),
      rowId: Str.optional(),
      label: DynamicStringSchema.nullable().optional(),
      // Flat envelope shape the admin encoder emits (`admin_row_actions/2`):
      // `action` is the client action NAME string ("view_record",
      // "start_edit", "invoke") and `context` carries literal +
      // row-relative {"path": "id"} refs. Deliberately static values — the
      // DataGrid resolves the context against each clicked row's base path
      // itself, which the binder's component-scoped ACTION resolution
      // cannot do.
      rowActions: ArrayOf(
        EmptyObject.extend({
          label: DynamicStringSchema,
          action: Str,
          context: RecordAny.optional(),
          destructive: Bool.optional(),
        }),
      ).optional(),
      children: ChildListSchema.optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    emptyState: EmptyObject.extend({
      message: DynamicStringSchema.nullable().optional(),
      child: Str.optional(),
      children: ChildListSchema.optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    pagination: EmptyObject.extend({
      page: DynamicNumberSchema.nullable().optional(),
      pageSize: DynamicNumberSchema.nullable().optional(),
      total: DynamicNumberSchema.nullable().optional(),
      hasNext: DynamicBooleanSchema.nullable().optional(),
      visible: DynamicBooleanSchema.nullable().optional(),
      previousVisible: DynamicBooleanSchema.nullable().optional(),
      nextVisible: DynamicBooleanSchema.nullable().optional(),
      rangeText: DynamicStringSchema.nullable().optional(),
      label: DynamicStringSchema.nullable().optional(),
      prevAction: bareEvent().optional(),
      nextAction: bareEvent().optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    recordPanel: EmptyObject.extend({
      mode: DynamicStringSchema.nullable().optional(),
      title: DynamicStringSchema.nullable().optional(),
      recordId: DynamicValueSchema.nullable().optional(),
      children: ChildListSchema.optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    fieldDisplay: EmptyObject.extend({
      label: DynamicStringSchema,
      value: DynamicValueSchema.nullable().optional(),
      format: formatEnum(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    formSection: EmptyObject.extend({
      title: DynamicStringSchema.nullable().optional(),
      columns: Num.int().min(1).max(6).optional(),
      children: ChildListSchema.optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    actionBar: EmptyObject.extend({
      primaryLabel: DynamicStringSchema.nullable().optional(),
      busy: DynamicBooleanSchema.nullable().optional(),
      destructive: Bool.optional(),
      // Emitted as {"event": submit_event} — the frozen submit_form
      // envelope, binder-resolved into a callable (ActionSchema classifies
      // ACTION via its REF description and its {event} union option).
      action: ActionSchema.optional(),
      children: ChildListSchema.optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    statusBanner: EmptyObject.extend({
      kind: DynamicStringSchema.nullable().optional(),
      message: DynamicStringSchema.nullable().optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),

    confirmDialog: EmptyObject.extend({
      title: DynamicStringSchema.nullable().optional(),
      body: DynamicStringSchema.nullable().optional(),
      confirmLabel: DynamicStringSchema.nullable().optional(),
      destructive: Bool.optional(),
      action: ActionSchema.optional(),
      accessibility: Any.optional(),
      weight: Num.optional(),
    }),
  };
}

// ---------------------------------------------------------------------------
// Shared element helpers
// ---------------------------------------------------------------------------

function str(value) {
  return value === null || value === undefined ? "" : String(value);
}

/** Merges check-driven validation errors with the /errors state. */
function fieldErrors(props, selfError) {
  const errors = [];
  if (selfError) errors.push(selfError);
  if (Array.isArray(props?.validationErrors)) {
    for (const message of props.validationErrors) {
      if (message && !errors.includes(message)) errors.push(String(message));
    }
  }
  return errors;
}

/**
 * Normalizes a row-action entry into a raw `{event: {name, context}}`
 * envelope ready for resolveEventContext + dispatchAction. Prefers the flat
 * shape the admin encoder emits (`{label, action: <name>, context}`); a
 * legacy nested `{label, action: {event: ...}}` is tolerated defensively.
 */
function rowActionEnvelope(entry) {
  if (!entry || typeof entry !== "object") return null;
  if (typeof entry.action === "string") {
    return {event: {name: entry.action, context: entry.context || {}}};
  }
  const nested = entry.action;
  if (nested && typeof nested === "object" && nested.event && typeof nested.event.name === "string") {
    return nested;
  }
  return null;
}

/**
 * The AshA2ui form-error subscription shared by the a11y-hardened inputs:
 * derives `/errors/<field>` from the input's `/form/<field>` value binding
 * and keeps `el._amErrText` current. Purely additive to the controller's own
 * prop subscriptions.
 */
function syncFieldError(el) {
  const context = el.context;
  const raw = context?.componentModel?.properties;
  const valuePath = raw?.value?.path;
  const match = typeof valuePath === "string" ? /^\/form\/(.+)$/.exec(valuePath) : null;
  const errorPath = match ? `/errors/${match[1]}` : null;

  if (errorPath === el._amErrPath) return;

  if (el._amErrUnsub) {
    el._amErrUnsub.unsubscribe();
    el._amErrUnsub = null;
  }
  el._amErrPath = errorPath;
  el._amErrText = "";

  if (errorPath && context?.dataContext) {
    const dataModel = context.dataContext.surface.dataModel;
    el._amErrUnsub = dataModel.subscribe(errorPath, (value) => {
      el._amErrText = errorText(value);
      el.requestUpdate();
    });
    el._amErrText = errorText(dataModel.get(errorPath));
  }
}

function teardownFieldError(el) {
  if (el._amErrUnsub) {
    el._amErrUnsub.unsubscribe();
    el._amErrUnsub = null;
  }
  el._amErrPath = null;
  el._amErrText = "";
}

function errorText(value) {
  if (value === null || value === undefined || value === "") return "";
  if (Array.isArray(value)) {
    return value.filter((item) => item !== null && item !== undefined && item !== "").join(" · ");
  }
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

/**
 * Reconstructs the frozen submit_form context (see the basic-v2 emission's
 * `submit_button/2` / `submit_event/1`): `/form` values + `/form/id`
 * recordId, plus the `/query` and `/context` bindings whenever the surface's
 * data model carries them.
 */
function buildSubmitFormContext(surface) {
  const context = {
    values: {path: "/form"},
    recordId: {path: "/form/id"},
  };
  const dataModel = surface.dataModel;
  if (dataModel.get("/query") !== null && dataModel.get("/query") !== undefined) {
    context.query = {path: "/query"};
  }
  if (dataModel.get("/context") !== null && dataModel.get("/context") !== undefined) {
    context.contexts = {path: "/context"};
  }
  return context;
}

// ---------------------------------------------------------------------------
// Element definitions
// ---------------------------------------------------------------------------

/**
 * Defines every admin custom element (idempotent across LiveView remounts
 * and hot reloads). All classes are created inside the factory so they close
 * over the host's single Lit instance and the freshly-built APIs.
 */
function defineAdminElements(deps, {adminApis}) {
  const {basicCatalog, A2uiLitElement, A2uiController, lit} = deps;
  const {html, css, nothing} = lit;
  const {shared, buttons} = createAdminStyles(css);

  // Shared styles for the a11y-hardened inputs. Declared BEFORE the define
  // calls: class static field initializers evaluate eagerly, so anything
  // their `static styles` arrays reference must already be initialized.
  const inputBaseStyles = css`
    :host {
      display: block;
    }
    .field {
      display: flex;
      flex-direction: column;
      gap: var(--am-space-2xs);
      min-width: 0;
    }
    .field-label {
      font-size: var(--am-font-size-s);
      font-weight: var(--am-font-weight-medium);
      color: var(--am-text);
      width: fit-content;
    }
    .control {
      font: inherit;
      font-size: var(--am-font-size-m);
      color: var(--am-text);
      background: var(--am-surface);
      border: 1px solid var(--am-border-strong);
      border-radius: var(--am-radius-m);
      padding: var(--am-space-xs) var(--am-space-s);
      min-height: 2.25rem;
      width: 100%;
    }
    .control:hover:not([disabled]) {
      border-color: var(--am-text-faint);
    }
    .control:focus {
      outline: none;
      border-color: var(--am-primary);
      box-shadow: 0 0 0 3px color-mix(in srgb, var(--am-primary) 15%, transparent);
    }
    .control[aria-invalid="true"] {
      border-color: var(--am-error);
    }
    textarea.control {
      min-height: 4.5rem;
      resize: vertical;
    }
    .error {
      color: var(--am-error);
      font-size: var(--am-font-size-s);
      font-weight: var(--am-font-weight-medium);
    }
    .choices {
      display: flex;
      flex-direction: column;
      gap: var(--am-space-xs);
      margin: 0;
      padding: 0;
      border: none;
      min-inline-size: 0;
    }
    .choices-legend {
      font-size: var(--am-font-size-s);
      font-weight: var(--am-font-weight-medium);
      color: var(--am-text);
      padding: 0;
    }
    .choice {
      display: flex;
      align-items: center;
      gap: var(--am-space-xs);
      font-size: var(--am-font-size-m);
      font-weight: var(--am-font-weight-regular);
    }
    .choice input {
      width: 1rem;
      height: 1rem;
      accent-color: var(--am-primary);
    }
  `;

  defineEntityPage();
  defineDataGrid();
  defineEmptyState();
  definePagination();
  defineRecordPanel();
  defineFieldDisplay();
  defineFormSection();
  defineActionBar();
  defineStatusBanner();
  defineConfirmDialog();
  defineTextField();
  defineCheckBox();
  defineChoicePicker();
  defineDateTimeInput();

  /** Resolves the basic-catalog Api for an overridden input kind. */
  function basicInputApi(name) {
    // The catalog entry for this kind was swapped in createAshAdminCatalog
    // to {name, schema, tagName}; the element binds to the same schema, so
    // validation + binding behavior are identical to the basic input.
    const entry = basicCatalog.components.get(name);
    if (!entry) {
      throw new Error(`createAshAdminCatalog: basicCatalog has no ${name} component to extend.`);
    }
    return {name: entry.name, schema: entry.schema, tagName: INPUT_OVERRIDE_TAGS[name]};
  }

  // --- EntityPage: page shell ---------------------------------------------

  function defineEntityPage() {
    const tag = TAGS.entityPage;
    if (customElements.get(tag)) return;

    class AshAdminEntityPage extends A2uiLitElement {
      static styles = [
        shared,
        css`
          :host {
            display: block;
          }
          .page-header {
            margin: 0 0 var(--am-space-xl);
          }
          .page-title {
            margin: 0;
            font-size: var(--am-font-size-xl);
            font-weight: var(--am-font-weight-semibold);
            line-height: var(--am-line-height-tight);
            letter-spacing: -0.01em;
          }
          .page-description {
            margin: var(--am-space-2xs) 0 0;
            color: var(--am-text-muted);
            font-size: var(--am-font-size-m);
            max-width: 60ch;
          }
          .page-body {
            display: flex;
            flex-direction: column;
            gap: var(--am-space-xl);
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.entityPage);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        return html`
          <header class="page-header">
            <h1 class="page-title">${str(props.title)}</h1>
            ${props.description
              ? html`<p class="page-description">${str(props.description)}</p>`
              : nothing}
          </header>
          <div class="page-body">
            ${childRefs(props.children).map((ref) => html`${this.renderNode(ref)}`)}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminEntityPage);
  }

  // --- DataGrid: table / card collection -----------------------------------

  function defineDataGrid() {
    const tag = TAGS.dataGrid;
    if (customElements.get(tag)) return;

    class AshAdminDataGrid extends A2uiLitElement {
      constructor() {
        super();
        // Destructive row action awaiting confirmation:
        // {envelope, basePath, label}
        this.pendingConfirm = null;
        this._confirmEl = null;
      }

      static styles = [
        shared,
        buttons,
        css`
          :host {
            display: block;
            container-type: inline-size;
          }
          .grid-table {
            width: 100%;
            border-collapse: collapse;
            font-size: var(--am-font-size-m);
            background: var(--am-surface);
          }
          .grid-table th {
            text-align: left;
            font-size: var(--am-font-size-xs);
            font-weight: var(--am-font-weight-semibold);
            letter-spacing: var(--am-tracking-wide);
            text-transform: uppercase;
            color: var(--am-text-muted);
            padding: var(--am-space-s) var(--am-space-m);
            border-bottom: 1px solid var(--am-border-strong);
            white-space: nowrap;
          }
          .grid-table tbody tr:hover {
            background: var(--am-hover-tint);
          }
          .grid-table td,
          .grid-table th[scope="row"] {
            padding: var(--am-space-s) var(--am-space-m);
            border-bottom: 1px solid var(--am-border);
            text-align: left;
            vertical-align: top;
          }
          .grid-table th[scope="row"] {
            font-weight: var(--am-font-weight-medium);
            white-space: nowrap;
          }
          .grid-table tbody tr:last-child td,
          .grid-table tbody tr:last-child th {
            border-bottom: none;
          }
          .cell-actions {
            text-align: right;
            white-space: nowrap;
          }
          .cell-actions .am-btn + .am-btn,
          .card-actions .am-btn + .am-btn {
            margin-left: var(--am-space-2xs);
          }
          .grid-cards {
            display: none;
            list-style: none;
            margin: 0;
            padding: 0;
            gap: var(--am-space-m);
          }
          .card {
            background: var(--am-surface);
            border: 1px solid var(--am-border);
            border-radius: var(--am-radius-m);
            padding: var(--am-space-m) var(--am-space-l);
            box-shadow: var(--am-shadow-1);
          }
          .card-fields {
            margin: 0;
            display: grid;
            gap: var(--am-space-xs) var(--am-space-l);
            grid-template-columns: repeat(auto-fit, minmax(min(100%, 12rem), 1fr));
          }
          .card-field dt {
            font-size: var(--am-font-size-xs);
            font-weight: var(--am-font-weight-semibold);
            letter-spacing: var(--am-tracking-wide);
            text-transform: uppercase;
            color: var(--am-text-muted);
          }
          .card-field dd {
            margin: 0;
            min-width: 0;
            overflow-wrap: anywhere;
          }
          .card-actions {
            display: flex;
            justify-content: flex-end;
            gap: var(--am-space-2xs);
            margin-top: var(--am-space-m);
          }
          .grid-empty {
            display: grid;
            place-items: center;
            min-height: 12rem;
          }
          .no-records {
            margin: 0;
            color: var(--am-text-muted);
          }
          .grid-pagination {
            display: flex;
            justify-content: center;
            margin-top: var(--am-space-m);
          }
          /* Real table at ≥ 48rem, card list below. Browsers without
           * container queries degrade to the table. */
          @container (max-width: 47.99rem) {
            .grid-table {
              display: none;
            }
            .grid-cards {
              display: grid;
              grid-template-columns: 1fr;
            }
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.dataGrid);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      updated(changedProperties) {
        super.updated(changedProperties);
        this.syncConfirmDialog();
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        if (this._confirmEl && this._confirmEl.parentNode) {
          this._confirmEl.parentNode.removeChild(this._confirmEl);
        }
      }

      get surface() {
        return this.context?.dataContext?.surface;
      }

      /** Raw rows binding path — anchors each row action's relative refs. */
      get rowsBasePath() {
        const raw = this.context?.componentModel?.properties?.rows;
        return raw && typeof raw.path === "string" ? raw.path : null;
      }

      childType(ref) {
        try {
          return this.surface?.componentsModel?.get(ref.id)?.type ?? null;
        } catch {
          return null;
        }
      }

      partitionChildren() {
        const props = this.controller?.props;
        const empty = [];
        const pagination = [];
        const rest = [];
        for (const ref of childRefs(props?.children)) {
          const type = this.childType(ref);
          if (type === "emptyState") empty.push(ref);
          else if (type === "pagination") pagination.push(ref);
          else rest.push(ref);
        }
        return {empty, pagination, rest};
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const columns = Array.isArray(props.columns) ? props.columns : [];
        const rows = Array.isArray(props.rows) ? props.rows : [];
        const rowActions = Array.isArray(props.rowActions) ? props.rowActions : [];
        const label = str(props.label);
        const {empty, pagination, rest} = this.partitionChildren();

        return html`
          <div class="grid-root">
            ${rows.length === 0
              ? html`
                  <div class="grid-empty">
                    ${empty.length > 0
                      ? empty.map((ref) => html`${this.renderNode(ref)}`)
                      : html`<p class="no-records">
                          ${label ? `${label}: no records` : "No records"}
                        </p>`}
                  </div>
                `
              : html`
                  ${this.renderTable(columns, rows, rowActions, label)}
                  ${this.renderCards(columns, rows, rowActions, label)}
                `}
            ${pagination.length > 0
              ? html`<div class="grid-pagination">
                  ${pagination.map((ref) => html`${this.renderNode(ref)}`)}
                </div>`
              : nothing}
            ${rest.map((ref) => html`${this.renderNode(ref)}`)}
          </div>
        `;
        // The ConfirmDialog is mounted imperatively in updated() — dynamic
        // tag names cannot appear in Lit templates without unsafeStatic,
        // which is not part of this factory's deps contract.
      }

      renderTable(columns, rows, rowActions, label) {
        const hasActions = rowActions.length > 0;
        return html`
          <table class="grid-table" aria-label=${label || "Records"}>
            <thead>
              <tr>
                ${columns.map((column) => html`<th scope="col">${str(column.label)}</th>`)}
                ${hasActions
                  ? html`<th scope="col"><span class="sr-only">Actions</span></th>`
                  : nothing}
              </tr>
            </thead>
            <tbody>
              ${rows.map(
                (row, index) => this.renderTableRow(row, index, columns, rowActions, hasActions),
              )}
            </tbody>
          </table>
        `;
      }

      renderTableRow(row, index, columns, rowActions, hasActions) {
        const rowId = this.rowIdentity(row, index);
        return html`
          <tr id="row-${rowId}">
            ${columns.map((column, columnIndex) => {
              const cell = this.cellValue(row, column);
              return columnIndex === 0
                ? html`<th scope="row">${cell}</th>`
                : html`<td>${cell}</td>`;
            })}
            ${hasActions
              ? html`<td class="cell-actions">${this.renderRowActions(row, index, rowActions)}</td>`
              : nothing}
          </tr>
        `;
      }

      renderCards(columns, rows, rowActions, label) {
        return html`
          <ul class="grid-cards" aria-label=${label || "Records"}>
            ${rows.map((row, index) => this.renderCard(row, index, columns, rowActions))}
          </ul>
        `;
      }

      renderCard(row, index, columns, rowActions) {
        const hasActions = rowActions.length > 0;
        return html`
          <li class="card">
            <dl class="card-fields">
              ${columns.map(
                (column) => html`
                  <div class="card-field">
                    <dt>${str(column.label)}</dt>
                    <dd>${this.cellValue(row, column)}</dd>
                  </div>
                `,
              )}
            </dl>
            ${hasActions
              ? html`<div class="card-actions">${this.renderRowActions(row, index, rowActions)}</div>`
              : nothing}
          </li>
        `;
      }

      renderRowActions(row, index, rowActions) {
        return rowActions.map((action) => {
          const label = str(action?.label);
          const destructive = action?.destructive === true;
          return html`
            <button
              type="button"
              class="am-btn am-btn-quiet am-btn-sm ${destructive ? "am-btn-danger" : ""}"
              @click=${() => this.onRowAction(action, index)}
            >
              ${label}
            </button>
          `;
        });
      }

      /** Formats a cell: explicit column format wins; ISO-datetime-looking
       * strings format for readability; everything else uses text rules. */
      cellValue(row, column) {
        const value = getByPath(row, column.path);
        if (column.format) return formatDisplayValue(value, column.format);
        if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(value)) {
          return formatDisplayValue(value, "datetime");
        }
        return formatDisplayValue(value);
      }

      rowIdentity(row, index) {
        const rowIdProp = this.controller?.props?.rowId || "id";
        const value = getByPath(row, rowIdProp);
        return value === null || value === undefined ? `i${index}` : String(value);
      }

      rowBasePath(index) {
        return this.rowsBasePath ? `${this.rowsBasePath}/${index}` : "/";
      }

      onRowAction(action, index) {
        const envelope = rowActionEnvelope(action);
        if (!envelope) return;

        if (action.destructive === true) {
          // Destructive actions gate behind the ConfirmDialog; confirming
          // dispatches this exact envelope unchanged.
          this.pendingConfirm = {
            envelope,
            basePath: this.rowBasePath(index),
            label: str(action.label),
          };
          this.requestUpdate();
          return;
        }

        this.dispatchRowAction(envelope, this.rowBasePath(index));
      }

      dispatchRowAction(envelope, basePath) {
        const surface = this.surface;
        if (!surface || !this.context?.componentModel) return;
        const resolved = resolveEventContext(envelope, surface.dataModel, basePath);
        surface.dispatchAction(resolved, this.context.componentModel.id);
      }

      /**
       * Mounts/unmounts the ConfirmDialog element imperatively. Setting its
       * reactive properties (title/body/confirmLabel/open) drives its own
       * Lit update lifecycle, including the focus trap and focus restore.
       */
      syncConfirmDialog() {
        const pending = this.pendingConfirm;

        if (!pending) {
          if (this._confirmEl && this._confirmEl.open) this._confirmEl.open = false;
          if (this._confirmEl && this._confirmEl.parentNode) {
            this._confirmEl.parentNode.removeChild(this._confirmEl);
          }
          return;
        }

        if (!this._confirmEl) {
          this._confirmEl = document.createElement(TAGS.confirmDialog);
          this._confirmEl.addEventListener("confirm", () => {
            const current = this.pendingConfirm;
            this.pendingConfirm = null;
            this.requestUpdate();
            if (current) this.dispatchRowAction(current.envelope, current.basePath);
          });
          this._confirmEl.addEventListener("cancel", () => {
            this.pendingConfirm = null;
            this.requestUpdate();
          });
        }

        const dialog = this._confirmEl;
        dialog.title = `${pending.label} this record?`;
        dialog.body = "This action cannot be undone.";
        dialog.confirmLabel = pending.label || "Confirm";
        dialog.destructive = true;

        if (!dialog.parentNode) this.renderRoot.appendChild(dialog);
        // Open last: the dialog's updated() focuses its heading once mounted.
        if (!dialog.open) dialog.open = true;
      }
    }

    customElements.define(tag, AshAdminDataGrid);
  }

  // --- EmptyState: zero results --------------------------------------------

  function defineEmptyState() {
    const tag = TAGS.emptyState;
    if (customElements.get(tag)) return;

    class AshAdminEmptyState extends A2uiLitElement {
      static styles = [
        shared,
        css`
          :host {
            display: block;
          }
          .empty {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: var(--am-space-m);
            padding: var(--am-space-2xl) var(--am-space-xl);
            text-align: center;
          }
          .empty-glyph {
            display: grid;
            place-items: center;
            width: 3rem;
            height: 3rem;
            border-radius: var(--am-radius-pill);
            background: var(--am-surface-sunken);
            border: 1px solid var(--am-border);
            color: var(--am-text-faint);
          }
          .empty-message {
            margin: 0;
            color: var(--am-text-muted);
            font-size: var(--am-font-size-m);
            max-width: 40ch;
          }
          .empty-action {
            display: flex;
            gap: var(--am-space-s);
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.emptyState);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const action = props.child
          ? [this.renderNode(props.child)]
          : childRefs(props.children).map((ref) => this.renderNode(ref));

        return html`
          <div class="empty">
            <span class="empty-glyph" aria-hidden="true">
              <svg
                viewBox="0 0 24 24"
                width="20"
                height="20"
                fill="none"
                stroke="currentColor"
                stroke-width="1.5"
                stroke-linecap="round"
                stroke-linejoin="round"
                aria-hidden="true"
              >
                <path d="M4 7h16M4 12h16M4 17h10"></path>
              </svg>
            </span>
            <p class="empty-message">${str(props.message)}</p>
            ${action.length > 0 ? html`<div class="empty-action">${action}</div>` : nothing}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminEmptyState);
  }

  // --- Pagination: conditional navigation -----------------------------------

  function definePagination() {
    const tag = TAGS.pagination;
    if (customElements.get(tag)) return;

    class AshAdminPagination extends A2uiLitElement {
      static styles = [
        shared,
        buttons,
        css`
          :host {
            display: block;
          }
          .pager {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: var(--am-space-m);
            flex-wrap: wrap;
          }
          .pager-status {
            display: inline-flex;
            align-items: baseline;
            gap: var(--am-space-s);
            font-size: var(--am-font-size-m);
          }
          .pager-current {
            font-weight: var(--am-font-weight-semibold);
          }
          .pager-range {
            color: var(--am-text-muted);
            font-size: var(--am-font-size-s);
          }
          .pager-chevron {
            font-size: 1em;
            line-height: 1;
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.pagination);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;
        if (props.visible !== true) return nothing;

        const showPrevious = props.previousVisible === true;
        const showNext = props.nextVisible === true;
        const page =
          props.page === null || props.page === undefined || props.page === ""
            ? NaN
            : Number(props.page);
        const label = str(props.label) || "Results";

        return html`
          <nav class="pager" aria-label=${label}>
            ${showPrevious
              ? html`
                  <button
                    type="button"
                    class="am-btn am-btn-quiet am-btn-sm"
                    @click=${() => this.turnPage(-1)}
                  >
                    <span class="pager-chevron" aria-hidden="true">‹</span>
                    Previous
                  </button>
                `
              : nothing}
            <span class="pager-status">
              ${Number.isFinite(page)
                ? html`<span class="pager-current" aria-current="page">Page ${page}</span>`
                : nothing}
              ${props.rangeText
                ? html`<span class="pager-range">${str(props.rangeText)}</span>`
                : nothing}
            </span>
            ${showNext
              ? html`
                  <button
                    type="button"
                    class="am-btn am-btn-quiet am-btn-sm"
                    @click=${() => this.turnPage(1)}
                  >
                    Next
                    <span class="pager-chevron" aria-hidden="true">›</span>
                  </button>
                `
              : nothing}
          </nav>
        `;
      }

      /**
       * Dispatches the existing `query` envelope with the given pageDelta.
       *
       * Priority: the `previousAction`/`nextAction` event object the admin
       * encoder emits (`{"name": "query", "context": {...}}`, byte-exact) —
       * its path refs are resolved at click time and dispatched; a legacy
       * callable or `{event: {...}}` envelope is tolerated; when neither is
       * present the envelope is reconstructed like the basic-v2
       * `query_button/2` emission: the query path is derived from the `page`
       * binding, `component` is added for multi-table surfaces, and the
       * `contexts` binding rides along when the surface carries context
       * state.
       */
      turnPage(delta) {
        const props = this.controller?.props;
        if (!props) return;

        const envelope = delta < 0 ? props.prevAction : props.nextAction;

        if (typeof envelope === "function") {
          envelope();
          return;
        }

        const context = this.context;
        const surface = context?.dataContext?.surface;
        if (!surface || !context.componentModel) return;

        if (envelope && typeof envelope.name === "string") {
          const resolved = resolveEventContext(
            {event: {name: envelope.name, context: envelope.context || {}}},
            surface.dataModel,
            "/",
          );
          surface.dispatchAction(resolved, context.componentModel.id);
          return;
        }

        if (envelope && envelope.event && typeof envelope.event.name === "string") {
          const resolved = resolveEventContext(envelope, surface.dataModel, "/");
          surface.dispatchAction(resolved, context.componentModel.id);
          return;
        }

        const raw = context.componentModel.properties || {};
        const pagePath =
          typeof raw.page?.path === "string"
            ? raw.page.path
            : typeof raw.pageSize?.path === "string"
              ? raw.pageSize.path
              : null;

        let queryPath = "/query";
        if (pagePath && pagePath.endsWith("/page")) {
          queryPath = pagePath.slice(0, -"/page".length) || "/query";
        }

        const actionContext = {pageDelta: delta, query: {path: queryPath}};
        if (queryPath !== "/query") {
          const segments = queryPath.split("/");
          actionContext.component = segments[segments.length - 1];
        }
        const contexts = surface.dataModel.get("/context");
        if (contexts !== null && contexts !== undefined && typeof contexts === "object") {
          actionContext.contexts = {path: "/context"};
        }

        const resolved = resolveEventContext(
          {event: {name: "query", context: actionContext}},
          surface.dataModel,
          "/",
        );
        surface.dispatchAction(resolved, context.componentModel.id);
      }
    }

    customElements.define(tag, AshAdminPagination);
  }

  // --- RecordPanel: explicit task panel -------------------------------------

  function defineRecordPanel() {
    const tag = TAGS.recordPanel;
    if (customElements.get(tag)) return;

    const MODE_HEADINGS = {
      view: "View record",
      create: "Create record",
      edit: "Edit record",
    };

    class AshAdminRecordPanel extends A2uiLitElement {
      constructor() {
        super();
        this._amLastMode = null;
        this._amRestoreFocus = null;
      }

      static styles = [
        shared,
        css`
          :host {
            display: block;
          }
          .panel {
            background: var(--am-surface-raised);
            border: 1px solid var(--am-border);
            border-radius: var(--am-radius-l);
            box-shadow: var(--am-shadow-2);
            padding: var(--am-space-xl);
            margin: var(--am-space-s) 0 var(--am-space-m);
            max-width: 56rem;
          }
          .panel-title {
            margin: 0 0 var(--am-space-l);
            font-size: var(--am-font-size-l);
            font-weight: var(--am-font-weight-semibold);
            line-height: var(--am-line-height-tight);
          }
          .panel-title:focus {
            outline: none;
          }
          .panel-title:focus-visible {
            outline: 2px solid var(--am-focus);
            outline-offset: 2px;
          }
          .panel-fields {
            margin: 0;
            display: flex;
            flex-direction: column;
          }
          .panel-form {
            display: flex;
            flex-direction: column;
            gap: var(--am-space-l);
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.recordPanel);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);

        // Capture the pre-panel focus BEFORE the DOM gains the panel, so
        // closing restores the user to whatever invoked the task (the row's
        // View/Edit button, a Create button, …).
        const mode = this.resolvedMode();
        if (mode && !this._amLastMode && !this._amRestoreFocus) {
          this._amRestoreFocus = document.activeElement;
        }

        applyWeight(this, this.controller?.props);
      }

      updated(changedProperties) {
        super.updated(changedProperties);
        const mode = this.resolvedMode();

        if (mode && !this._amLastMode) {
          // Panel opened: move focus into the panel.
          this.focusPanel();
        } else if (!mode && this._amLastMode) {
          // Panel closed (mode → nil = back to browse): restore focus.
          if (this._amRestoreFocus && this._amRestoreFocus.isConnected) {
            this._amRestoreFocus.focus();
          }
          this._amRestoreFocus = null;
        } else if (mode && mode !== this._amLastMode) {
          // Task switched (view ↔ edit): the content changed wholesale, so
          // bring focus back to the panel heading.
          this.focusPanel();
        }

        this._amLastMode = mode;
      }

      resolvedMode() {
        const mode = this.controller?.props?.mode;
        return mode === null || mode === undefined || mode === "" ? null : String(mode);
      }

      focusPanel() {
        const heading = this.renderRoot?.querySelector("[data-panel-heading]");
        if (heading) heading.focus();
      }

      childType(ref) {
        try {
          return this.context?.dataContext?.surface?.componentsModel?.get(ref.id)?.type ?? null;
        } catch {
          return null;
        }
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;
        const mode = this.resolvedMode();
        if (!mode) return nothing;

        const isView = mode === "view";
        const refs = childRefs(props.children).filter((ref) => {
          const type = this.childType(ref);
          if (type === "fieldDisplay") return isView;
          return !isView;
        });

        const title = str(props.title);
        const headingText = title || MODE_HEADINGS[mode] || "";

        return html`
          <section
            class="panel"
            aria-label=${headingText || "Record panel"}
            data-record-id=${str(props.recordId ?? "")}
          >
            <h2 class="panel-title" tabindex="-1" data-panel-heading>
              ${headingText}
            </h2>
            ${isView
              ? html`<dl class="panel-fields">
                  ${refs.map((ref) => html`${this.renderNode(ref)}`)}
                </dl>`
              : html`<div class="panel-form">
                  ${refs.map((ref) => html`${this.renderNode(ref)}`)}
                </div>`}
          </section>
        `;
      }
    }

    customElements.define(tag, AshAdminRecordPanel);
  }

  // --- FieldDisplay: read-only value ----------------------------------------

  function defineFieldDisplay() {
    const tag = TAGS.fieldDisplay;
    if (customElements.get(tag)) return;

    class AshAdminFieldDisplay extends A2uiLitElement {
      static styles = [
        shared,
        css`
          :host {
            display: block;
            container-type: inline-size;
          }
          .field {
            display: grid;
            grid-template-columns: minmax(8rem, 33%) 1fr;
            gap: var(--am-space-2xs) var(--am-space-l);
            align-items: baseline;
            padding: var(--am-space-xs) 0;
            border-bottom: 1px solid var(--am-border);
          }
          :host(:last-child) .field,
          .field:last-child {
            border-bottom: none;
          }
          .field-label {
            font-size: var(--am-font-size-xs);
            font-weight: var(--am-font-weight-semibold);
            letter-spacing: var(--am-tracking-wide);
            text-transform: uppercase;
            color: var(--am-text-muted);
          }
          .field-value {
            margin: 0;
            font-size: var(--am-font-size-m);
            overflow-wrap: anywhere;
          }
          .field-value-boolean {
            display: inline-flex;
            align-items: center;
            gap: var(--am-space-2xs);
            font-weight: var(--am-font-weight-medium);
          }
          .field-value-boolean::before {
            content: "";
            width: 0.5rem;
            height: 0.5rem;
            border-radius: 50%;
            background: var(--am-text-faint);
          }
          .field-value-boolean.is-true::before {
            background: var(--am-success);
          }
          .field-value-boolean.is-false::before {
            background: var(--am-border-strong);
          }
          @container (max-width: 29.99rem) {
            .field {
              grid-template-columns: 1fr;
              gap: var(--am-space-2xs);
            }
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.fieldDisplay);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const value = formatDisplayValue(props.value, props.format);
        const isBoolean = props.format === "boolean";

        return html`
          <div class="field">
            <dt class="field-label">${str(props.label)}</dt>
            ${isBoolean
              ? html`<dd
                  class="field-value field-value-boolean ${value === "Yes" ? "is-true" : "is-false"}"
                >
                  ${value}
                </dd>`
              : html`<dd class="field-value">${value}</dd>`}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminFieldDisplay);
  }

  // --- FormSection: labeled field grouping ----------------------------------

  function defineFormSection() {
    const tag = TAGS.formSection;
    if (customElements.get(tag)) return;

    // Frozen AshA2ui encoder id conventions (see the v0_9_1 emission):
    // inputs are `form_input_<field>` with value bound to `/form/<field>`,
    // errors are `form_error_<field>` Texts bound to `/errors/<field>`, and
    // searchable relationship selects are `form_select_<field>` composites.
    const ERROR_ID_PREFIX = "form_error_";
    const SELECT_ID_PREFIX = "form_select_";
    const INPUT_KINDS = ["TextField", "CheckBox", "ChoicePicker", "DateTimeInput"];

    class AshAdminFormSection extends A2uiLitElement {
      static styles = [
        shared,
        css`
          :host {
            display: block;
            container-type: inline-size;
          }
          .fs {
            border: none;
            margin: 0;
            padding: 0;
          }
          .fs-title {
            margin: 0 0 var(--am-space-l);
            font-size: var(--am-font-size-m);
            font-weight: var(--am-font-weight-semibold);
            line-height: var(--am-line-height-tight);
          }
          .fs-grid {
            display: grid;
            gap: var(--am-space-l) var(--am-space-xl);
            grid-template-columns: repeat(var(--am-fs-cols, 1), minmax(0, 1fr));
          }
          .fs-cell {
            display: flex;
            flex-direction: column;
            gap: var(--am-space-2xs);
            min-width: 0;
          }
          .fs-extra {
            margin-top: var(--am-space-l);
          }
          @container (max-width: 39.99rem) {
            .fs-grid {
              grid-template-columns: 1fr;
            }
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.formSection);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        const props = this.controller?.props;
        const columns = Math.min(Math.max(Math.round(Number(props?.columns) || 1), 1), 6);
        this.style.setProperty("--am-fs-cols", String(columns));
        applyWeight(this, props);
      }

      childType(ref) {
        try {
          return this.context?.dataContext?.surface?.componentsModel?.get(ref.id)?.type ?? null;
        } catch {
          return null;
        }
      }

      childValuePath(ref) {
        try {
          const path = this.context?.dataContext?.surface?.componentsModel?.get(ref.id)?.properties
            ?.value?.path;
          return typeof path === "string" ? path : null;
        } catch {
          return null;
        }
      }

      /**
       * Pairs the encoder's sibling `form_error_<field>` Texts with their
       * inputs. The a11y-hardened inputs (TextField/CheckBox/ChoicePicker/
       * DateTimeInput overrides) already render + aria-wire `/errors/<field>`
       * themselves — their paired error Texts are dropped so the message is
       * never double-rendered. Error Texts that pair with a searchable-select
       * composite (`form_select_<field>`) render inside that field's cell
       * (true adjacency); anything unpaired renders in a trailing block.
       */
      partitionChildren() {
        const props = this.controller?.props;
        const refs = childRefs(props?.children);

        const errors = [];
        const fields = [];
        for (const ref of refs) {
          if (ref.id.startsWith(ERROR_ID_PREFIX) && this.childType(ref) === "Text") {
            errors.push(ref);
          } else {
            fields.push(ref);
          }
        }

        const attached = new Map(); // field ref id -> error ref
        const trailing = [];
        for (const errorRef of errors) {
          const field = errorRef.id.slice(ERROR_ID_PREFIX.length);

          const ownedByInput = fields.some(
            (ref) =>
              this.childValuePath(ref) === `/form/${field}` &&
              INPUT_KINDS.includes(this.childType(ref)),
          );
          if (ownedByInput) continue; // the input renders this error itself

          const selectRef = fields.find((ref) => ref.id === `${SELECT_ID_PREFIX}${field}`);
          if (selectRef) {
            attached.set(selectRef.id, errorRef);
            continue;
          }

          trailing.push(errorRef);
        }

        return {fields, attached, trailing};
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const {fields, attached, trailing} = this.partitionChildren();

        return html`
          <div class="fs">
            ${props.title ? html`<h3 class="fs-title">${str(props.title)}</h3>` : nothing}
            <div class="fs-grid">
              ${fields.map(
                (ref) => html`
                  <div class="fs-cell">
                    ${this.renderNode(ref)}
                    ${attached.has(ref.id)
                      ? html`${this.renderNode(attached.get(ref.id))}`
                      : nothing}
                  </div>
                `,
              )}
            </div>
            ${trailing.length > 0
              ? html`<div class="fs-extra">
                  ${trailing.map((ref) => html`${this.renderNode(ref)}`)}
                </div>`
              : nothing}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminFormSection);
  }

  // --- ActionBar: action hierarchy -------------------------------------------

  function defineActionBar() {
    const tag = TAGS.actionBar;
    if (customElements.get(tag)) return;

    class AshAdminActionBar extends A2uiLitElement {
      static styles = [
        shared,
        buttons,
        css`
          :host {
            display: block;
          }
          .bar {
            display: flex;
            align-items: center;
            gap: var(--am-space-m);
            flex-wrap: wrap;
            margin-top: var(--am-space-l);
          }
          /* Quiet secondaries: custom properties pierce the basic Button's
           * shadow boundary, so its default chrome softens without touching
           * the basic catalog. */
          .bar-secondary {
            display: flex;
            align-items: center;
            gap: var(--am-space-s);
            flex-wrap: wrap;
            --a2ui-button-border: 1px solid transparent;
            --a2ui-button-background: transparent;
            --a2ui-button-padding: 0.375rem 0.75rem;
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.actionBar);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const label = str(props.primaryLabel ?? "");
        const busy = props.busy === true;
        const destructive = props.destructive === true;
        const children = childRefs(props.children);

        return html`
          <div class="bar" role="group" aria-label="Record actions">
            ${label !== ""
              ? html`
                  <button
                    type="button"
                    class="am-btn ${destructive ? "am-btn-destructive" : "am-btn-primary"}"
                    ?disabled=${busy}
                    aria-busy=${busy ? "true" : "false"}
                    @click=${() => this.submit()}
                  >
                    ${busy ? html`<span class="am-spinner" aria-hidden="true"></span>` : nothing}
                    ${label}
                  </button>
                `
              : nothing}
            ${children.length > 0
              ? html`<div class="bar-secondary">
                  ${children.map((ref) => html`${this.renderNode(ref)}`)}
                </div>`
              : nothing}
          </div>
        `;
      }

      /**
       * Dispatches the existing `submit_form` envelope: the `action`
       * envelope prop the encoder emits (GenericBinder-resolved into a
       * callable, byte-exact) wins; otherwise the frozen context is
       * reconstructed from the data model's shape (matching the basic-v2
       * emission's `submit_button/2`).
       */
      submit() {
        const props = this.controller?.props;
        if (!props) return;

        if (typeof props.action === "function") {
          props.action();
          return;
        }

        const context = this.context;
        const surface = context?.dataContext?.surface;
        if (!surface || !context.componentModel) return;

        const resolved = resolveEventContext(
          {event: {name: "submit_form", context: buildSubmitFormContext(surface)}},
          surface.dataModel,
          "/",
        );
        surface.dispatchAction(resolved, context.componentModel.id);
      }
    }

    customElements.define(tag, AshAdminActionBar);
  }

  // --- StatusBanner: typed feedback ------------------------------------------

  function defineStatusBanner() {
    const tag = TAGS.statusBanner;
    if (customElements.get(tag)) return;

    const glyph = (paths) => html`<svg
      viewBox="0 0 20 20"
      width="16"
      height="16"
      fill="none"
      stroke="currentColor"
      stroke-width="1.75"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      ${paths.map((path) => html`<path d=${path}></path>`)}
    </svg>`;

    const GLYPHS = {
      success: glyph(["M4 10.5l4 4 8-9"]),
      error: glyph(["M10 4v8", "M10 15.5v.01"]),
      warning: glyph(["M10 4.5l6 10.5H4l6-10.5z", "M10 9v3", "M10 13.75v.01"]),
      info: glyph(["M10 9v5", "M10 6.25v.01"]),
    };

    class AshAdminStatusBanner extends A2uiLitElement {
      static styles = [
        shared,
        css`
          :host {
            display: block;
          }
          .banner {
            display: flex;
            align-items: flex-start;
            gap: var(--am-space-s);
            padding: var(--am-space-s) var(--am-space-m);
            border-radius: var(--am-radius-m);
            border: 1px solid transparent;
            font-size: var(--am-font-size-m);
          }
          .banner-glyph {
            flex: none;
            margin-top: 0.125rem;
            display: inline-flex;
          }
          .banner-content {
            min-width: 0;
            overflow-wrap: anywhere;
          }
          .banner-success {
            color: var(--am-success);
            background: var(--am-success-subtle);
            border-color: color-mix(in srgb, var(--am-success) 25%, transparent);
          }
          .banner-error {
            color: var(--am-error);
            background: var(--am-error-subtle);
            border-color: color-mix(in srgb, var(--am-error) 25%, transparent);
          }
          .banner-warning {
            color: var(--am-warning);
            background: var(--am-warning-subtle);
            border-color: color-mix(in srgb, var(--am-warning) 25%, transparent);
          }
          .banner-info {
            color: var(--am-text-muted);
            background: var(--am-hover-tint);
            border-color: var(--am-border);
          }
        `,
      ];

      createController() {
        return new A2uiController(this, adminApis.statusBanner);
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const kind = props.kind === null || props.kind === undefined ? "" : String(props.kind);
        if (!kind) return nothing;

        const tone = ["success", "error", "warning", "info"].includes(kind) ? kind : "info";
        // Typed feedback semantics: errors assert, everything else is polite.
        const role = tone === "error" ? "alert" : "status";

        return html`
          <div class="banner banner-${tone}" role=${role}>
            <span class="banner-glyph">${GLYPHS[tone]}</span>
            <div class="banner-content">${str(props.message)}</div>
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminStatusBanner);
  }

  // --- ConfirmDialog: destructive confirmation -------------------------------

  function defineConfirmDialog() {
    const tag = TAGS.confirmDialog;
    if (customElements.get(tag)) return;

    class AshAdminConfirmDialog extends A2uiLitElement {
      static properties = {
        open: {type: Boolean},
        title: {type: String},
        body: {type: String},
        confirmLabel: {type: String},
        destructive: {type: Boolean},
      };

      constructor() {
        super();
        this.open = false;
        this.title = "";
        this.body = "";
        this.confirmLabel = "Confirm";
        this.destructive = true;
        this._amRestoreFocus = null;
      }

      static styles = [
        shared,
        buttons,
        css`
          :host {
            display: contents;
          }
          .overlay {
            position: fixed;
            inset: 0;
            z-index: 80;
            display: grid;
            place-items: center;
            padding: var(--am-space-l);
            background: rgb(15 23 42 / 0.45);
          }
          .dialog {
            width: min(28rem, 100%);
            background: var(--am-surface);
            color: var(--am-text);
            border: 1px solid var(--am-border);
            border-radius: var(--am-radius-l);
            box-shadow: var(--am-shadow-3);
            padding: var(--am-space-xl);
          }
          .dialog-title {
            margin: 0 0 var(--am-space-s);
            font-size: var(--am-font-size-l);
            font-weight: var(--am-font-weight-semibold);
            line-height: var(--am-line-height-tight);
          }
          .dialog-title:focus {
            outline: none;
          }
          .dialog-title:focus-visible {
            outline: 2px solid var(--am-focus);
            outline-offset: 2px;
          }
          .dialog-body {
            margin: 0 0 var(--am-space-xl);
            color: var(--am-text-muted);
            font-size: var(--am-font-size-m);
          }
          .dialog-actions {
            display: flex;
            justify-content: flex-end;
            gap: var(--am-space-s);
          }
        `,
      ];

      // Normally rendered by the DataGrid renderer (not the component tree),
      // so no controller binding is used. A standalone emission still
      // validates against the catalog schema and renders closed.
      createController() {
        return null;
      }

      updated(changedProperties) {
        super.updated(changedProperties);
        if (!changedProperties.has("open")) return;

        if (this.open) {
          this._amRestoreFocus = document.activeElement;
          const heading = this.renderRoot?.querySelector("[data-dialog-heading]");
          if (heading) heading.focus();
        } else if (changedProperties.get("open") === true && this.isConnected) {
          this.restoreFocus();
        }
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        // The DataGrid removes this element on confirm/cancel — restoring
        // focus to the invoking row button is the closing act.
        if (this.open) this.restoreFocus();
      }

      restoreFocus() {
        if (this._amRestoreFocus && this._amRestoreFocus.isConnected) {
          this._amRestoreFocus.focus();
        }
        this._amRestoreFocus = null;
      }

      confirm() {
        this.dispatchEvent(new CustomEvent("confirm", {bubbles: false}));
      }

      cancel() {
        this.dispatchEvent(new CustomEvent("cancel", {bubbles: false}));
      }

      onKeydown(event) {
        if (event.key === "Escape") {
          event.preventDefault();
          this.cancel();
          return;
        }
        if (event.key === "Tab") {
          // Focus trap: cycle within the dialog while it is open.
          const focusables = [
            ...this.renderRoot.querySelectorAll(
              'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])',
            ),
          ].filter((element) => !element.hasAttribute("disabled"));
          if (focusables.length === 0) return;
          const first = focusables[0];
          const last = focusables[focusables.length - 1];
          if (event.shiftKey && document.activeElement === first) {
            event.preventDefault();
            last.focus();
          } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault();
            first.focus();
          }
        }
      }

      render() {
        if (!this.open) return nothing;

        return html`
          <div
            class="overlay"
            @keydown=${(event) => this.onKeydown(event)}
            @pointerdown=${(event) => {
              // Clicking the backdrop cancels; clicks inside the dialog do not.
              if (event.target === event.currentTarget) this.cancel();
            }}
          >
            <div
              class="dialog"
              role="dialog"
              aria-modal="true"
              aria-labelledby="am-dialog-title"
              aria-describedby="am-dialog-body"
            >
              <h2 class="dialog-title" id="am-dialog-title" tabindex="-1" data-dialog-heading>
                ${str(this.title)}
              </h2>
              ${this.body
                ? html`<p class="dialog-body" id="am-dialog-body">${str(this.body)}</p>`
                : nothing}
              <div class="dialog-actions">
                <button type="button" class="am-btn" @click=${() => this.cancel()}>Cancel</button>
                <button
                  type="button"
                  class="am-btn ${this.destructive ? "am-btn-destructive" : "am-btn-primary"}"
                  @click=${() => this.confirm()}
                >
                  ${str(this.confirmLabel) || "Confirm"}
                </button>
              </div>
            </div>
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminConfirmDialog);
  }

  // --- A11y-hardened basic inputs --------------------------------------------

  function defineTextField() {
    const tag = INPUT_OVERRIDE_TAGS.TextField;
    if (customElements.get(tag)) return;

    class AshAdminTextField extends A2uiLitElement {
      static styles = [shared, inputBaseStyles];

      createController() {
        return new A2uiController(this, basicInputApi("TextField"));
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
        syncFieldError(this);
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        teardownFieldError(this);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const inputId = `${this.context?.componentModel?.id || "textfield"}-input`;
        const errorId = `${inputId}-error`;
        const errors = fieldErrors(props, this._amErrText);
        const invalid = errors.length > 0;

        let type = "text";
        if (props.variant === "number") type = "number";
        if (props.variant === "obscured") type = "password";

        return html`
          <div class="field">
            ${props.label
              ? html`<label class="field-label" for=${inputId}>${props.label}</label>`
              : nothing}
            ${props.variant === "longText"
              ? html`<textarea
                  id=${inputId}
                  class="control"
                  .value=${props.value ?? ""}
                  aria-invalid=${invalid ? "true" : "false"}
                  aria-describedby=${invalid ? errorId : ""}
                  @input=${(event) => props.setValue?.(event.target.value)}
                ></textarea>`
              : html`<input
                  id=${inputId}
                  class="control"
                  type=${type}
                  .value=${props.value ?? ""}
                  aria-invalid=${invalid ? "true" : "false"}
                  aria-describedby=${invalid ? errorId : ""}
                  @input=${(event) => props.setValue?.(event.target.value)}
                />`}
            ${invalid ? html`<div class="error" id=${errorId}>${errors[0]}</div>` : nothing}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminTextField);
  }

  function defineCheckBox() {
    const tag = INPUT_OVERRIDE_TAGS.CheckBox;
    if (customElements.get(tag)) return;

    class AshAdminCheckBox extends A2uiLitElement {
      static styles = [shared, inputBaseStyles];

      createController() {
        return new A2uiController(this, basicInputApi("CheckBox"));
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
        syncFieldError(this);
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        teardownFieldError(this);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const inputId = `${this.context?.componentModel?.id || "checkbox"}-input`;
        const errorId = `${inputId}-error`;
        const errors = fieldErrors(props, this._amErrText);
        const invalid = errors.length > 0;

        return html`
          <div class="field">
            <label class="choice" for=${inputId}>
              <input
                id=${inputId}
                type="checkbox"
                .checked=${props.value === true}
                aria-invalid=${invalid ? "true" : "false"}
                aria-describedby=${invalid ? errorId : ""}
                @change=${(event) => props.setValue?.(event.target.checked)}
              />
              ${props.label}
            </label>
            ${invalid ? html`<div class="error" id=${errorId}>${errors[0]}</div>` : nothing}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminCheckBox);
  }

  function defineChoicePicker() {
    const tag = INPUT_OVERRIDE_TAGS.ChoicePicker;
    if (customElements.get(tag)) return;

    class AshAdminChoicePicker extends A2uiLitElement {
      static styles = [
        shared,
        inputBaseStyles,
        css`
          select.control {
            appearance: none;
            background-image: linear-gradient(45deg, transparent 50%, var(--am-text-muted) 50%),
              linear-gradient(135deg, var(--am-text-muted) 50%, transparent 50%);
            background-position:
              calc(100% - 1.15rem) calc(50% + 0.1rem),
              calc(100% - 0.8rem) calc(50% + 0.1rem);
            background-size:
              0.35rem 0.35rem,
              0.35rem 0.35rem;
            background-repeat: no-repeat;
            padding-right: var(--am-space-xl);
          }
        `,
      ];

      createController() {
        return new A2uiController(this, basicInputApi("ChoicePicker"));
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
        syncFieldError(this);
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        teardownFieldError(this);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        // The A2UI schema types ChoicePicker value as a string list, but a
        // server data-model refresh can echo a scalar back into the binding
        // (e.g. AshA2ui's /query/filters/<name>); accept both.
        const raw = props.value;
        const selected = Array.isArray(raw) ? raw : raw == null ? [] : [String(raw)];
        const options = Array.isArray(props.options) ? props.options : [];
        const baseId = this.context?.componentModel?.id || "choice";
        const errorId = `${baseId}-error`;
        const errors = fieldErrors(props, this._amErrText);

        return props.variant === "multipleSelection"
          ? this.renderCheckboxes(props, options, selected, baseId, errors)
          : this.renderSelect(props, options, selected, baseId, errors);
      }

      renderSelect(props, options, selected, baseId, errors) {
        const inputId = `${baseId}-input`;
        const invalid = errors.length > 0;

        // An unset binding on a picker that offers an empty-valued option
        // (AshA2ui's "All" filter/preset option) means "all" — show that
        // option rather than a placeholder.
        let current = selected.length > 0 ? selected[0] : undefined;
        if (current === undefined && options.some((option) => option.value === "")) {
          current = "";
        }
        const hasMatch = options.some((option) => option.value === current);

        return html`
          <div class="field">
            ${props.label
              ? html`<label class="field-label" for=${inputId}>${props.label}</label>`
              : nothing}
            <select
              id=${inputId}
              class="control"
              aria-invalid=${invalid ? "true" : "false"}
              aria-describedby=${invalid ? `${baseId}-error` : ""}
              @change=${(event) => props.setValue && props.setValue([event.target.value])}
            >
              ${hasMatch
                ? nothing
                : html`<option value="" disabled selected hidden>Select…</option>`}
              ${options.map(
                (option) => html`
                  <option value=${option.value} ?selected=${option.value === current}>
                    ${option.label}
                  </option>
                `,
              )}
            </select>
            ${invalid
              ? html`<div class="error" id=${`${baseId}-error`}>${errors[0]}</div>`
              : nothing}
          </div>
        `;
      }

      renderCheckboxes(props, options, selected, baseId, errors) {
        const errorId = `${baseId}-error`;
        const toggle = (value) => {
          if (!props.setValue) return;
          if (selected.includes(value)) {
            props.setValue(selected.filter((item) => item !== value));
          } else {
            props.setValue([...selected, value]);
          }
        };

        return html`
          <div class="field">
            <fieldset class="choices" aria-describedby=${errors.length ? errorId : ""}>
              ${props.label ? html`<legend class="choices-legend">${props.label}</legend>` : nothing}
              ${options.map((option, index) => {
                const optionId = `${baseId}-opt-${index}`;
                return html`
                  <label class="choice" for=${optionId}>
                    <input
                      id=${optionId}
                      type="checkbox"
                      .checked=${selected.includes(option.value)}
                      @change=${() => toggle(option.value)}
                    />
                    ${option.label}
                  </label>
                `;
              })}
            </fieldset>
            ${errors.length > 0 ? html`<div class="error" id=${errorId}>${errors[0]}</div>` : nothing}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminChoicePicker);
  }

  function defineDateTimeInput() {
    const tag = INPUT_OVERRIDE_TAGS.DateTimeInput;
    if (customElements.get(tag)) return;

    // HTML5 date/time inputs reject timezone indicators and sub-minute
    // precision in .value; strip both without shifting the wall clock.
    const normalizeDateTimeValue = (value, type) => {
      if (!value) return "";
      const hasTime = value.includes("T");
      const split = value.split("T");
      const datePart = (hasTime ? split[0] : value).substring(0, 10) || "";
      const timePart = (hasTime ? split[1] : value).substring(0, 5) || "";
      if (type === "date") return datePart;
      if (type === "time") return timePart;
      if (type === "datetime-local") return datePart && timePart ? `${datePart}T${timePart}` : "";
      return "";
    };

    class AshAdminDateTimeInput extends A2uiLitElement {
      static styles = [shared, inputBaseStyles];

      createController() {
        return new A2uiController(this, basicInputApi("DateTimeInput"));
      }

      willUpdate(changedProperties) {
        super.willUpdate(changedProperties);
        applyWeight(this, this.controller?.props);
        syncFieldError(this);
      }

      disconnectedCallback() {
        super.disconnectedCallback();
        teardownFieldError(this);
      }

      render() {
        const props = this.controller?.props;
        if (!props) return nothing;

        const inputId = `${this.context?.componentModel?.id || "datetime"}-input`;
        const errorId = `${inputId}-error`;
        const errors = fieldErrors(props, this._amErrText);
        const invalid = errors.length > 0;

        // Mirrors the upstream control: date and/or time via the native
        // input types, ISO-string round-trip.
        const type =
          props.enableDate && props.enableTime
            ? "datetime-local"
            : props.enableDate
              ? "date"
              : "time";
        const value = normalizeDateTimeValue(props.value, type);

        return html`
          <div class="field">
            ${props.label
              ? html`<label class="field-label" for=${inputId}>${props.label}</label>`
              : nothing}
            <input
              id=${inputId}
              class="control"
              type=${type}
              .value=${value}
              aria-invalid=${invalid ? "true" : "false"}
              aria-describedby=${invalid ? errorId : ""}
              @input=${(event) => props.setValue?.(event.target.value)}
            />
            ${invalid ? html`<div class="error" id=${errorId}>${errors[0]}</div>` : nothing}
          </div>
        `;
      }
    }

    customElements.define(tag, AshAdminDateTimeInput);
  }
}

export default createAshAdminCatalog;
