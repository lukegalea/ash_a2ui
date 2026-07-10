# Submission checklist

Everything needed to publish `ash_a2ui` and get it in front of the Ash
community. Publishing requires the maintainer's hex.pm account; everything
below is staged so it's one command away.

## 1. Publish to hex.pm

- [ ] Confirm the package name is still free: `mix hex.info ash_a2ui`
      (returned 404 as of 2026-07-10).
- [ ] Final local gate: `mix format --check-formatted && mix credo --strict
      && mix test && mix docs` all clean.
- [ ] Verify package metadata in `mix.exs` (`:package` — maintainer,
      license, `files` list includes `priv`, `documentation`,
      `usage-rules.md`; links point at `lukegalea/ash_a2ui`).
- [ ] `mix hex.user auth` (once, on the publishing machine).
- [ ] `mix hex.publish` — review the file list and docs preview it prints
      **before** confirming.
- [ ] Tag the release: `git tag v0.1.0 && git push --tags` (or use
      `mix git_ops.release`, which manages CHANGELOG + version + tag).

### CI-driven publishing (optional, recommended after first manual publish)

- [ ] Create a hex.pm API key: `mix hex.user key generate --key-name ci
      --permission api:write`.
- [ ] Add it as the `HEX_API_KEY` repository secret on GitHub
      (`lukegalea/ash_a2ui` → Settings → Secrets → Actions). The shared
      `ash-project` CI workflow already wires it; the publish step is inert
      until the secret exists and a `v*` tag is pushed.

## 2. Verify hexdocs

- [ ] After publish, check <https://hexdocs.pm/ash_a2ui>:
  - [ ] README renders as the landing page ("Home").
  - [ ] Sidebar groups present: Tutorials / Topics / DSLs / About AshA2ui.
  - [ ] DSL cheat sheet (`DSL: AshA2ui`) renders with searchable entries
        (search for `row_actions` in the docs search box).
  - [ ] All four topic pages and the tutorial render; spot-check relative
        links between them (they should have been rewritten by ExDoc, not
        point at `documentation/...` paths).
  - [ ] The hex/hexdocs badges in the README resolve (they 404 pre-publish).
- [ ] If anything is broken, fix and `mix hex.publish docs` to republish
      docs without a new release.

## 3. Elixir Forum post (Ash section)

Post to <https://elixirforum.com/c/elixir-framework-forums/ash-framework-forum>.
Draft:

> **Title:** AshA2ui — generate A2UI (Agent to UI) surfaces from Ash resources
>
> Hi all! I just published `ash_a2ui`, an Ash extension that generates
> [A2UI v0.9.1](https://github.com/a2ui-project/a2ui) protocol payloads
> straight from your resources.
>
> You declare a small `a2ui` block (table + form + row actions — or put it
> in a standalone UI module via `use AshA2ui.Standalone`), and the extension
> emits the `createSurface`/`updateComponents`/`updateDataModel` message
> stream for any A2UI renderer (`@a2ui/lit`, `@a2ui/react`, agent canvases).
> Client actions come back as A2UI `action` envelopes and are routed into
> your Ash actions with the actor and `authorize?: true` — the declared
> `row_actions` are the allowlist, and fields/actions are checked by
> compile-time verifiers.
>
> The protocol core depends only on `ash`; there's an optional
> batteries-included LiveView transport (`AshA2ui.LiveRenderer`) with
> PubSub-driven live data refresh, and plain JSON endpoints work as an
> alternative transport. Every emitted payload is validated against the
> vendored A2UI JSON Schemas in the test suite.
>
> Docs: <https://hexdocs.pm/ash_a2ui> — including an honest "when it pays
> off" guide (spoiler: if you just need an internal admin, AshAdmin is less
> work).
>
> Feedback very welcome, especially from anyone rendering A2UI surfaces in
> agent canvases.

- [ ] Post it, and update the link here: ________

## 4. Ash Discord `#showcase` blurb

> Just published **ash_a2ui** — declare a `a2ui do ... end` block on an Ash
> resource (or a standalone UI module) and get an A2UI v0.9.1 surface over
> the wire: tables, forms, row actions, compile-time verifiers, actor-aware
> auth. Core depends only on `ash`; optional LiveView transport with PubSub
> live refresh; renders with `@a2ui/lit` / `@a2ui/react` or any A2UI client.
> 📦 <https://hex.pm/packages/ash_a2ui> · 📚 <https://hexdocs.pm/ash_a2ui>

- [ ] Post in `#showcase` on the Ash Discord (invite: discord.gg/HTHRaaVPUc).

## 5. PR to ash-project/ash README ("Packages" section)

- [ ] Wait until the hex package + hexdocs are live (listing PRs for
      unpublished packages get bounced).
- [ ] Fork `ash-project/ash`, edit the README's community packages table,
      and add a one-liner in alphabetical position, matching the existing
      row format:

      | [AshA2ui](https://hexdocs.pm/ash_a2ui) | Generate A2UI (Agent to UI) protocol surfaces from Ash resources. |

- [ ] Open the PR referencing the hex package and the forum post; note that
      CI uses the shared `ash-project` reusable workflow and the test suite
      validates payloads against the vendored A2UI spec schemas.

## 6. Post-publish housekeeping

- [ ] Flip the README "Status: not yet published" note to a normal install
      section.
- [ ] Replace the "pending POC" cells in the README coverage matrix and the
      LOC data point in `documentation/topics/what-is-ash-a2ui.md` once the
      reference POC lands.
- [ ] Watch the GitHub Actions run on the release tag — the hexdocs publish
      job needs `HEX_API_KEY` (step 1).
