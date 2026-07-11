defmodule AshA2ui.Test.Article do
  @moduledoc """
  Fixture resource for calculation & aggregate columns: a public expression
  calculation (`display_title`, string concat) and a public count aggregate
  (`comment_count`, counting the `AshA2ui.Test.Comment` has_many), both
  rendered as table columns and allowlisted as sortable in the `query`.

  Also carries a module-based (non-expression) calculation
  (`shout_title`) to exercise the "not sortable" verifier path — it renders
  fine as a column but may not appear in `sortable`.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshA2ui]

  defmodule ShoutTitle do
    @moduledoc false
    use Ash.Resource.Calculation

    @impl true
    def load(_query, _opts, _context), do: [:title]

    @impl true
    def calculate(records, _opts, _context) do
      Enum.map(records, &String.upcase(&1.title || ""))
    end
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true, allow_nil?: false

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:draft, :published]],
      default: :draft
  end

  relationships do
    has_many :comments, AshA2ui.Test.Comment, public?: true
  end

  calculations do
    calculate :display_title,
              :string,
              expr(title <> " (" <> type(status, :string) <> ")"),
              public?: true

    calculate :shout_title, :string, ShoutTitle, public?: true
  end

  aggregates do
    count :comment_count, :comments, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  a2ui do
    surface_id "articles"

    query :default do
      search_fields [:title]
      sortable [:title, :comment_count, :display_title]
      default_sort title: :asc
      page_size 5
      max_page_size 10
    end

    component :table do
      fields [:title, :display_title, :shout_title, :comment_count]
      read_action :read
      row_actions [:destroy]
      query :default
    end

    component :form do
      fields [:title, :status]
      create_action :create
      update_action :update
    end
  end
end
