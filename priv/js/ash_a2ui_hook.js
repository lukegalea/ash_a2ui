/**
 * AshA2ui LiveView JS hook.
 *
 * Hosts an `<a2ui-surface>` element (from `@a2ui/lit`) inside the LiveView
 * container, feeds it the A2UI server->client messages pushed by
 * `AshA2ui.LiveRenderer` as the "a2ui:messages" event, and forwards the
 * renderer's client `action` payloads back to the server as the
 * "a2ui:action" LiveView event (wrapped in the A2UI v0.9.1 client envelope).
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
 *     renders a native `<select>` for single-choice pickers.
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
 * }} deps
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
  };
}

export const AshA2ui = {
  mounted() {
    const {MessageProcessor, catalogs, markdown} = resolveDeps();

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

  /** Feeds pushed server->client messages into the renderer. */
  processMessages(messages) {
    if (!this.processor) return;

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
   * Wraps a renderer action (A2uiClientAction or a DOM event detail) in the
   * A2UI v0.9.1 client->server envelope and pushes it to the LiveView.
   */
  forwardAction(action) {
    if (!action || !action.name) return;

    const envelope = {
      version: "v0.9.1",
      action: {
        name: action.name,
        surfaceId: action.surfaceId,
        sourceComponentId: action.sourceComponentId,
        timestamp: action.timestamp || new Date().toISOString(),
        context: action.context || {},
      },
    };

    this.pushEvent("a2ui:action", envelope);
  },
};

export default AshA2ui;
