/**
 * AshA2ui merged component catalog for the `@a2ui/lit` renderer.
 *
 * The A2UI basic catalog's ChoicePicker renders every single-choice picker
 * as a radio-button list (its only `displayStyle`s are `checkbox` and
 * `chips` — there is no dropdown, through spec v1.0). For admin-style
 * surfaces with filter/preset/enum pickers that is the wrong control, and
 * no amount of CSS-variable theming can fix it because it is structural.
 *
 * `createAshA2uiCatalog(deps)` builds a Catalog registered under the SAME
 * catalog id the AshA2ui encoder emits (the basic catalog id), reusing
 * every basic-catalog component and function except ChoicePicker, which is
 * replaced by `<ash-a2ui-choicepicker>`:
 *
 *   - `variant: "mutuallyExclusive"` (the default) renders a native
 *     `<select>` — themed via the same `--a2ui-*` variables as the rest of
 *     the catalog, plus `--a2ui-choicepicker-select-*` overrides.
 *   - `variant: "multipleSelection"` falls back to a checkbox list
 *     (matching the basic catalog's behavior).
 *   - `filterable` is ignored for single-choice pickers: native selects
 *     already support keyboard search, and AshA2ui's searchable
 *     relationship selects use a server-mediated TextField + List
 *     composite, not ChoicePicker.
 *
 * ## Contract with the host bundle
 *
 * Like the hook, this file ships with **no bundled dependencies** (the
 * host bundle owns the single `lit` / `@a2ui` instance; NODE_PATH-based
 * resolution from inside `deps/` would not find them anyway). The host
 * passes the classes in:
 *
 *     import {html, css, nothing} from "lit";
 *     import {basicCatalog, A2uiLitElement, A2uiController} from "@a2ui/lit/v0_9";
 *     import {Catalog} from "@a2ui/web_core/v0_9";
 *     import {ChoicePickerApi} from "@a2ui/web_core/v0_9/basic_catalog";
 *     import {createAshA2uiCatalog} from "../../deps/ash_a2ui/priv/js/ash_a2ui_catalog.js";
 *
 *     const catalog = createAshA2uiCatalog({
 *       Catalog,
 *       basicCatalog,
 *       ChoicePickerApi,
 *       A2uiLitElement,
 *       A2uiController,
 *       lit: {html, css, nothing},
 *     });
 *     configureAshA2ui({MessageProcessor, catalogs: [catalog]});
 *
 * Verified against @a2ui/lit 0.10.1 / @a2ui/web_core 0.10.4:
 * `new Catalog(id, components, functions, themeSchema)` takes
 * `{...ComponentApi, tagName}` entries; the renderer resolves
 * `createSurface.catalogId` by exact string match and renders each
 * component type via `catalog.components.get(type).tagName`.
 */

const TAG_NAME = "ash-a2ui-choicepicker";

/**
 * Builds the merged catalog. See the module docs for the `deps` contract.
 *
 * @returns {object} a `@a2ui/web_core` Catalog registered under the basic
 *   catalog's id, with ChoicePicker replaced.
 */
export function createAshA2uiCatalog(deps) {
  const {Catalog, basicCatalog, ChoicePickerApi, A2uiLitElement, A2uiController, lit} = deps;

  if (
    !Catalog ||
    !basicCatalog ||
    !ChoicePickerApi ||
    !A2uiLitElement ||
    !A2uiController ||
    !lit
  ) {
    throw new Error(
      "createAshA2uiCatalog: missing deps. Pass {Catalog, basicCatalog, " +
        "ChoicePickerApi, A2uiLitElement, A2uiController, lit: {html, css, nothing}}.",
    );
  }

  defineChoicePickerElement(deps);

  const choicePicker = {...ChoicePickerApi, tagName: TAG_NAME};

  const components = [...basicCatalog.components.values()].map((component) =>
    component.name === "ChoicePicker" ? choicePicker : component,
  );

  return new Catalog(
    basicCatalog.id,
    components,
    [...basicCatalog.functions.values()],
    basicCatalog.themeSchema,
  );
}

// Defines <ash-a2ui-choicepicker> once (idempotent across LiveView
// remounts and hot reloads). Written without decorators so the file stays
// plain JS with injected dependencies.
function defineChoicePickerElement({A2uiLitElement, A2uiController, ChoicePickerApi, lit}) {
  if (customElements.get(TAG_NAME)) return;

  const {html, css, nothing} = lit;

  class AshA2uiChoicePickerElement extends A2uiLitElement {
    /**
     * Styling knobs (all optional, themed by the same tokens as the rest
     * of the basic catalog):
     *
     * - `--a2ui-color-input` / `--a2ui-color-on-input`: select colors.
     * - `--a2ui-textfield-border`: select border (shared with TextField).
     * - `--a2ui-choicepicker-select-border-radius`: select corner radius.
     * - `--a2ui-choicepicker-select-padding`: select padding.
     * - `--a2ui-choicepicker-label-*`, `--a2ui-choicepicker-gap`: as in
     *   the basic catalog's ChoicePicker.
     */
    static styles = css`
      :host {
        display: flex;
        flex-direction: column;
        gap: var(--a2ui-choicepicker-gap, var(--a2ui-spacing-xs, 0.25rem));
      }
      label {
        color: var(--a2ui-choicepicker-label-color, inherit);
        font-size: var(
          --a2ui-choicepicker-label-font-size,
          var(--a2ui-label-font-size, var(--a2ui-font-size-s))
        );
        font-weight: var(
          --a2ui-choicepicker-label-font-weight,
          var(--a2ui-label-font-weight, bold)
        );
      }
      select {
        background-color: var(--a2ui-color-input, #fff);
        color: var(--a2ui-color-on-input, #333);
        border: var(--a2ui-textfield-border, var(--a2ui-border, 1px solid #ccc));
        border-radius: var(
          --a2ui-choicepicker-select-border-radius,
          var(--a2ui-border-radius, 0.25rem)
        );
        padding: var(
          --a2ui-choicepicker-select-padding,
          var(--a2ui-spacing-s, 0.25rem) var(--a2ui-spacing-m, 0.5rem)
        );
        font-family: inherit;
        font-size: inherit;
        max-width: 100%;
      }
      select:focus {
        outline: none;
        border-color: var(
          --a2ui-textfield-color-border-focus,
          var(--a2ui-color-primary, #17e)
        );
      }
      .options {
        display: flex;
        flex-direction: column;
        gap: var(--a2ui-choicepicker-gap, var(--a2ui-spacing-xs, 0.25rem));
      }
      .option-label {
        font-weight: normal;
        font-size: inherit;
      }
    `;

    createController() {
      return new A2uiController(this, ChoicePickerApi);
    }

    render() {
      const props = this.controller?.props;
      if (!props) return nothing;

      const selected = Array.isArray(props.value) ? props.value : [];
      const options = props.options || [];

      const body =
        props.variant === "multipleSelection"
          ? this.renderCheckboxes(props, options, selected)
          : this.renderSelect(props, options, selected);

      return html`
        ${props.label ? html`<label>${props.label}</label>` : nothing} ${body}
      `;
    }

    renderSelect(props, options, selected) {
      const {html, nothing} = lit;
      const current = selected.length > 0 ? selected[0] : undefined;
      const hasMatch = options.some((opt) => opt.value === current);

      return html`
        <select
          aria-label=${props.label || "Choose an option"}
          @change=${(e) => props.setValue && props.setValue([e.target.value])}
        >
          ${hasMatch
            ? nothing
            : html`<option value="" disabled selected hidden>Select…</option>`}
          ${options.map(
            (opt) =>
              html`<option value=${opt.value} ?selected=${opt.value === current}>
                ${opt.label}
              </option>`,
          )}
        </select>
      `;
    }

    renderCheckboxes(props, options, selected) {
      const {html} = lit;

      const toggle = (value) => {
        if (!props.setValue) return;
        if (selected.includes(value)) {
          props.setValue(selected.filter((v) => v !== value));
        } else {
          props.setValue([...selected, value]);
        }
      };

      return html`
        <div class="options">
          ${options.map(
            (opt) => html`
              <label class="option-label">
                <input
                  type="checkbox"
                  .checked=${selected.includes(opt.value)}
                  @change=${() => toggle(opt.value)}
                />
                ${opt.label}
              </label>
            `,
          )}
        </div>
      `;
    }

    // The basic catalog's shared base class applies the layout `weight`
    // prop as flex; replicate that here since the base class isn't part of
    // @a2ui/lit's public exports.
    willUpdate(changedProperties) {
      super.willUpdate(changedProperties);
      const props = this.controller?.props;
      if (props && props.weight !== undefined) {
        this.style.flex = String(props.weight);
      } else {
        this.style.removeProperty("flex");
      }
    }
  }

  customElements.define(TAG_NAME, AshA2uiChoicePickerElement);
}

export default createAshA2uiCatalog;
