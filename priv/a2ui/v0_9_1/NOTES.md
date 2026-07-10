# Vendored A2UI v0.9.1 spec schemas

These JSON Schema files are vendored verbatim from the A2UI specification repo
(<https://github.com/a2ui-project/a2ui>), `specification/v0_9_1/` directory.

- **Source commit:** `96abfdc60de0657c6322028d10c1cc7bc25c237c` (`main`, 2026-07-10).
  There is no `v0.9.1` git tag in the upstream repo (only `v0.8`/`v0.9` tags exist,
  both pointing at the same commit which predates the `v0_9_1` spec directory), so the
  files are pinned to this commit of `main` instead.
- **Fetched:** 2026-07-10, all files verified to parse as valid JSON.

| Local file | Source URL |
|---|---|
| `server_to_client.json` | <https://raw.githubusercontent.com/a2ui-project/a2ui/96abfdc60de0657c6322028d10c1cc7bc25c237c/specification/v0_9_1/json/server_to_client.json> |
| `client_to_server.json` | <https://raw.githubusercontent.com/a2ui-project/a2ui/96abfdc60de0657c6322028d10c1cc7bc25c237c/specification/v0_9_1/json/client_to_server.json> |
| `common_types.json` | <https://raw.githubusercontent.com/a2ui-project/a2ui/96abfdc60de0657c6322028d10c1cc7bc25c237c/specification/v0_9_1/json/common_types.json> |
| `client_capabilities.json` | <https://raw.githubusercontent.com/a2ui-project/a2ui/96abfdc60de0657c6322028d10c1cc7bc25c237c/specification/v0_9_1/json/client_capabilities.json> |
| `server_capabilities.json` | <https://raw.githubusercontent.com/a2ui-project/a2ui/96abfdc60de0657c6322028d10c1cc7bc25c237c/specification/v0_9_1/json/server_capabilities.json> |
| `client_data_model.json` | <https://raw.githubusercontent.com/a2ui-project/a2ui/96abfdc60de0657c6322028d10c1cc7bc25c237c/specification/v0_9_1/json/client_data_model.json> |
| `server_to_client_list.json` | <https://raw.githubusercontent.com/a2ui-project/a2ui/96abfdc60de0657c6322028d10c1cc7bc25c237c/specification/v0_9_1/json/server_to_client_list.json> |
| `server_to_client_list_wrapper.json` | <https://raw.githubusercontent.com/a2ui-project/a2ui/96abfdc60de0657c6322028d10c1cc7bc25c237c/specification/v0_9_1/json/server_to_client_list_wrapper.json> |
| `client_to_server_list.json` | <https://raw.githubusercontent.com/a2ui-project/a2ui/96abfdc60de0657c6322028d10c1cc7bc25c237c/specification/v0_9_1/json/client_to_server_list.json> |
| `client_to_server_list_wrapper.json` | <https://raw.githubusercontent.com/a2ui-project/a2ui/96abfdc60de0657c6322028d10c1cc7bc25c237c/specification/v0_9_1/json/client_to_server_list_wrapper.json> |
| `sample.json` | <https://raw.githubusercontent.com/a2ui-project/a2ui/96abfdc60de0657c6322028d10c1cc7bc25c237c/specification/v0_9_1/json/sample.json> |
| `catalogs/basic/catalog.json` | <https://raw.githubusercontent.com/a2ui-project/a2ui/96abfdc60de0657c6322028d10c1cc7bc25c237c/specification/v0_9_1/catalogs/basic/catalog.json> |

Notes on schema mechanics (relevant to `AshA2ui.Test.SchemaHelper`):

- The schemas declare `$schema: draft 2020-12` but are validated in tests with
  `ex_json_schema` (draft-7 engine). The helper strips `$schema` before resolving;
  draft-2020-12-only keywords (`unevaluatedProperties`) are ignored by the engine,
  which makes validation slightly *more permissive* than the spec — acceptable for
  positive-path assertions.
- Cross-file `$ref`s use both absolute URLs (`https://a2ui.org/specification/v0_9/...`)
  and relative refs (`catalog.json#/$defs/anyComponent`). The helper rewrites relative
  refs to absolute URLs and resolves all remote refs from these vendored files
  (never the network). `catalog.json` refs resolve to `catalogs/basic/catalog.json`
  (the basic catalog).
