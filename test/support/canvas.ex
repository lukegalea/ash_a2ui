defmodule Canvas.Test.Blog do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Canvas.Test.Post
    resource Canvas.Test.Page
    resource Canvas.Test.Task
  end
end

defmodule Canvas.Test.Catalog do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Canvas.Test.Product
  end
end

defmodule Canvas.Test.Post do
  @moduledoc """
  Canvas fixture: a post with two relationships — `:product` (whose
  destination is registered in the second fixture domain, so the graph
  carries a cross-domain relationship edge) and `:tag` (whose destination
  exists but is NOT in the canvas registry, so the graph must carry no edge
  for it). The `:publish_summary` generic action exercises `:act`
  capabilities.
  """

  use Ash.Resource,
    domain: Canvas.Test.Blog,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
  end

  relationships do
    belongs_to :product, Canvas.Test.Product, public?: true

    # Registered elsewhere in the test suite (AshA2ui.Test.Domain), but not
    # in `Canvas.Test.Registry` — from the canvas's point of view this
    # destination does not exist.
    belongs_to :tag, AshA2ui.Test.Minimal, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    action :publish_summary, :string do
      run fn _input, _context -> {:ok, "published"} end
    end
  end
end

defmodule Canvas.Test.Product do
  @moduledoc false

  use Ash.Resource,
    domain: Canvas.Test.Catalog,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
  end

  actions do
    defaults [:read, :create]
  end
end

defmodule Canvas.Test.Page do
  @moduledoc """
  Canvas fixture: a policy-gated resource. Reads are open; creates and
  updates require an actor with `admin: true` — the two-actor setup the
  record-capability tests use (`%{admin: true}` may edit, `%{admin: false}`
  may not).
  """

  use Ash.Resource,
    domain: Canvas.Test.Blog,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if actor_attribute_equals(:admin, true)
    end

    policy action_type(:update) do
      authorize_if actor_attribute_equals(:admin, true)
    end
  end
end

defmodule Canvas.Test.Task do
  @moduledoc """
  Canvas fixture: an `AshStateMachine` resource, so the graph carries the
  state-machine sub-entity (states as semantic content).
  """

  use Ash.Resource,
    domain: Canvas.Test.Blog,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  ets do
    private? true
  end

  state_machine do
    initial_states([:pending])
    default_initial_state(:pending)

    transitions do
      transition(:start, from: :pending, to: :running)
      transition(:complete, from: :running, to: :done)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :summary, :string, public?: true, allow_nil?: false
  end

  actions do
    defaults [:read, create: :*]

    update :start do
      change transition_state(:running)
    end

    update :complete do
      change transition_state(:done)
    end
  end
end

defmodule Canvas.Test.Registry do
  @moduledoc """
  The canvas registry over the canvas fixtures: two domains (one resource
  of `Canvas.Test.Blog` relates into `Canvas.Test.Catalog`), with label
  overrides at all three levels — application, resource module, and record
  struct.
  """

  @behaviour AshA2ui.Canvas.Registry

  @impl true
  def domains, do: [Canvas.Test.Blog, Canvas.Test.Catalog]

  @impl true
  def label(:application), do: "Canvas Test App"
  def label(Canvas.Test.Post), do: "Posts"
  def label(%Canvas.Test.Post{} = post), do: post.name
  def label(_other), do: nil
end
