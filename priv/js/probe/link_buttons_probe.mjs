/**
 * Basic-catalog link-button probe — the browser gate for reference links
 * in the basic composition (`link_buttons: true`, see the Relationships
 * guide):
 *
 *   merged catalog (createAshA2uiCatalog)
 *     - a `<value id>_link` Button reads as a link: the page font (not the
 *       user-agent button font), the link colour on the Text inside, an
 *       underline, no button box, and a focus ring on keyboard focus;
 *     - activating one dispatches `open_surface` with the row's bound
 *       surface and record id; the detail's link does the same after the
 *       context_select reply;
 *     - following a link (the surface leaves the DOM, as a LiveView
 *       navigation does) logs no console error. The status banner used to
 *       throw "unsubscribe is not a function" here.
 *   stock basic catalog
 *     - the same Buttons dispatch the same action, and teardown is clean.
 *
 * Fixtures are recorded wire payloads:
 *
 *     MIX_ENV=test mix run priv/js/probe/record_link_buttons.exs
 *
 * Run:
 *
 *     node priv/js/probe/link_buttons_probe.mjs [--node-modules DIR] [--port N]
 *
 * `--node-modules` is any tree with @a2ui/lit + @a2ui/web_core 0.10.x or
 * 0.11.x and lit 3. Chrome comes from $CHROME, Playwright from
 * $PLAYWRIGHT_NODE_MODULES. Exit code is the verdict.
 */

import {cpSync, mkdirSync, mkdtempSync, rmSync, symlinkSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, join, resolve} from "node:path";
import {spawn} from "node:child_process";

const probeDir = dirname(fileURLToPath(import.meta.url));
const repoPrivJs = resolve(probeDir, "..");

const args = process.argv.slice(2);
const arg = (name, fallback) => {
  const index = args.indexOf(`--${name}`);
  return index !== -1 ? args[index + 1] : fallback;
};
const nodeModules = arg("node-modules", join(repoPrivJs, "../../../clinic-demo/assets/node_modules"));
const port = Number(arg("port", "4193"));
const executablePath = process.env.CHROME || "/usr/bin/google-chrome";
const playwrightModule = `${process.env.PLAYWRIGHT_NODE_MODULES ?? "/home/lukegalea/vendorpm/quality-assurance/node_modules"}/playwright/index.mjs`;
const {chromium} = await import(playwrightModule);

const results = [];
const failures = [];

async function check(label, fn) {
  try {
    await fn();
    results.push(`ok    ${label}`);
  } catch (error) {
    failures.push(`FAIL  ${label}: ${error.message.split("\n")[0]}`);
  }
}

const expect = (actual, expected, note = "") => {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${note} expected ${e}, got ${a}`);
};

const truthy = (value, note) => {
  if (!value) throw new Error(`${note} (got ${JSON.stringify(value)})`);
};

async function serve() {
  const root = mkdtempSync(join("/tmp", "link-buttons-probe-"));
  symlinkSync(nodeModules, join(root, "nm"), "dir");
  symlinkSync(repoPrivJs, join(root, "catalog"), "dir");
  mkdirSync(join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "fixtures"), join(root, "fixtures"), {recursive: true});
  cpSync(join(probeDir, "link_buttons_probe.html"), join(root, "link_buttons_probe.html"));

  const server = spawn("python3", ["-m", "http.server", String(port), "--directory", root], {
    stdio: "ignore",
  });
  const base = `http://127.0.0.1:${port}`;
  for (let attempt = 0; attempt < 40; attempt++) {
    try {
      await fetch(`${base}/link_buttons_probe.html`, {method: "HEAD"});
      break;
    } catch {
      await new Promise((r) => setTimeout(r, 100));
    }
  }
  return {
    base,
    stop: () => {
      server.kill();
      rmSync(root, {recursive: true, force: true});
    },
  };
}

async function openCase(browser, base, query) {
  const page = await browser.newPage({viewport: {width: 1280, height: 900}});
  const errors = [];
  page.on("pageerror", (error) => errors.push(`PAGEERROR: ${error.message.slice(0, 200)}`));
  page.on("console", (message) => {
    if (message.type() === "error") {
      if (message.location()?.url?.includes("favicon")) return;
      errors.push(`CONSOLE: ${message.text().slice(0, 200)}`);
    }
  });
  page.__errors = errors;
  await page.goto(`${base}/link_buttons_probe.html?${query}`, {waitUntil: "load"});
  await page.waitForFunction(() => window.__boot?.stage && window.__boot.stage !== "imports-done");
  await page.waitForTimeout(600);
  const stage = await page.evaluate(() => window.__boot);
  if (stage.stage === "error") throw new Error(`boot failed: ${stage.error}`);
  await page.evaluate(() => {
    window.__deepAll = (selector) => {
      const found = [];
      const search = (root) => {
        for (const element of root.querySelectorAll(selector)) found.push(element);
        for (const element of root.querySelectorAll("*")) {
          if (element.shadowRoot) search(element.shadowRoot);
        }
      };
      search(document);
      return found;
    };
    window.__deepText = (root) => {
      let text = "";
      const walk = (node) => {
        for (const child of node.childNodes) {
          if (child.nodeType === Node.TEXT_NODE) text += child.textContent;
          else walk(child);
        }
        if (node.shadowRoot) walk(node.shadowRoot);
      };
      walk(root);
      return text.replace(/\s+/g, " ").trim();
    };
    // Component hosts by id, in document order. The basic catalog renders
    // into a shadow root on @a2ui/lit 0.10.x and into light DOM on 0.11.x;
    // __rootOf answers the one this renderer uses.
    window.__hosts = (id) => window.__deepAll("*").filter((el) => el.context?.componentModel?.id === id);
    window.__rootOf = (host) => host.shadowRoot ?? host;
    // The first link Button with a value (rows without a reference render
    // an empty one; see the Relationships guide).
    window.__linkHost = (id) =>
      window.__hosts(id).find((host) => window.__deepText(window.__linkButton(host)) !== "");
    window.__linkButton = (host) => window.__rootOf(host).querySelector("button");
    // The rendered element carrying the link's text (the value Text's p or
    // span), inside the link's button.
    window.__linkInk = (host) => {
      const valueId = host.context.componentModel.id.replace(/_link$/, "");
      const button = window.__linkButton(host);
      const below = [];
      const walk = (root) => {
        for (const el of root.querySelectorAll("*")) {
          below.push(el);
          if (el.shadowRoot) walk(el.shadowRoot);
        }
      };
      walk(button);
      const textHost = below.find((el) => el.context?.componentModel?.id === valueId);
      if (!textHost) return null;
      const root = window.__rootOf(textHost);
      // (0.10.x without a markdown renderer draws a bare span.)
      return root.querySelector(".a2ui-text p") ?? root.querySelector(".a2ui-text") ?? root.querySelector("span");
    };
  });
  return page;
}

const PERSON_LINK = "record_row_meta_value_person_name_link";
const DETAIL_LINK = "detail_note_detail_value_person_name_link";

async function main() {
  const {base, stop} = await serve();
  const browser = await chromium.launch({executablePath});

  try {
    /* --- merged catalog: links look like links ---------------------------- */
    let page = await openCase(browser, base, "catalog=ash");

    await check("ash: a link Button reads as a link (page font, link colour, underline, no box)", async () => {
      const style = await page.evaluate((id) => {
        const host = window.__linkHost(id);
        if (!host) return null;
        const button = window.__linkButton(host);
        const ink = window.__linkInk(host);
        const b = getComputedStyle(button);
        const probe = document.createElement("span");
        probe.style.color = "var(--a2ui-link-color, var(--a2ui-color-primary))";
        document.body.appendChild(probe);
        const linkColor = getComputedStyle(probe).color;
        probe.remove();
        return {
          text: window.__deepText(button),
          pageFont: getComputedStyle(document.body).fontFamily,
          buttonFont: b.fontFamily,
          inkFont: ink && getComputedStyle(ink).fontFamily,
          buttonColor: b.color,
          inkColor: ink && getComputedStyle(ink).color,
          linkColor,
          decoration: b.textDecorationLine,
          padding: b.paddingTop + " " + b.paddingLeft,
          border: b.borderTopWidth,
          shadow: b.boxShadow,
          background: b.backgroundColor,
          hostMargin: getComputedStyle(host).marginTop,
          classes: button.className,
        };
      }, PERSON_LINK);
      truthy(style, "the person link renders");
      truthy(style.text.length > 0, "it shows the value");
      expect(style.buttonFont, style.pageFont, "button font");
      expect(style.inkFont, style.pageFont, "text font");
      expect(style.buttonColor, style.linkColor, "button colour");
      expect(style.inkColor, style.linkColor, "text colour");
      expect(style.decoration, "underline", "underline");
      expect(style.padding, "0px 0px", "padding");
      expect(style.border, "0px", "border");
      expect(style.shadow, "none", "shadow");
      expect(style.background, "rgba(0, 0, 0, 0)", "background");
      expect(style.hostMargin, "0px", "host margin");
      truthy(/\bnb-link\b/.test(style.classes), `the link tier class (${style.classes})`);
    });

    await check("ash: other borderless Buttons keep the button tier", async () => {
      const classes = await page.evaluate(() =>
        window
          .__deepAll("*")
          .filter((el) => /_button$/.test(el.context?.componentModel?.id ?? ""))
          .map((el) => window.__rootOf(el).querySelector("button")?.className ?? ""),
      );
      truthy(classes.length > 0, "the surface has other buttons");
      expect(classes.filter((c) => /\bnb-link\b/.test(c)), [], "no non-link button is a link");
    });

    await check("ash: keyboard focus on a link shows a focus ring", async () => {
      await page.evaluate((id) => window.__linkButton(window.__linkHost(id)).focus(), PERSON_LINK);
      await page.keyboard.press("Shift+Tab");
      await page.keyboard.press("Tab");
      const ring = await page.evaluate((id) => {
        const button = window.__linkButton(window.__linkHost(id));
        const focused = button.getRootNode().activeElement === button;
        const style = getComputedStyle(button);
        return {focused, visible: button.matches(":focus-visible"), outline: style.outlineStyle, width: style.outlineWidth};
      }, PERSON_LINK);
      expect(ring.focused, true, "the link has focus");
      expect(ring.visible, true, ":focus-visible");
      expect(ring.outline, "solid", "outline style");
      expect(ring.width, "2px", "outline width");
    });

    await page.screenshot({path: join(probeDir, "screenshots", "link_buttons_ash.png"), fullPage: true});

    await check("ash: activating a row link dispatches open_surface with its target", async () => {
      await page.evaluate((id) => {
        window.__dispatched.length = 0;
        window.__linkButton(window.__linkHost(id)).click();
      }, PERSON_LINK);
      await page.waitForTimeout(150);
      const dispatched = await page.evaluate(() => window.__dispatched);
      expect(dispatched.map((d) => d.name), ["open_surface"], "dispatched");
      expect(dispatched[0].context.field, "person_name", "field");
      expect(dispatched[0].context.surface, "person", "surface");
      expect(typeof dispatched[0].context.recordId, "string", "record id");
    });

    await check("ash: the detail's link dispatches open_surface after the select reply", async () => {
      await page.evaluate(() => window.__feedFixture("link_buttons_select"));
      await page.waitForTimeout(300);
      await page.evaluate((id) => {
        window.__dispatched.length = 0;
        window.__linkButton(window.__linkHost(id)).click();
      }, DETAIL_LINK);
      await page.waitForTimeout(150);
      const dispatched = await page.evaluate(() => window.__dispatched);
      expect(dispatched.map((d) => d.name), ["open_surface"], "dispatched");
      expect(dispatched[0].context.surface, "person", "surface");
      expect(typeof dispatched[0].context.recordId, "string", "record id");
    });

    await check("ash: following a link (the surface leaves the DOM) logs no console error", async () => {
      await page.evaluate(() => window.__navigate());
      await page.waitForTimeout(300);
      expect(page.__errors, [], "errors");
    });
    await page.close();

    /* --- stock basic catalog --------------------------------------------- */
    page = await openCase(browser, base, "catalog=stock");

    await check("stock: a row link dispatches open_surface, and teardown is clean", async () => {
      await page.evaluate((id) => {
        window.__dispatched.length = 0;
        window.__linkButton(window.__linkHost(id)).click();
      }, PERSON_LINK);
      await page.waitForTimeout(150);
      const names = await page.evaluate(() => window.__dispatched.map((d) => d.name));
      expect(names, ["open_surface"], "dispatched");
      await page.evaluate(() => window.__navigate());
      await page.waitForTimeout(300);
      expect(page.__errors, [], "errors");
    });
    await page.close();
  } finally {
    await browser.close();
    stop();
  }

  for (const line of results) console.log(line);
  for (const line of failures) console.log(line);
  console.log(`\n${results.length} passed, ${failures.length} failed`);
  process.exit(failures.length === 0 ? 0 : 1);
}

await main();
