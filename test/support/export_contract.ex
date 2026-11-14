defmodule AshA2ui.Test.ExportContract do
  @moduledoc """
  Fixture resource for table CSV exports of columns the table does not show:
  a contract with a `value` and `currency` the hub table leaves out, an
  expression calculation, a count aggregate over its lines, a `margin` only
  admins may read (a field policy), a `secret` flag the read policy hides
  and an `archived` flag the `:active` read filters out.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:active, :draft]],
      default: :draft

    attribute :value, :decimal, public?: true
    attribute :currency, :string, public?: true
    attribute :margin, :decimal, public?: true
    attribute :secret, :boolean, public?: true, default: false
    attribute :archived, :boolean, public?: true, default: false
  end

  relationships do
    has_many :lines, AshA2ui.Test.ExportContractLine,
      public?: true,
      destination_attribute: :contract_id
  end

  calculations do
    calculate :priced_name, :string, expr(name <> " (" <> currency <> ")"), public?: true
  end

  aggregates do
    count :line_count, :lines, public?: true
  end

  actions do
    defaults [:read, create: :*]

    read :active do
      filter expr(archived == false)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(secret == false)
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :margin do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end
end

defmodule AshA2ui.Test.ExportContractLine do
  @moduledoc "Fixture: a line of a `AshA2ui.Test.ExportContract`."

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
  end

  relationships do
    belongs_to :contract, AshA2ui.Test.ExportContract, public?: true
  end

  actions do
    defaults [:read, create: :*]
  end
end

defmodule AshA2ui.Test.ExportContractsUI do
  @moduledoc """
  Fixture surface for exporting columns the table does not show: the table
  renders name and status (and `currency` as a hidden field); the export
  adds an attribute (`value`, labelled by a `field` override), the hidden
  field, a calculation, an aggregate and a field-policy-guarded attribute.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.ExportContract
    surface_id "export_contracts"

    query :default do
      search_fields [:name]
      filters [:status]
      default_sort name: :asc
      page_size 2
    end

    component :table do
      fields [:name, :status, :currency]
      read_action :active
      query :default

      export do
        filename "contracts.csv"
        columns [:name, :value, :status, :currency, :priced_name, :line_count, :margin]
      end
    end

    field :currency do
      hidden true
    end

    field :value do
      label "Contract value"
    end
  end
end

defmodule AshA2ui.Test.ExportContractMarginsUI do
  @moduledoc """
  Fixture surface showing the field-policy-guarded `margin` of
  `AshA2ui.Test.ExportContract` as a table column.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.ExportContract
    surface_id "export_contract_margins"

    component :table do
      fields [:name, :margin]
      read_action :active
    end
  end
end

defmodule AshA2ui.Test.ExportContractsSelectUI do
  @moduledoc """
  Fixture surface for a column-selectable table export: the export block of
  `AshA2ui.Test.ExportContractsUI` with `column_select`, so the surface
  carries a CheckBox per export column, bound to `/export/table/columns`.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.ExportContract
    surface_id "export_contracts_select"

    component :table do
      fields [:name, :status]
      read_action :active

      export do
        filename "contracts.csv"
        columns [:name, :value, :status]
        column_select true
      end
    end
  end
end
