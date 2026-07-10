/**
 * AshA2ui LiveView JS hook.
 *
 * Hosts an `<a2ui-surface>` element (from a renderer such as `@a2ui/lit`)
 * inside the LiveView container, feeds it the A2UI server->client messages
 * pushed by `AshA2ui.LiveRenderer` via `push_event`, and forwards the
 * renderer's client `action` envelopes back to the server as the
 * "a2ui:action" LiveView event.
 *
 * TODO Track 4: implement mounted()/destroyed(), message feed wiring, and
 * action event forwarding.
 */
export const AshA2ui = {
  mounted() {
    // TODO Track 4
  },

  destroyed() {
    // TODO Track 4
  },
};

export default AshA2ui;
