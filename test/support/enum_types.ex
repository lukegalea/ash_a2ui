defmodule AshA2ui.Test.Severity do
  @moduledoc "Plain-atom `Ash.Type.Enum` (no explicit labels)."
  use Ash.Type.Enum, values: [:low, :medium, :very_high]
end

defmodule AshA2ui.Test.Stage do
  @moduledoc "`Ash.Type.Enum` with explicit labels."
  use Ash.Type.Enum,
    values: [
      todo: [label: "To Do"],
      in_progress: [label: "In Progress"]
    ]
end

defmodule AshA2ui.Test.EnumRecord do
  @moduledoc """
  Fixture resource for `Ash.Type.Enum`-typed attributes: they default to
  ChoicePickers whose options come from the enum module's `values/0` (labels
  from `label/1` when declared, humanized values otherwise), in forms and in
  query filter pickers alike.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :severity, AshA2ui.Test.Severity, public?: true
    attribute :stage, AshA2ui.Test.Stage, public?: true
  end

  actions do
    defaults [:read, create: :*, update: :*]
  end

  a2ui do
    surface_id "enum_records"

    query :default do
      filters [:severity]
      page_size 25
    end

    component :table do
      fields [:name, :severity, :stage]
      read_action :read
      query :default
    end

    component :form do
      fields [:name, :severity, :stage]
      create_action :create
      update_action :update
    end
  end
end
