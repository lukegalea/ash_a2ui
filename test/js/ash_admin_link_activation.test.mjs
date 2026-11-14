// activateLink: the stock reference-link activation, exported for host
// elements that draw a `_links` entry themselves. A plain click on a link to
// a record is an openSurface request (in place, no navigation); anything else
// is left to the browser.

import test from "node:test";
import assert from "node:assert/strict";

import {adminCatalog} from "./catalogs.mjs";

const {activateLink, OPEN_SURFACE_EVENT} = adminCatalog;

const record = {surface: "parties", recordId: 42, label: "Northline", href: "/app/r/parties/42"};

function click(init = {}) {
  return new MouseEvent("click", {bubbles: true, composed: true, cancelable: true, button: 0, ...init});
}

// A source element inside an open shadow root, so the request has to cross it.
function source() {
  const host = document.createElement("div");
  document.body.replaceChildren(host);
  const inner = document.createElement("span");
  host.attachShadow({mode: "open"}).appendChild(inner);
  return inner;
}

function requests() {
  const seen = [];
  const listener = (event) => seen.push(event);
  window.addEventListener(OPEN_SURFACE_EVENT, listener);
  return {seen, stop: () => window.removeEventListener(OPEN_SURFACE_EVENT, listener)};
}

test("a plain click on a record link asks the host to open it in place", () => {
  const {seen, stop} = requests();
  const event = click();
  const bubbled = [];
  const el = source();
  el.parentNode.host.addEventListener("click", () => bubbled.push(true));
  let opened;
  el.addEventListener("click", (e) => (opened = activateLink(e, record, {source: el, surfaceId: "s1"})));

  el.dispatchEvent(event);
  stop();

  assert.equal(opened, true);
  assert.equal(event.defaultPrevented, true);
  assert.equal(seen.length, 1);
  assert.equal(seen[0].composed, true);
  assert.deepEqual(seen[0].detail, {surface: "parties", recordId: "42", surfaceId: "s1", href: "/app/r/parties/42"});
  assert.deepEqual(bubbled, []);
});

test("the host's openSurface callback takes the request when given", () => {
  const {seen, stop} = requests();
  const calls = [];
  const deps = {openSurface: (args, info) => calls.push([args, info])};

  const opened = activateLink(click(), record, {source: source(), surfaceId: "s1", deps});
  stop();

  assert.equal(opened, true);
  assert.deepEqual(calls, [[{surface: "parties", recordId: "42"}, {surfaceId: "s1", href: "/app/r/parties/42"}]]);
  assert.equal(seen.length, 0);
});

test("a modified or middle click keeps the browser's own behaviour", () => {
  for (const init of [{metaKey: true}, {ctrlKey: true}, {shiftKey: true}, {altKey: true}, {button: 1}]) {
    const {seen, stop} = requests();
    const event = click(init);
    const opened = activateLink(event, record, {source: source()});
    stop();

    assert.equal(opened, false, JSON.stringify(init));
    assert.equal(event.defaultPrevented, false, JSON.stringify(init));
    assert.equal(seen.length, 0, JSON.stringify(init));
  }
});

test("a plain link (no surface) is followed, not opened in place", () => {
  const {seen, stop} = requests();
  const event = click();
  const opened = activateLink(event, {href: "/requests/42", label: "Request"}, {source: source()});
  stop();

  assert.equal(opened, false);
  assert.equal(event.defaultPrevented, false);
  assert.equal(seen.length, 0);
});
