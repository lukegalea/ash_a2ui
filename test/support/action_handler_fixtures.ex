defmodule AshA2ui.ActionHandlerTest.TestDomain do
  @moduledoc """
  Fixture domain for the action-handler suites (`action_handler_test.exs`,
  `relationship_test.exs`, `v1_0_action_handler_test.exs`).

  Lives in test/support rather than inside a test file on purpose: test
  files are compiled per-run in an unspecified order, and a test module
  defined in one `.exs` is not visible to another that loads first — which
  used to crash `relationship_test.exs` with "not a Spark DSL module" the
  moment it ran before `action_handler_test.exs`. Support files are compiled
  by `elixirc_paths` before any test runs, so order cannot matter.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    allow_unregistered? true
  end
end

defmodule AshA2ui.ActionHandlerTest.Protected do
  @moduledoc false
  use Ash.Resource,
    domain: AshA2ui.ActionHandlerTest.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end

  a2ui do
    surface_id "protected"

    component :table do
      fields [:name]
      read_action :read
      row_actions [:destroy]
    end

    component :form do
      fields [:name]
      create_action :create
      update_action :update
    end
  end
end

defmodule AshA2ui.ActionHandlerTest.Gadget do
  @moduledoc false
  use Ash.Resource,
    domain: AshA2ui.ActionHandlerTest.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    action :generate_secret, :map do
      argument :record_id, :uuid, allow_nil?: true

      run fn input, _context ->
        {:ok, %{secret: "s3cr3t", record_id: input.arguments[:record_id]}}
      end
    end
  end

  a2ui do
    surface_id "gadget"

    component :table do
      fields [:name]
      read_action :read
      row_actions [:generate_secret, :destroy]
    end
  end
end

defmodule AshA2ui.ActionHandlerTest.CheckInFacade do
  @moduledoc """
  Stand-in for a host engine facade behind a `via` row action: the delegate
  receives the dispatch context plus the entity's declared extra args,
  completes the work through the resource action itself, and returns the
  same shapes a direct invocation does.

  The record's name picks the behavior (one fixture surface drives all the
  delegation cases):

    * anything else — the engine-facade happy path: run the resource action
      under the dispatching actor and return its result
    * "stale" — return `{:ok, :accepted}` without writing (proves the direct
      dispatch never runs for a via action)
    * "completed" — return an Ash validation error on :status
    * "locked" — return `Ash.Error.Forbidden`
  """

  alias Ash.Error.Changes.InvalidArgument

  def complete(%{record: %{name: "stale"}}, _source), do: {:ok, :accepted}

  def complete(%{record: %{name: "completed"}}, _source) do
    {:error,
     %Ash.Error.Invalid{
       errors: [
         InvalidArgument.exception(
           field: :status,
           message: "task already completed"
         )
       ]
     }}
  end

  def complete(%{record: %{name: "locked"}}, _source), do: {:error, %Ash.Error.Forbidden{}}

  def complete(%{record: record, actor: actor} = context, source) do
    Process.put({__MODULE__, :last_call}, %{context: context, source: source})

    record
    |> Ash.Changeset.for_update(:check_in, %{}, actor: actor)
    |> Ash.update()
  end
end

defmodule AshA2ui.ActionHandlerTest.Ticket do
  @moduledoc false
  use Ash.Resource,
    domain: AshA2ui.ActionHandlerTest.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :status, :string, public?: true, default: "open"
  end

  actions do
    defaults [:read, :destroy, create: :*]

    update :check_in do
      accept []
      change set_attribute(:status, "checked_in")
    end
  end

  a2ui do
    surface_id "ticket"

    component :table do
      fields [:name, :status]
      read_action :read
      row_actions [:check_in]
    end

    action :check_in do
      via {AshA2ui.ActionHandlerTest.CheckInFacade, :complete, [:board]}
    end
  end
end

defmodule AshA2ui.ActionHandlerTest.Widget do
  @moduledoc false
  use Ash.Resource,
    domain: AshA2ui.ActionHandlerTest.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true
    attribute :touched, :boolean, public?: true, default: false
  end

  actions do
    defaults [:read, :destroy, create: :*]

    update :update do
      primary? true
      accept [:name]
    end

    update :touch do
      accept []
      change set_attribute(:touched, true)
    end
  end

  a2ui do
    surface_id "widget"

    component :table do
      fields [:name, :touched]
      read_action :read
      row_actions [:touch, :destroy]
    end

    component :form do
      fields [:name]
      create_action :create
      update_action :update
    end
  end
end
