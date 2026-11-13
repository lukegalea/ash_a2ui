// The two shipped catalogs built as catalogs.mjs builds them, but over an
// A2uiLitElement that renders into light DOM (createRenderRoot() returns
// `this`), the default of the upstream @a2ui/lit after 0.15.0. Import it
// instead of catalogs.mjs, in a test file of its own: the tags can be
// defined once per process.

import {register} from "node:module";
import "./dom.mjs";

register("./resolve_hooks.mjs", import.meta.url);

const lit = await import("lit");
const {A2uiLitElement, A2uiController} = await import("@a2ui/lit");
const basic = await import("@a2ui/web_core/catalogs/basic/v1");

const ashCatalog = await import("../../priv/js/ash_a2ui_catalog.js");
const adminCatalog = await import("../../priv/js/ash_admin_catalog.js");

// The upstream change is to A2uiLitElement itself (its createRenderRoot()
// returns `this`), so the pinned class is changed in place rather than
// subclassed: an element that calls past A2uiLitElement to LitElement (the
// ConfirmDialog's update) sees the same prototype chain as upstream.
A2uiLitElement.prototype.createRenderRoot = function createRenderRoot() {
  return this;
};

const deps = {
  basicCatalog: basic.basicCatalog,
  ChoicePickerApi: basic.ChoicePickerApi,
  ColumnApi: basic.ColumnApi,
  A2uiLitElement,
  A2uiController,
  lit: {html: lit.html, css: lit.css, nothing: lit.nothing},
};

export const mergedCatalog = ashCatalog.createAshA2uiCatalog(deps);
export const admin = adminCatalog.createAshAdminCatalog({...deps, basicCatalog: mergedCatalog});
