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
 * @param {{MessageProcessor: Function, catalogs: Array<object>}} deps
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

  return {MessageProcessor: deps.MessageProcessor, catalogs: deps.catalogs || []};
}

export const AshA2ui = {
  mounted() {
    const {MessageProcessor, catalogs} = resolveDeps();

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
