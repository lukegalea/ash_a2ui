# Vendored A2UI v1.0 spec schemas (Release Candidate)

These JSON Schema files are vendored verbatim from the A2UI specification repo
(<https://github.com/a2ui-project/a2ui>), `specification/v1_0/` directory.

- **Source commit:** `96abfdc60de0657c6322028d10c1cc7bc25c237c` (`main`, 2026-07-10) —
  the same commit the v0.9.1 schemas in `../v0_9_1/` are pinned to. There is no
  `v1.0` git tag upstream; per `specification/v1_0/README.md` the v1.0 spec is a
  **release candidate** ("currently a candidate for becoming stable"), previously
  known as v0.10 while in draft. Re-diff against upstream before the final 1.0
  tag lands: any drift between this pin and the eventual stable release must be
  reconciled here and in `AshA2ui.Encoder.V1_0`.
- **Fetched:** 2026-07-13, all files verified to parse as valid JSON.

| Local file | Upstream path (at the pinned commit) |
|---|---|
| `server_to_client.json` | `specification/v1_0/json/server_to_client.json` |
| `client_to_server.json` | `specification/v1_0/json/client_to_server.json` |
| `common_types.json` | `specification/v1_0/json/common_types.json` |
| `catalog_definition.json` | `specification/v1_0/json/catalog_definition.json` |
| `client_capabilities.json` | `specification/v1_0/json/client_capabilities.json` |
| `server_capabilities.json` | `specification/v1_0/json/server_capabilities.json` |
| `client_data_model.json` | `specification/v1_0/json/client_data_model.json` |
| `server_to_client_list.json` | `specification/v1_0/json/server_to_client_list.json` |
| `server_to_client_list_wrapper.json` | `specification/v1_0/json/server_to_client_list_wrapper.json` |
| `client_to_server_list.json` | `specification/v1_0/json/client_to_server_list.json` |
| `client_to_server_list_wrapper.json` | `specification/v1_0/json/client_to_server_list_wrapper.json` |
| `sample.json` | `specification/v1_0/json/sample.json` |
| `catalogs/basic/catalog.json` | `specification/v1_0/catalogs/basic/catalog.json` |
| `test/testing_catalog.json` | `specification/v1_0/test/testing_catalog.json` |
| `test/cases/*.json(l)` | `specification/v1_0/test/cases/*` |

## The upstream conformance cases (`test/cases/`)

The upstream spec ships its own schema test suites (`test/cases/*.json`, each a
`{"schema": <file>, "catalog": <optional file>, "tests": [{description, valid,
data}]}` document, plus `contact_form_example.jsonl` — a full valid message
stream). `AshA2ui.Test.SchemaHelper` runs **all of them** through the same
resolved schemas the encoder tests use (see `test/v1_0_conformance_test.exs`),
so our schema loading is proven equivalent to the reference `ajv` runner —
this, together with the encoder/handler conformance assertions, is the
executable 1.0 spec.

A suite's optional `"catalog"` key aliases `catalog.json` to that file for the
duration of the suite (the upstream runner does the same with a temp file);
without it `catalog.json` resolves to `catalogs/basic/catalog.json`.

## Schema mechanics (relevant to `AshA2ui.Test.SchemaHelper`)

Identical to v0.9.1 (see `../v0_9_1/NOTES.md`):

- The schemas declare `$schema: draft 2020-12` but are validated in tests with
  `ex_json_schema` (draft-7 engine). The helper strips `$schema` before
  resolving; draft-2020-12-only keywords are ignored by the engine, which makes
  validation slightly *more permissive* than the spec — acceptable for
  positive-path assertions (and the negative upstream cases we run all fail on
  draft-7-expressible constraints).
- Cross-file `$ref`s use both absolute URLs
  (`https://a2ui.org/specification/v1_0/...`) and relative refs
  (`catalog.json#/$defs/anyComponent`). The helper rewrites relative refs to
  absolute v1_0 URLs and resolves all remote refs from these vendored files
  (never the network).

## v1.0 semantics the schemas cannot express (covered by conformance tests)

- `updateDataModel` deletion: setting a path's value to `null` deletes the key;
  omitted keys are **no longer** a deletion mechanism.
- `actionId` uniqueness per action needing a response; `surfaceId` global
  uniqueness per client session.
- UAX #31 identifier rules for catalog entity names (components, functions,
  argument keys).
- `callableFrom` execution boundaries are checked at runtime from the catalog,
  not on the wire (`INVALID_FUNCTION_CALL` on violation).
- `@index` is only evaluable inside list-template iteration (Collection Scope);
  the `@` prefix is reserved.
- MIME type: `application/a2ui+json` (was `application/json+a2ui`).
