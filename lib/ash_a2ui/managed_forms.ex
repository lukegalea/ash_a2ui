defmodule AshA2ui.ManagedForms do
  @moduledoc """
  Shared introspection for `nested_form` entities: maps a form action's
  argument to its `manage_relationship` change and infers the nested form's
  interaction mode from the change's options via
  `Ash.Changeset.ManagedRelationshipHelpers` (the AshSDUI-derived approach —
  users declare the argument, never the mode).

  Used by `AshA2ui.ResolvedView` at resolve time and
  `AshA2ui.Verifiers.VerifyNestedForms` at compile time, so both always
  agree.
  """

  alias Ash.Changeset.ManagedRelationshipHelpers
  alias Ash.Resource.Info, as: ResourceInfo

  @typedoc """
  The resolved `manage_relationship` change behind a nested form's argument:
  the relationship struct plus the sanitized manage options
  (`Ash.Changeset.ManagedRelationshipHelpers.sanitize_opts/2`, with `type:`
  shorthands expanded first).
  """
  @type manage :: %{relationship: Ash.Resource.Relationships.relationship(), opts: keyword}

  @doc """
  Finds the `manage_relationship` change consuming `argument` on the named
  action of `resource` and returns its resolved `t:manage/0` — or `:error`
  when the action doesn't exist, doesn't declare the argument, or no
  `manage_relationship` change consumes it.
  """
  @spec manage(module | map, atom, atom) :: {:ok, manage} | :error
  def manage(resource, action_name, argument) do
    with %{changes: changes} = action when is_list(changes) <-
           ResourceInfo.action(resource, action_name),
         true <- Enum.any?(action.arguments, &(&1.name == argument)),
         change_opts when is_list(change_opts) <- manage_change_opts(changes, argument),
         relationship when not is_nil(relationship) <-
           ResourceInfo.relationship(resource, change_opts[:relationship]) do
      {:ok,
       %{
         relationship: relationship,
         opts: ManagedRelationshipHelpers.sanitize_opts(relationship, normalize(change_opts))
       }}
    else
      _missing -> :error
    end
  end

  defp manage_change_opts(changes, argument) do
    Enum.find_value(changes, fn
      %{change: {Ash.Resource.Change.ManageRelationship, change_opts}} ->
        change_opts[:argument] == argument && change_opts

      _other_change ->
        nil
    end)
  end

  # The `type:` shorthand expands to its full on_lookup/on_no_match/on_match/
  # on_missing set before explicit overrides apply — matching what
  # Ash.Changeset.manage_relationship does at changeset time.
  defp normalize(change_opts) do
    manage_opts = change_opts[:opts] || []

    case manage_opts[:type] do
      nil -> manage_opts
      type -> Keyword.merge(Ash.Changeset.manage_relationship_opts(type), manage_opts)
    end
  end

  @doc """
  Infers the v1 interaction mode from sanitized manage options:

    * lookups possible (`on_lookup` not `:ignore`, e.g.
      `type: :append_and_remove`) -> `:pick_existing`
    * else creates possible (`on_no_match: :create`, e.g.
      `type: :direct_control`) -> `:create_inline`
    * else -> `:error` (update-only/ignore configurations have no v1
      rendering; rejected at compile time)
  """
  @spec mode(keyword) :: {:ok, :pick_existing | :create_inline} | :error
  def mode(sanitized_opts) do
    cond do
      ManagedRelationshipHelpers.could_lookup?(sanitized_opts) -> {:ok, :pick_existing}
      ManagedRelationshipHelpers.could_create?(sanitized_opts) -> {:ok, :create_inline}
      true -> :error
    end
  end

  @doc """
  The default create_inline sub-form fields: the accepts of the destination
  action the change creates through (`on_no_match`), minus the relationship's
  `destination_attribute` (set by Ash, never typed by the user). `nil` when
  no destination create action is resolvable.
  """
  @spec default_fields(manage) :: [atom] | nil
  def default_fields(%{relationship: relationship, opts: sanitized_opts}) do
    sanitized_opts
    |> ManagedRelationshipHelpers.on_no_match_destination_actions(relationship)
    |> List.wrap()
    |> Enum.find_value(fn
      {:destination, action_name} -> action_name
      _join_or_nil -> nil
    end)
    |> case do
      nil ->
        nil

      action_name ->
        case ResourceInfo.action(relationship.destination, action_name) do
          %{accept: accept} when is_list(accept) ->
            Enum.reject(accept, &(&1 == relationship.destination_attribute))

          _no_accepts ->
            nil
        end
    end
  end
end
