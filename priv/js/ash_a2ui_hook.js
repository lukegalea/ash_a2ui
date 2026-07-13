/**
 * AshA2ui LiveView JS hook.
 *
 * Hosts an `<a2ui-surface>` element (from `@a2ui/lit`) inside the LiveView
 * container, feeds it the A2UI server->client messages pushed by
 * `AshA2ui.LiveRenderer` as the "a2ui:messages" event, and forwards the
 * renderer's client `action` payloads back to the server as the
 * "a2ui:action" LiveView event (wrapped in the A2UI client envelope of the
 * surface's protocol version).
 *
 * ## A2UI v1.0 support
 *
 * No published `@a2ui/lit` / `@a2ui/web_core` release ships a v1.0 runtime
 * (0.10.x exposes only v0_8/v0_9 entry points; the v1_0 directory carries
 * schemas alone) — so this hook is the v1.0-capable client layer on top of
 * the v0_9 renderer. Per-message (`message.version === "v1.0"`) it:
 *
 *   - **expands inline `createSurface`** (v1.0's single-message bootstrap
 *     carrying `components` + `dataModel`) into the v0.9 triple the
 *     renderer understands, mapping the v1.0 basic-catalog id onto a
 *     registered catalog and carrying `surfaceProperties` through as the
 *     surface theme metadata;
 *   - **generates the `actionResponse` handshake**: outgoing actions from a
 *     v1.0 surface carry a unique `actionId` + `wantResponse: true` in a
 *     v1.0 envelope, and — the UX point — the hook optimistically writes
 *     `{status: "pending", ...}` to the surface's reserved `/ui/response`
 *     path the moment the action fires, so bound status components show
 *     feedback at 0 RTT. The server's `actionResponse` (echoing the
 *     `actionId`) resolves the pending entry; a watchdog timeout writes a
 *     timeout error into `/ui/response` if no response ever arrives. Every
 *     response also dispatches a bubbling `"ash-a2ui:action-response"`
 *     CustomEvent on the container for host-level integration.
 *   - **executes `callFunction`** server->client calls against the
 *     host-registered function table (`configureAshA2ui({functions})`;
 *     `openUrl` and `downloadFile` ship as built-ins) and pushes the `functionResponse`
 *     back as the "a2ui:function_response" LiveView event when
 *     `wantResponse` is set.
 *
 * v0.9.1 surfaces are untouched: their messages pass straight through and
 * their actions keep the v0.9.1 envelope.
 *
 * ## Contract with the host bundle
 *
 * This file ships without dependencies — importing `@a2ui/lit` /
 * `@a2ui/web_core` is left to the host app bundle, which must:
 *
 *   1. Import `@a2ui/lit/v0_9` so the `<a2ui-surface>` custom element is
 *      registered (the import has that side effect).
 *   2. Hand the renderer classes to this hook before `LiveSocket` mounts it:
 *
 *          import {MessageProcessor} from "@a2ui/web_core/v0_9";
 *          import {basicCatalog} from "@a2ui/lit/v0_9";
 *          import {AshA2ui, configureAshA2ui} from "ash_a2ui/priv/js/ash_a2ui_hook.js";
 *
 *          configureAshA2ui({MessageProcessor, catalogs: [basicCatalog]});
 *          const liveSocket = new LiveSocket("/live", Socket, {hooks: {AshA2ui}});
 *
 * Optional extras shipped alongside this hook (see the Theming topic):
 *
 *   - `ash_a2ui_theme.css` — a neutral `--a2ui-*` CSS-variable theme for
 *     the basic catalog; import it into your app CSS and override tokens.
 *   - `ash_a2ui_catalog.js` — `createAshA2uiCatalog(deps)` builds a merged
 *     catalog (registered under the basic catalog id) whose ChoicePicker
 *     renders a native `<select>` for single-choice pickers and whose
 *     Column upgrades AshA2ui search-picker composites to a typeahead
 *     combobox (pass `ColumnApi` in the deps to enable).
 *   - `configureAshA2ui({..., markdown})` — wires a markdown renderer so
 *     Text headings render as headings instead of literal `##` markdown
 *     (see the configureAshA2ui docs below).
 *
 * Verified against @a2ui/lit / @a2ui/web_core 0.10.x sources
 * (https://github.com/a2ui-project/a2ui, renderers/web_core + renderers/lit,
 * v0_9 entry points):
 *
 *   - Message ingest is `new MessageProcessor(catalogs, actionHandler)` +
 *     `processor.processMessages(messages)` — NOT a method on the
 *     `<a2ui-surface>` element. The element only takes a `SurfaceModel` via
 *     its `surface` property, delivered through
 *     `processor.onSurfaceCreated(cb)`.
 *   - User actions are delivered to the `actionHandler` callback passed to
 *     the `MessageProcessor` constructor (an `A2uiClientAction` with `name`,
 *     `surfaceId`, `sourceComponentId`, `context`) — in v0.9 there is no
 *     public action DOM event on the surface element.
 *
 * FIXME(@a2ui/lit API, verify in POC): the `a2uiaction` DOM listener below is
 * a defensive fallback from the v0.8-era API kept in case a renderer build
 * dispatches DOM events instead of (or in addition to) calling the
 * MessageProcessor action handler; if both fire we would double-push. Docs:
 * https://www.npmjs.com/package/@a2ui/lit and
 * https://a2ui.org/guides/client-setup/.
 *
 * v0 limitation: a single surface per hook — the last surface created by the
 * processor wins the `<a2ui-surface>` element.
 */

let hookDeps = null;

/**
 * Registers the renderer classes the hook needs. Call once from the host
 * bundle before the LiveSocket mounts any AshA2ui hook.
 *
 * `markdown` is optional but strongly recommended: without a markdown
 * renderer the basic catalog's Text component prints headings as literal
 * markdown (`## Title`) — an upstream design decision, see
 * https://github.com/google/A2UI/issues/1226. Pass the three pieces and
 * the hook wires them up with a Lit context provider on the hook element:
 *
 *     import {ContextProvider} from "@lit/context";
 *     import {Context} from "@a2ui/lit/v0_9";
 *     import {renderMarkdown} from "@a2ui/markdown-it";
 *
 *     configureAshA2ui({
 *       MessageProcessor,
 *       catalogs: [catalog],
 *       markdown: {ContextProvider, context: Context.markdown, render: renderMarkdown},
 *     });
 *
 * (`ContextProvider` attaches its `context-request` listeners directly to
 * the host element, so a plain hook container works as the provider host —
 * verified against @lit/context 1.x `context-provider.js`.)
 *
 * @param {{
 *   MessageProcessor: Function,
 *   catalogs: Array<object>,
 *   markdown?: {ContextProvider: Function, context: object, render: Function},
 *   functions?: Object<string, Function>,
 *   pendingMessage?: string,
 *   actionTimeoutMs?: number,
 * }} deps
 *   `functions` — client-side functions the server may invoke via v1.0
 *   `callFunction` messages, keyed by name (`(args) => value | Promise`);
 *   merged over the built-in `openUrl` / `downloadFile`. `pendingMessage` — the optimistic
 *   `/ui/response` message shown while a v1.0 action is in flight (default
 *   "Working…"). `actionTimeoutMs` — v1.0 actionResponse watchdog (default
 *   10000; 0 disables).
 */
export function configureAshA2ui(deps) {
  hookDeps = deps;
}

function resolveDeps() {
  // Fallback for host bundles that prefer a global over calling
  // configureAshA2ui (e.g. when the hook is bundled separately).
  const deps = hookDeps || globalThis.__ASH_A2UI_DEPS__;

  if (!deps || typeof deps.MessageProcessor !== "function") {
    throw new Error(
      "AshA2ui hook: missing @a2ui renderer classes. Call " +
        "configureAshA2ui({MessageProcessor, catalogs}) from your app bundle " +
        "(or set globalThis.__ASH_A2UI_DEPS__) before mounting the LiveSocket.",
    );
  }

  return {
    MessageProcessor: deps.MessageProcessor,
    catalogs: deps.catalogs || [],
    markdown: deps.markdown || null,
    functions: {...BUILTIN_FUNCTIONS, ...(deps.functions || {})},
    pendingMessage: deps.pendingMessage || "Working…",
    actionTimeoutMs: deps.actionTimeoutMs === undefined ? 10000 : deps.actionTimeoutMs,
  };
}

const V1_VERSION = "v1.0";
const V1_BASIC_CATALOG_ID = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json";
const V0_BASIC_CATALOG_ID = "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json";

const BUILTIN_FUNCTIONS = {
  openUrl: (args) => {
    if (args && typeof args.url === "string") window.open(args.url, "_blank", "noopener");
    return null;
  },
  // The frozen server-generated file-export contract (see AshA2ui.Export):
  // `dataUrl` (a data: URL — how AshA2ui delivers CSV exports) or `url`
  // (a signed download URL, for hosts that upload instead of inlining),
  // downloaded under `filename` via a transient anchor click.
  downloadFile: (args) => {
    const href = args && (typeof args.dataUrl === "string" ? args.dataUrl : args.url);
    if (typeof href !== "string") return null;
    const anchor = document.createElement("a");
    anchor.href = href;
    anchor.download = (args && args.filename) || "download";
    anchor.rel = "noopener";
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    return null;
  },
};

function randomActionId() {
  if (globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") {
    return globalThis.crypto.randomUUID();
  }
  return `a2ui-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

export const AshA2ui = {
  mounted() {
    const deps = resolveDeps();
    const {MessageProcessor, catalogs, markdown} = deps;
    this.deps = deps;

    // v1.0 state: which surfaces speak v1.0, and the in-flight
    // actionId -> {surfaceId, timer} entries awaiting an actionResponse.
    this.v1Surfaces = new Set();
    this.pendingActions = new Map();

    // Provide the markdown renderer to Text components (which consume the
    // `Context.markdown` Lit context) from the hook container, an ancestor
    // of every rendered component. The renderer contract is
    // `(value, options) => Promise<string>`; wrap sync renderers so both
    // shapes work.
    if (markdown && markdown.ContextProvider && markdown.context && markdown.render) {
      this.markdownProvider = new markdown.ContextProvider(this.el, {
        context: markdown.context,
        initialValue: (value, options) => Promise.resolve(markdown.render(value, options)),
      });
    }

    this.surfaceEl = document.createElement("a2ui-surface");
    this.el.appendChild(this.surfaceEl);

    this.processor = new MessageProcessor(catalogs, (action) => {
      this.forwardAction(action);
    });

    // The surface element renders a SurfaceModel; hand it the model as soon
    // as the processor creates it (single-surface v0 semantics).
    if (typeof this.processor.onSurfaceCreated === "function") {
      this.surfaceSubscription = this.processor.onSurfaceCreated((surface) => {
        this.surfaceEl.surface = surface;
      });
    }

    this.handleEvent("a2ui:messages", ({messages}) => {
      this.processMessages(messages || []);
    });

    // Defensive fallback: see FIXME in the header comment.
    this.onDomAction = (event) => this.forwardAction(event.detail);
    this.el.addEventListener("a2uiaction", this.onDomAction);
  },

  destroyed() {
    for (const pending of this.pendingActions.values()) {
      if (pending.timer) clearTimeout(pending.timer);
    }
    this.pendingActions.clear();

    if (this.surfaceSubscription && typeof this.surfaceSubscription.unsubscribe === "function") {
      this.surfaceSubscription.unsubscribe();
    }

    if (this.onDomAction) {
      this.el.removeEventListener("a2uiaction", this.onDomAction);
    }

    if (this.surfaceEl && this.surfaceEl.parentNode) {
      this.surfaceEl.parentNode.removeChild(this.surfaceEl);
    }

    this.processor = null;
    this.surfaceEl = null;
    // The ContextProvider's listeners are attached to this.el, which the
    // LiveView is discarding — dropping the reference is enough.
    this.markdownProvider = null;
  },

  /**
   * Feeds pushed server->client messages into the renderer, adapting v1.0
   * messages for the v0_9 MessageProcessor (see "A2UI v1.0 support" above).
   */
  processMessages(messages) {
    if (!this.processor) return;

    const adapted = [];
    for (const message of messages) {
      adapted.push(...this.adaptMessage(message));
    }

    this.feedProcessor(adapted);
  },

  feedProcessor(messages) {
    if (messages.length === 0) return;

    if (typeof this.processor.processMessages === "function") {
      this.processor.processMessages(messages);
    } else if (typeof this.processor.processMessage === "function") {
      // Defensive: older/newer builds may only expose the singular API.
      for (const message of messages) {
        this.processor.processMessage(message);
      }
    } else {
      console.error("AshA2ui hook: MessageProcessor has no processMessages/processMessage API");
    }
  },

  /**
   * Maps one server->client message to the list of messages handed to the
   * v0_9 renderer. v0.9.1 messages pass through untouched; v1.0 messages
   * are expanded/consumed per the header comment.
   */
  adaptMessage(message) {
    if (!message || message.version !== V1_VERSION) return [message];

    if (message.createSurface) return this.adaptV1CreateSurface(message.createSurface);

    if (message.actionResponse) {
      this.resolveActionResponse(message);
      return [];
    }

    if (message.callFunction) {
      this.executeFunctionCall(message);
      return [];
    }

    if (message.deleteSurface && message.deleteSurface.surfaceId) {
      this.v1Surfaces.delete(message.deleteSurface.surfaceId);
    }

    // updateComponents / updateDataModel / deleteSurface payloads are
    // shape-compatible with v0.9; the processor does not inspect `version`.
    return [message];
  },

  /**
   * Expands v1.0's inline createSurface (surface + components + dataModel
   * in one message) into the v0.9 triple the published renderer
   * understands, mapping the v1.0 basic-catalog id onto a registered
   * catalog and passing surfaceProperties through as the surface's theme
   * metadata slot.
   */
  adaptV1CreateSurface(payload) {
    const {surfaceId, catalogId, surfaceProperties, sendDataModel, components, dataModel} = payload;

    this.v1Surfaces.add(surfaceId);

    const registered = (this.deps.catalogs || []).some((catalog) => catalog.id === catalogId);
    const mappedCatalogId =
      !registered && catalogId === V1_BASIC_CATALOG_ID ? V0_BASIC_CATALOG_ID : catalogId;

    const create = {surfaceId, catalogId: mappedCatalogId};
    if (surfaceProperties) create.theme = surfaceProperties;
    if (sendDataModel !== undefined) create.sendDataModel = sendDataModel;

    const expanded = [{createSurface: create}];

    if (components && components.length > 0) {
      expanded.push({updateComponents: {surfaceId, components}});
    }

    if (dataModel !== undefined) {
      expanded.push({updateDataModel: {surfaceId, path: "/", value: dataModel}});
    }

    return expanded;
  },

  /**
   * Resolves a server actionResponse: clears the pending entry (and its
   * watchdog), settles the optimistic /ui/response pending state with the
   * response itself, and re-dispatches the response as a bubbling DOM event
   * so host code can react per action.
   */
  resolveActionResponse(message) {
    const pending = this.pendingActions.get(message.actionId);

    if (pending) {
      if (pending.timer) clearTimeout(pending.timer);
      this.pendingActions.delete(message.actionId);

      // Settle the optimistic pending write with the response payload so
      // "Working…" never outlives its action. The actionResponse is the
      // FIRST message of the server's reply batch, so a server /ui/response
      // write in the same batch (e.g. an invoke result) lands after this
      // and wins — this is only the floor.
      const response = message.actionResponse || {};
      const settled = response.error
        ? {
            status: "error",
            code: response.error.code || "",
            message: response.error.message || "",
            result: {},
            resultText: "",
          }
        : {
            status: "ok",
            message: "",
            result: {},
            resultText: "",
            ...(response.value || {}),
          };

      this.writeUiResponse(pending.surfaceId, settled);
    }

    this.el.dispatchEvent(
      new CustomEvent("ash-a2ui:action-response", {
        bubbles: true,
        detail: {
          actionId: message.actionId,
          surfaceId: pending ? pending.surfaceId : undefined,
          response: message.actionResponse,
        },
      }),
    );
  },

  /**
   * Executes a v1.0 server->client callFunction against the registered
   * function table and, when `wantResponse` is set, pushes the
   * functionResponse (or error) back as the "a2ui:function_response"
   * LiveView event.
   */
  executeFunctionCall(message) {
    const {functionCallId, wantResponse, callFunction} = message;
    const name = callFunction && callFunction.call;
    const fn = this.deps.functions[name];

    const reply = (payload) => {
      if (wantResponse) this.pushEvent("a2ui:function_response", payload);
    };

    if (typeof fn !== "function") {
      console.warn(`AshA2ui hook: no client function registered for callFunction "${name}"`);
      reply({
        version: V1_VERSION,
        error: {code: "UNSUPPORTED_FUNCTION", message: `Unknown function: ${name}`, functionCallId},
      });
      return;
    }

    Promise.resolve()
      .then(() => fn(callFunction.args || {}))
      .then((value) =>
        reply({
          version: V1_VERSION,
          functionResponse: {functionCallId, call: name, value: value === undefined ? null : value},
        }),
      )
      .catch((error) =>
        reply({
          version: V1_VERSION,
          error: {code: "FUNCTION_FAILED", message: String(error), functionCallId},
        }),
      );
  },

  /**
   * Writes the surface's reserved /ui/response object locally (through the
   * renderer's own data model) — the 0-RTT pending/timeout feedback path.
   */
  writeUiResponse(surfaceId, value) {
    this.feedProcessor([
      {updateDataModel: {surfaceId, path: "/ui/response", value}},
    ]);
  },

  /**
   * Wraps a renderer action (A2uiClientAction or a DOM event detail) in the
   * A2UI client->server envelope of the surface's protocol version and
   * pushes it to the LiveView.
   *
   * For v1.0 surfaces the action carries a generated `actionId` +
   * `wantResponse: true`, an optimistic `{status: "pending"}` is written to
   * `/ui/response` (instant feedback on the bound status components), and a
   * watchdog turns a never-answered action into a visible timeout error.
   */
  forwardAction(action) {
    if (!action || !action.name) return;

    const inner = {
      name: action.name,
      surfaceId: action.surfaceId,
      sourceComponentId: action.sourceComponentId,
      timestamp: action.timestamp || new Date().toISOString(),
      context: action.context || {},
    };

    if (!this.v1Surfaces.has(action.surfaceId)) {
      this.pushEvent("a2ui:action", {version: "v0.9.1", action: inner});
      return;
    }

    const actionId = randomActionId();
    inner.actionId = actionId;
    inner.wantResponse = true;

    let timer = null;
    if (this.deps.actionTimeoutMs > 0) {
      timer = setTimeout(() => {
        if (!this.pendingActions.has(actionId)) return;
        this.pendingActions.delete(actionId);
        this.writeUiResponse(action.surfaceId, {
          status: "error",
          code: "TIMEOUT",
          message: "The server did not respond in time. Please try again.",
          result: {},
          resultText: "",
        });
      }, this.deps.actionTimeoutMs);
    }

    this.pendingActions.set(actionId, {surfaceId: action.surfaceId, timer});

    this.writeUiResponse(action.surfaceId, {
      status: "pending",
      message: this.deps.pendingMessage,
      result: {},
      resultText: "",
    });

    this.pushEvent("a2ui:action", {version: V1_VERSION, action: inner});
  },
};

export default AshA2ui;
