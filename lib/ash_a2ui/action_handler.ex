defmodule AshA2ui.ActionHandler do
  @moduledoc """
  Consumes A2UI client->server `action` envelope messages and invokes the
  corresponding Ash actions (actor-aware, `authorize?: true` by default).

  FROZEN CONTRACT — the `handle/3` signature is the interface every parallel
  track codes against; do not change outside an integration commit.

  ## Accepted message shapes

  The full client->server envelope from the A2UI v0.9.1 spec
  (`priv/a2ui/v0_9_1/client_to_server.json`):

      %{
        "version" => "v0.9.1",
        "action" => %{
          "name" => "submit_form",
          "surfaceId" => "...",
          "sourceComponentId" => "...",
          "timestamp" => "...",
          "context" => %{...}
        }
      }

  Be liberal in what you accept: a bare inner action map
  (`%{"name" => ..., "context" => ...}`) is also handled, for transports that
  unwrap the envelope before dispatching. Only `"name"` and `"context"` are
  consumed; the `surfaceId` on every follow-up message always comes from the
  resolved view, never from the incoming message.

  ## Supported `action.name` values

    * `"submit_form"` — context
      `%{"values" => %{field => value}, "recordId" => id | nil}`. Without
      `"recordId"` the view's create action runs; with it, the update action.
      `values` keys are strings and are cast to the target action's accepted
      attributes and arguments by comparing against their known names (no
      dynamic atom creation); unknown keys are silently dropped. Values from
      single-select ChoicePickers (relationship selects, enums) may arrive as
      one-element string lists — they are unwrapped before Ash casts them to
      the attribute/argument type.

    * `"invoke"` — context
      `%{"action" => name, "recordId" => id | nil, "values" => map | absent}`.
      Invokes a destroy/update/generic action by name. The action **must be
      listed in the resolved view's `row_actions`** — that allowlist is the
      authorization surface for client-triggered actions; anything else is
      rejected with a `/ui/status` error before touching Ash. When the
      action's `action` entity declares `visible_when` conditions, the
      identified record is fetched (with any condition calculations loaded)
      and the conditions are evaluated server-side — an invoke on a
      non-visible action is rejected with a `/ui/status` error, regardless
      of what the client rendered. Destroy- and
      update-type actions run **the named action** on the record identified
      by `"recordId"`. Params are empty unless the action's `action` entity
      declares `prompt_fields`: then the context's `"values"` map is
      filtered to the declared prompt fields and cast against the Ash
      action's arguments/accepts (unknown keys silently dropped; `"values"`
      is ignored entirely for actions without `prompt_fields`); validation
      errors map to `/errors/<field>` as usual, and a success clears the
      action's `/prompt/values/<action>` state. For generic
      actions that define a `:record_id` argument, the context's `"recordId"`
      is passed through. A generic action returning a map has its raw result
      placed at `/ui/action_result` and a human-readable rendering (one
      "Humanized key: value" line per key) at `/ui/action_result_text`
      (handler-defined conventions, not part of the A2UI spec). Both paths
      are cleared by every subsequent successful action.

    * `"prompt"` — context `%{"action" => name, "recordId" => id}`. Sent by
      the trigger button of a prompt Modal (see `AshA2ui.Encoder.V0_9_1`)
      when it opens. The action must be an allowlisted row action declaring
      `prompt_fields`, and its `visible_when` conditions (if any) are
      enforced against the identified record. On success returns
      `updateDataModel` messages pre-filling `/prompt/values/<action>` (each
      prompt field's current record value when it is a public attribute,
      `""` otherwise) and clearing `/errors`. No Ash write happens — the
      write is the subsequent `"invoke"` from the Modal's confirm button.

    * `"select_row"` — context `%{"recordId" => id}`. Returns a single
      `updateDataModel` populating `/form` with the record's field values
      (edit-form population), including `"id"`.

    * `"query"` — context `%{"query" => <the /query map>}` plus an optional
      literal `"page"` override or relative `"pageDelta"` (used by the
      emitted Apply / prev / next controls). Requires the surface's table to
      declare a `query`; every requested search/sort/filter/page value is
      validated against that named allowlist by `AshA2ui.QueryRunner` —
      non-allowlisted values are rejected with a `/ui/status` error before
      Ash is called. On success returns `updateDataModel` messages for
      `/records` and `/query`.

  Unknown action names and malformed messages return
  `{:error, [updateDataModel]}` with an explanation at `/ui/status`.

  ## Follow-up messages

  All returned messages are A2UI v0.9.1 `updateDataModel` server messages
  using the reserved data-model paths (see `topics/data-model-conventions`):

    * on success: `/records` (re-read row maps, each including `"id"`;
      `source` columns are re-loaded and walked), `/form` cleared to `%{}`,
      `/errors` cleared to `%{}`, `/ui/status` set to a success text, and
      `/ui/action_result` + `/ui/action_result_text` cleared — then set for
      map-returning generic actions. On query-enabled surfaces the re-read
      runs through
      the query (`submit_form`/`invoke` contexts may carry the current
      `/query` map under `"query"`; missing or invalid state falls back to
      the query's defaults) and a `/query` state message is included;
    * on validation errors: `/errors/<field>` per failing field and
      `/ui/status`;
    * on `Ash.Error.Forbidden`: only a `/ui/status` "not authorized" message
      (no field errors, to avoid leaking policy details).

  Values are serialized JSON-safe (dates/datetimes to ISO 8601, decimals to
  strings, atoms to strings).
  """

  alias Ash.Resource.Info, as: ResourceInfo
  alias AshA2ui.Conditions
  alias AshA2ui.QueryRunner
  alias AshA2ui.ResolvedView

  @version "v0.9.1"

  @doc """
  Handles an A2UI client `action` envelope for the surface declared on
  `resource_or_ui_module` (an `Ash.Resource` using the `AshA2ui` extension,
  or an `AshA2ui.Standalone` UI module).

  Returns `{:ok, messages}` with follow-up server->client messages or
  `{:error, messages}` carrying error information on the reserved
  `/errors/<field>` and `/ui/status` data-model paths. See the moduledoc for
  the accepted message shapes and emitted messages.

  ## Options

    * `:actor` — the actor for the Ash action invocation (and the refresh
      read).
    * `:tenant` — the tenant for the Ash action invocation.
    * `:authorize?` — whether to authorize the Ash calls. Defaults to `true`.
  """
  @spec handle(module, action_message :: map, opts :: keyword) ::
          {:ok, [map]} | {:error, [map]}
  def handle(resource_or_ui_module, action_message, opts \\ []) do
    view = ResolvedView.resolve(resource_or_ui_module, opts)
    ash_opts = ash_opts(view, opts)

    case parse(action_message) do
      {:ok, name, context} ->
        env = %{view: view, ash_opts: ash_opts, refresh: refresh_params(view, context)}
        dispatch(name, context, env)

      :error ->
        {:error, [status(view, "Malformed action message: expected an A2UI action envelope.")]}
    end
  end

  # Success refreshes respect the client's current query state when a table
  # has a `query` configured: any action context may carry the current
  # `/query` value under `"query"` — the single table's state map, or (on
  # multi-table surfaces) the whole per-table state object. Returns
  # `%{table_name => params | nil}` (nil for tables without a query). A
  # missing or invalid carried state falls back to the query's declared
  # defaults (the write itself is never failed over refresh state).
  defp refresh_params(view, context) do
    carried = (is_map(context) && Map.get(context, "query")) || nil

    Map.new(view.tables, fn table ->
      {table.name, table_refresh_params(view, table, carried)}
    end)
  end

  defp table_refresh_params(_view, %{query: nil}, _carried), do: nil

  defp table_refresh_params(view, table, carried) do
    state =
      if ResolvedView.multi_table?(view) do
        is_map(carried) && Map.get(carried, to_string(table.name))
      else
        carried
      end

    case QueryRunner.parse(table, %{"query" => state}) do
      {:ok, params} -> params
      {:error, _reason} -> QueryRunner.default_params(table.query)
    end
  end

  defp parse(%{"action" => %{"name" => name} = action}) when is_binary(name),
    do: {:ok, name, Map.get(action, "context") || %{}}

  defp parse(%{"name" => name} = action) when is_binary(name),
    do: {:ok, name, Map.get(action, "context") || %{}}

  defp parse(_action_message), do: :error

  defp ash_opts(view, opts) do
    [
      domain: ResourceInfo.domain(view.resource),
      actor: opts[:actor],
      tenant: opts[:tenant],
      authorize?: Keyword.get(opts, :authorize?, true)
    ]
  end

  # --- dispatch --------------------------------------------------------------

  defp dispatch("submit_form", context, env) do
    values = Map.get(context, "values") || %{}

    case Map.get(context, "recordId") do
      nil -> create(env, values)
      record_id -> update(env, record_id, values)
    end
  end

  defp dispatch("invoke", context, %{view: view} = env) do
    requested = Map.get(context, "action")
    allowed = requested && Enum.find(view.row_actions, &(to_string(&1) == requested))

    cond do
      not is_binary(requested) ->
        {:error, [status(view, ~s(Malformed invoke action: context is missing "action".))]}

      is_nil(allowed) ->
        {:error,
         [
           status(
             view,
             "Action #{inspect(requested)} is not allowed: it is not listed in the " <>
               "view's row_actions."
           )
         ]}

      true ->
        invoke(allowed, Map.get(context, "recordId"), Map.get(context, "values"), env)
    end
  end

  defp dispatch("prompt", context, %{view: view, ash_opts: ash_opts}) do
    requested = Map.get(context, "action")
    allowed = requested && Enum.find(view.row_actions, &(to_string(&1) == requested))
    setting = allowed && Map.get(view.actions, allowed)
    record_id = Map.get(context, "recordId")

    cond do
      not is_binary(requested) ->
        {:error, [status(view, ~s(Malformed prompt action: context is missing "action".))]}

      is_nil(allowed) ->
        {:error,
         [
           status(
             view,
             "Action #{inspect(requested)} is not allowed: it is not listed in the " <>
               "view's row_actions."
           )
         ]}

      not match?(%{prompt_fields: [_ | _]}, setting) ->
        {:error, [status(view, "Action #{inspect(requested)} does not declare prompt_fields.")]}

      is_nil(record_id) ->
        {:error, [status(view, ~s(Malformed prompt action: context is missing "recordId".))]}

      true ->
        prompt(view, setting, record_id, ash_opts)
    end
  end

  defp dispatch("select_row", context, %{view: view, ash_opts: ash_opts}) do
    case Map.get(context, "recordId") do
      nil ->
        {:error, [status(view, ~s(Malformed select_row action: context is missing "recordId".))]}

      record_id ->
        select_row(view, record_id, ash_opts)
    end
  end

  defp dispatch("query", context, %{view: view, ash_opts: ash_opts}) do
    with {:table, {:ok, table}} <- {:table, query_table(view, context)},
         {:parse, {:ok, params}} <- {:parse, QueryRunner.parse(table, context)},
         {:run, {:ok, records, query_state}} <-
           {:run, QueryRunner.run(table, params, ash_opts)} do
      {:ok,
       [
         update_data_model(view, table.records_path, rows(view, table, records)),
         update_data_model(view, table.query_path, query_state)
       ]}
    else
      {:table, {:error, reason}} -> {:error, [status(view, reason)]}
      {:parse, {:error, reason}} -> {:error, [status(view, reason)]}
      {:run, {:error, error}} -> {:error, error_messages(view, error)}
    end
  end

  defp dispatch(name, _context, %{view: view}) do
    {:error, [status(view, "Unknown action #{inspect(name)}.")]}
  end

  # The table a "query" action targets: the only table on single-table
  # surfaces; on multi-table surfaces the context must carry the source
  # "component" (the emitted controls always do). A surface without tables
  # resolves to the view itself — its nil query makes QueryRunner.parse
  # reject with the usual "no query configured" message.
  defp query_table(%ResolvedView{tables: [table]}, _context), do: {:ok, table}
  defp query_table(%ResolvedView{tables: []} = view, _context), do: {:ok, view}

  defp query_table(view, context) do
    case is_map(context) && Map.get(context, "component") do
      component when is_binary(component) ->
        case Enum.find(view.tables, &(to_string(&1.name) == component)) do
          nil -> {:error, "Unknown table component #{inspect(component)}."}
          table -> {:ok, table}
        end

      _missing ->
        {:error,
         ~s(Malformed query action: multi-table surfaces require "component" in the context.)}
    end
  end

  # --- submit_form -----------------------------------------------------------

  defp create(%{view: view, ash_opts: ash_opts} = env, values) do
    action = view.create_action || primary_action(view.resource, :create)
    env = Map.put(env, :invoked, action)

    view.resource
    |> Ash.Changeset.for_create(action, cast_values(view.resource, action, values), ash_opts)
    |> Ash.create()
    |> after_write(env, "Created successfully.")
  end

  defp update(%{view: view, ash_opts: ash_opts} = env, record_id, values) do
    action = view.update_action || primary_action(view.resource, :update)
    env = Map.put(env, :invoked, action)

    result =
      with {:ok, record} <- fetch_record(view, record_id, ash_opts) do
        record
        |> Ash.Changeset.for_update(action, cast_values(view.resource, action, values), ash_opts)
        |> Ash.update()
      end

    after_write(result, env, "Updated successfully.")
  end

  # --- invoke ----------------------------------------------------------------

  defp invoke(action_name, record_id, values, %{view: view} = env) do
    setting = Map.get(view.actions, action_name)
    env = env |> Map.put(:invoked, action_name) |> Map.put(:setting, setting)

    case enforce_visibility(view, setting, record_id, env.ash_opts) do
      :ok ->
        params = prompt_params(view, setting, action_name, values)

        case ResourceInfo.action(view.resource, action_name) do
          %{type: :destroy} ->
            invoke_destroy(action_name, record_id, params, env)

          %{type: :update} ->
            invoke_update(action_name, record_id, params, env)

          %{type: :action} = action ->
            invoke_generic(action, record_id, params, env)

          _other ->
            {:error,
             [status(view, "Action #{inspect(action_name)} cannot be invoked as a row action.")]}
        end

      {:error, messages} ->
        {:error, messages}
    end
  end

  # Handler-side visible_when enforcement (mandatory — rendering hides
  # buttons best-effort, but the server is the authority): the identified
  # record is fetched with any condition calculations loaded, and every
  # condition must hold or the invoke is rejected before touching the write.
  defp enforce_visibility(_view, nil, _record_id, _ash_opts), do: :ok
  defp enforce_visibility(_view, %{visible_when: []}, _record_id, _ash_opts), do: :ok

  defp enforce_visibility(view, %{name: name}, nil, _ash_opts) do
    {:error,
     [
       status(
         view,
         "Action #{inspect(to_string(name))} declares visible_when conditions and " <>
           ~s(requires a "recordId" to evaluate them.)
       )
     ]}
  end

  defp enforce_visibility(view, %{visible_when: conditions, name: name}, record_id, ash_opts) do
    loads = Conditions.condition_loads(view.resource, conditions)

    case fetch_record(view, record_id, ash_opts, loads) do
      {:ok, record} ->
        if Conditions.visible?(view.resource, conditions, record) do
          :ok
        else
          {:error,
           [status(view, "Action #{inspect(to_string(name))} is not available for this record.")]}
        end

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  # The invoke params: empty unless the action declares prompt_fields — then
  # the client-sent "values" map is filtered to the declared prompt fields
  # (nothing outside them ever reaches the changeset) and cast against the
  # Ash action's arguments/accepts. "values" on prompt-less actions is
  # ignored entirely.
  defp prompt_params(view, %{prompt_fields: [_ | _] = fields}, action_name, values)
       when is_map(values) do
    allowed = MapSet.new(fields, &Atom.to_string/1)
    filtered = Map.filter(values, fn {key, _value} -> normalize_key(key) in allowed end)
    cast_values(view.resource, action_name, filtered)
  end

  defp prompt_params(_view, _setting, _action_name, _values), do: %{}

  defp invoke_destroy(action_name, record_id, params, %{view: view, ash_opts: ash_opts} = env) do
    result =
      with {:ok, record} <- fetch_record(view, record_id, ash_opts) do
        record
        |> Ash.Changeset.for_destroy(action_name, params, ash_opts)
        |> Ash.destroy()
      end

    after_write(result, env, "Action #{inspect(to_string(action_name))} completed.")
  end

  # An `invoke` on an update-type row action runs *that* action on the
  # identified record — with empty params (touch-style actions whose changes
  # come from `change` blocks / defaults), or with the cast prompt values
  # when the action declares prompt_fields. Never the form's update action.
  defp invoke_update(action_name, record_id, params, %{view: view, ash_opts: ash_opts} = env) do
    result =
      with {:ok, record} <- fetch_record(view, record_id, ash_opts) do
        record
        |> Ash.Changeset.for_update(action_name, params, ash_opts)
        |> Ash.update()
      end

    after_write(result, env, "Action #{inspect(to_string(action_name))} completed.")
  end

  defp invoke_generic(action, record_id, params, %{view: view, ash_opts: ash_opts} = env) do
    view.resource
    |> Ash.ActionInput.for_action(
      action.name,
      Map.merge(generic_params(action, record_id), params),
      ash_opts
    )
    |> Ash.run_action()
    |> generic_result(env, "Action #{inspect(to_string(action.name))} completed.")
  end

  # --- prompt ----------------------------------------------------------------

  # Pre-fills /prompt/values/<action> when the prompt Modal opens: each
  # prompt field's current record value when it is a public attribute of the
  # resource, "" otherwise (arguments have no stored value). Clears /errors
  # so stale validation messages don't show inside a fresh prompt.
  defp prompt(view, setting, record_id, ash_opts) do
    loads = Conditions.condition_loads(view.resource, setting.visible_when)

    case fetch_record(view, record_id, ash_opts, loads) do
      {:ok, record} ->
        if Conditions.visible?(view.resource, setting.visible_when, record) do
          {:ok, prompt_prefill_messages(view, setting, record)}
        else
          {:error,
           [
             status(
               view,
               "Action #{inspect(to_string(setting.name))} is not available for this record."
             )
           ]}
        end

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  defp prompt_prefill_messages(view, setting, record) do
    prefill =
      Map.new(setting.prompt_fields, fn field ->
        {Atom.to_string(field), prefill_value(view.resource, record, field)}
      end)

    [
      update_data_model(view, "/prompt/values/#{setting.name}", prefill),
      update_data_model(view, "/errors", %{})
    ]
  end

  defp prefill_value(resource, record, field) do
    if ResourceInfo.attribute(resource, field) do
      case json_value(Map.get(record, field)) do
        nil -> ""
        value -> value
      end
    else
      ""
    end
  end

  defp generic_result({:ok, result}, %{view: view} = env, status_text)
       when is_map(result) and not is_struct(result) do
    extra = [
      update_data_model(view, "/ui/action_result", json_map(result)),
      update_data_model(view, "/ui/action_result_text", action_result_text(result))
    ]

    success(env, status_text, extra)
  end

  defp generic_result({:error, error}, %{view: view}, _status_text) do
    {:error, error_messages(view, error)}
  end

  defp generic_result(_ok_or_other, env, status_text) do
    success(env, status_text)
  end

  # If the generic action declares a `:record_id` argument, pass the
  # context's "recordId" through to it.
  defp generic_params(action, record_id) do
    if record_id && Enum.any?(action.arguments, &(&1.name == :record_id)) do
      %{record_id: record_id}
    else
      %{}
    end
  end

  # --- select_row ------------------------------------------------------------

  defp select_row(view, record_id, ash_opts) do
    case fetch_record(view, record_id, ash_opts) do
      {:ok, record} ->
        {:ok, [update_data_model(view, "/form", record_values(view, record, form_fields(view)))]}

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  # --- success follow-ups ----------------------------------------------------

  defp after_write(:ok, env, status_text), do: success(env, status_text)
  defp after_write({:ok, _record}, env, status_text), do: success(env, status_text)

  defp after_write({:error, error}, %{view: view}, _status_text),
    do: {:error, error_messages(view, error)}

  # A success re-reads and re-emits every refresh-target table (each table's
  # records path, plus its query state when a query is attached — run
  # through the carried-or-default query params, see refresh_params/2),
  # then the standard /form, /errors and /ui writes.
  #
  # Targets default to *every* table; an `action` entity
  # (`action :approve do refreshes [:new_items] end`) limits the refresh to
  # the named table components. /ui/action_result and /ui/action_result_text
  # are cleared on every successful action before any `extra` writes, so a
  # stale result never outlives the action that produced it (a map-returning
  # generic action clears and then sets them in the same batch).
  defp success(env, status_text, extra \\ [])

  defp success(%{view: view} = env, status_text, extra) do
    case refresh_messages(env) do
      {:ok, refresh} ->
        {:ok,
         refresh ++
           [
             update_data_model(view, "/form", %{}),
             update_data_model(view, "/errors", %{}),
             update_data_model(view, "/ui/status", status_text),
             update_data_model(view, "/ui/action_result", %{}),
             update_data_model(view, "/ui/action_result_text", "")
           ] ++ prompt_clear(env) ++ extra}

      {:error, error} ->
        {:error, error_messages(view, error)}
    end
  end

  # A successful prompt-backed invoke resets its /prompt/values/<action>
  # state so the next prompt starts clean.
  defp prompt_clear(%{view: view, setting: %{prompt_fields: [_ | _], name: name}}),
    do: [update_data_model(view, "/prompt/values/#{name}", %{})]

  defp prompt_clear(_env), do: []

  defp refresh_messages(%{view: view, ash_opts: ash_opts, refresh: refresh} = env) do
    view
    |> refresh_targets(env[:invoked])
    |> Enum.reduce_while({:ok, []}, fn table, {:ok, acc} ->
      case table_refresh(view, table, refresh[table.name], ash_opts) do
        {:ok, messages} -> {:cont, {:ok, acc ++ messages}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp refresh_targets(view, invoked) do
    case invoked && Map.get(view.refreshes, invoked) do
      nil -> view.tables
      names -> Enum.filter(view.tables, &(&1.name in names))
    end
  end

  defp table_refresh(view, %{query: nil} = table, _params, ash_opts) do
    case read_table(table, ash_opts) do
      {:ok, records} ->
        {:ok, [update_data_model(view, table.records_path, rows(view, table, records))]}

      {:error, error} ->
        {:error, error}
    end
  end

  defp table_refresh(view, table, params, ash_opts) do
    case QueryRunner.run(table, params || QueryRunner.default_params(table.query), ash_opts) do
      {:ok, records, query_state} ->
        {:ok,
         [
           update_data_model(view, table.records_path, rows(view, table, records)),
           update_data_model(view, table.query_path, query_state)
         ]}

      {:error, error} ->
        {:error, error}
    end
  end

  # Table rows carry the per-row visibility data (`"_actions"` +
  # `"_visible_<action>"`, see AshA2ui.Conditions) when any of the table's
  # row actions declare visible_when conditions.
  defp rows(view, table, records) do
    Enum.map(records, fn record ->
      view
      |> record_values(record, table_fields(table))
      |> Map.merge(Conditions.row_visibility(view, table, record))
    end)
  end

  # Human-readable, selectable text for a map-returning generic action:
  # one "Humanized key: value" line per key, sorted by key.
  defp action_result_text(result) do
    result
    |> Enum.map(fn {key, value} -> {to_string(key), json_value(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join("\n", fn {key, value} ->
      "#{humanize(key)}: #{display_value(value)}"
    end)
  end

  defp display_value(value) when is_binary(value), do: value
  defp display_value(value), do: Jason.encode!(value)

  defp humanize(key) do
    key
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  # --- Ash invocation helpers ------------------------------------------------

  defp read_table(table, ash_opts) do
    table.resource
    |> Ash.Query.for_read(
      table.read_action || primary_action(table.resource, :read),
      %{},
      ash_opts
    )
    |> Ash.Query.load(table.loads)
    |> Ash.read()
  end

  # Record lookups (updates, destroys, select_row) go through the single
  # table's read action; on multi-table surfaces — where per-table reads may
  # be filtered slices — through the resource's primary read. `loads` covers
  # visible_when condition calculations when enforcement needs them.
  defp fetch_record(view, record_id, ash_opts, loads \\ []) do
    opts =
      ash_opts
      |> Keyword.put(:action, read_action(view))
      |> Keyword.put(:load, loads)

    Ash.get(view.resource, record_id, opts)
  end

  defp read_action(view), do: view.read_action || primary_action(view.resource, :read)

  defp primary_action(resource, type) do
    ResourceInfo.primary_action!(resource, type).name
  end

  # Cast string-keyed client values to the action's accepted attributes and
  # arguments by matching against their known names — never creating atoms
  # from client input. Unknown keys are dropped. Single-select ChoicePickers
  # bind string lists, so a list value targeting a non-array attribute or
  # argument is unwrapped ([v] -> v, [] -> nil) before Ash casts it.
  defp cast_values(resource, action_name, values) do
    action = ResourceInfo.action(resource, action_name)

    known =
      action.arguments
      |> Enum.map(& &1.name)
      |> Kernel.++(List.wrap(Map.get(action, :accept)))
      |> Map.new(&{Atom.to_string(&1), &1})

    values
    |> Enum.flat_map(fn {key, value} ->
      case Map.fetch(known, normalize_key(key)) do
        {:ok, name} -> [{name, unwrap_single(value, target_type(resource, action, name))}]
        :error -> []
      end
    end)
    |> Map.new()
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key

  defp target_type(resource, action, name) do
    case Enum.find(action.arguments, &(&1.name == name)) do
      %{type: type} -> type
      nil -> ResourceInfo.attribute(resource, name).type
    end
  end

  defp unwrap_single(value, {:array, _type}), do: value
  defp unwrap_single([], _type), do: nil
  defp unwrap_single([value], _type), do: value
  defp unwrap_single(value, _type), do: value

  # --- field selection -------------------------------------------------------

  defp table_fields(table) do
    case table.component.fields do
      fields when is_list(fields) -> fields
      _no_declared_fields -> public_attribute_names(table.resource)
    end
  end

  defp form_fields(view) do
    case Enum.find(view.components, &(&1.name == :form)) do
      %{fields: fields} when is_list(fields) -> fields
      _no_form -> default_row_fields(view)
    end
  end

  defp default_row_fields(%{tables: [table | _rest]}), do: table_fields(table)
  defp default_row_fields(view), do: public_attribute_names(view.resource)

  defp public_attribute_names(resource) do
    resource |> ResourceInfo.public_attributes() |> Enum.map(& &1.name)
  end

  # --- error mapping ---------------------------------------------------------

  defp error_messages(view, %Ash.Error.Forbidden{}) do
    [status(view, "You are not authorized to perform this action.")]
  end

  defp error_messages(view, error) do
    field_messages =
      for {field, text} <- field_errors(error) do
        update_data_model(view, "/errors/#{field}", text)
      end

    field_messages ++ [status(view, error_status(field_messages, error))]
  end

  defp error_status([], error) when is_exception(error),
    do: "Request failed: " <> first_line(Exception.message(error))

  defp error_status([], error), do: "Request failed: " <> inspect(error)

  defp error_status(_field_messages, _error),
    do: "Validation failed. Please review the field errors."

  # Walks the error-class `errors` list (as AshPhoenix.Form does) collecting
  # `%{field: f}` / `%{fields: [..]}` sub-errors, interpolating their `vars`
  # into the message text.
  defp field_errors(error) do
    error
    |> collect_field_errors()
    |> Enum.group_by(fn {field, _text} -> field end, fn {_field, text} -> text end)
    |> Enum.map(fn {field, texts} -> {field, Enum.join(Enum.uniq(texts), "; ")} end)
  end

  defp collect_field_errors(%{errors: errors}) when is_list(errors) do
    Enum.flat_map(errors, &collect_field_errors/1)
  end

  defp collect_field_errors(%{field: field} = error) when not is_nil(field) do
    [{field, error_text(error)}]
  end

  defp collect_field_errors(%{fields: fields} = error) when is_list(fields) and fields != [] do
    Enum.map(fields, &{&1, error_text(error)})
  end

  defp collect_field_errors(_error), do: []

  defp error_text(%{message: message} = error) when is_binary(message) do
    interpolate(message, Map.get(error, :vars))
  end

  # Splode prepends a "Bread Crumbs:" preamble to Exception.message/1; the
  # human-readable message is the last non-empty line.
  defp error_text(error) when is_exception(error), do: last_line(Exception.message(error))
  defp error_text(error), do: inspect(error)

  defp interpolate(message, vars) do
    Enum.reduce(vars_list(vars), message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", var_string(value))
    end)
  end

  defp vars_list(vars) when is_map(vars), do: Map.to_list(vars)
  defp vars_list(vars) when is_list(vars), do: vars
  defp vars_list(_vars), do: []

  defp var_string(value) when is_binary(value), do: value
  defp var_string(value), do: inspect(value)

  defp first_line(message) do
    message |> String.split("\n", parts: 2) |> hd() |> String.trim()
  end

  defp last_line(message) do
    message
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> List.last()
    |> Kernel.||("")
  end

  # --- message + value construction ------------------------------------------

  defp status(view, text), do: update_data_model(view, "/ui/status", text)

  defp update_data_model(view, path, value) do
    %{
      "version" => @version,
      "updateDataModel" => %{
        "surfaceId" => view.surface_id,
        "path" => path,
        "value" => value
      }
    }
  end

  defp record_values(view, record, fields) do
    fields
    |> Map.new(fn field -> {Atom.to_string(field), field_value(view, record, field)} end)
    |> Map.put("id", json_value(Map.get(record, :id)))
  end

  # `source` columns read through the loaded relationship path (nil-safe: a
  # nil or unloaded relationship serializes to ""); plain fields read the
  # record key directly.
  defp field_value(view, record, field) do
    case view.fields[field] do
      %{source: [_ | _] = source} ->
        case walk_source(record, source) do
          nil -> ""
          value -> json_value(value)
        end

      _plain ->
        json_value(Map.get(record, field))
    end
  end

  defp walk_source(record, [attribute]), do: Map.get(record, attribute)

  defp walk_source(record, [relationship | rest]) do
    case Map.get(record, relationship) do
      %Ash.NotLoaded{} -> nil
      nil -> nil
      related -> walk_source(related, rest)
    end
  end

  defp json_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), json_value(value)} end)
  end

  # A calculation/aggregate that slipped past `loads` must not leak an
  # inspect()-ed struct onto the wire.
  defp json_value(%Ash.NotLoaded{}), do: nil
  defp json_value(%Decimal{} = value), do: Decimal.to_string(value)
  defp json_value(%Date{} = value), do: Date.to_iso8601(value)
  defp json_value(%Time{} = value), do: Time.to_iso8601(value)
  defp json_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp json_value(value) when is_struct(value), do: inspect(value)
  defp json_value(value) when is_map(value), do: json_map(value)
  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)

  defp json_value(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  defp json_value(value), do: value
end
