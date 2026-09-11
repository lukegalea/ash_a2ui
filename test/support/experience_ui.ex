defmodule AshA2ui.Test.Experience.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    allow_unregistered? true
  end
end

defmodule AshA2ui.Test.Experience.Task do
  @moduledoc """
  Experience v2 fixture: a query-backed table (page size 2) with a
  create/update form. `name` carries a `min_length` constraint so submitted
  blank values fail action validation with a field-tied error.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Experience.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false, constraints: [min_length: 1]
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  a2ui do
    surface_id "experience_task"

    query :default do
      search_fields [:name]
      default_sort name: :asc
      page_size 2
      max_page_size 5
    end

    component :table do
      fields [:name]
      read_action :read
      row_actions [:destroy]
      query :default
    end

    component :form do
      fields [:name]
      create_action :create
      update_action :update
    end
  end
end

defmodule AshA2ui.Test.Experience.NoUpdate do
  @moduledoc """
  Experience v2 fixture: a resource with a create action but **no** update
  action — rows must offer View but never Edit.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Experience.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy, create: :*]
  end

  a2ui do
    surface_id "experience_no_update"

    component :table do
      fields [:name]
      read_action :read
    end

    component :form do
      fields [:name]
      create_action :create
    end
  end
end

defmodule AshA2ui.Test.Experience.ReadOnly do
  @moduledoc """
  Experience v2 fixture: neither create nor update actions, and no form
  component — rows must offer View only.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Experience.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
  end

  actions do
    defaults [:read]
  end

  a2ui do
    surface_id "experience_read_only"

    component :table do
      fields [:name]
      read_action :read
    end
  end
end

defmodule AshA2ui.Test.Experience.Protected do
  @moduledoc """
  Experience v2 fixture: policy-guarded — reads/creates need an actor,
  updates additionally need `%{admin: true}` (drives the forged-event
  authorization tests).
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Experience.Domain,
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

    policy action_type(:update) do
      authorize_if actor_attribute_equals(:admin, true)
    end
  end

  a2ui do
    surface_id "experience_protected"

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
