defmodule AshA2ui do
  @field %Spark.Dsl.Entity{
    name: :field,
    describe: """
    Per-field presentation overrides, shared across all components of the surface.
    """,
    examples: [
      """
      field :name do
        label "Provider Name"
        widget :text_field
      end
      """
    ],
    target: AshA2ui.Field,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the resource attribute/calculation/aggregate this field maps to."
      ],
      label: [
        type: :string,
        doc: "Human-readable label. Defaults to a humanized version of the field name."
      ],
      widget: [
        type: :atom,
        doc:
          "Widget override (e.g. `:text_field`, `:check_box`, `:choice_picker`, `:date_time_input`). Defaults via `AshA2ui.TypeMapper`."
      ],
      order: [
        type: :non_neg_integer,
        default: 0,
        doc: "Sort order of the field within components. Lower comes first."
      ],
      hidden: [
        type: :boolean,
        default: false,
        doc: "Hide this field from all components."
      ],
      format: [
        type: :atom,
        doc: "Named formatter hint (e.g. `:date`) applied when rendering values."
      ],
      relationship: [
        type: :atom,
        doc: """
        The `belongs_to` relationship this form field selects a record for. Only needed as
        an explicit override (e.g. action-argument fields); fields whose name matches a
        `belongs_to` relationship's `source_attribute` are inferred automatically.
        """
      ],
      option_label: [
        type: :atom,
        doc: """
        The destination attribute shown as the option label of a relationship select.
        Defaults to the first existing public attribute of `[:name, :title, :label,
        :username, :email]` on the destination, else its primary key.
        """
      ],
      option_value: [
        type: :atom,
        doc: """
        The destination attribute submitted as the option value of a relationship select.
        Defaults to the destination's primary key (required explicitly when that primary
        key is composite).
        """
      ],
      option_sort: [
        type: :atom,
        doc: """
        The destination attribute the options of a relationship select are sorted by
        (ascending). Defaults to the resolved `option_label`.
        """
      ],
      option_limit: [
        type: :pos_integer,
        default: 100,
        doc: """
        Maximum number of options loaded for a relationship select. Option sets larger
        than this are truncated — large sets need the roadmap's searchable selects.
        """
      ],
      source: [
        type: {:list, :atom},
        doc: """
        A relationship path (e.g. `[:user, :email]`) this table column reads its value
        through. Every step but the last must be a public relationship; the last must be
        a public attribute of the final destination. Source columns are table-only and
        not sortable.
        """
      ]
    ]
  }

  @preset %Spark.Dsl.Entity{
    name: :preset,
    describe: """
    A named, server-side composite filter the client selects by name via the
    `"preset"` query parameter — the predicates themselves never travel over
    the wire. Declare either a declarative keyword `filter` (conditions ANDed;
    `nil` means `is_nil`, a list means membership) or a dedicated
    `read_action` as an escape hatch for predicates the keyword form can't
    express.
    """,
    examples: [
      """
      preset :pending do
        filter status: :pending, deleted_at: nil
      end
      """,
      """
      preset :deleted do
        read_action :deleted
      end
      """
    ],
    target: AshA2ui.Preset,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the preset, sent by the client as the `\"preset\"` query parameter."
      ],
      filter: [
        type: :keyword_list,
        doc: """
        Keyword conditions ANDed onto the table's base query. Keys are public
        attributes or public expression calculations; `nil` values mean
        `is_nil`, list values mean membership, anything else is equality.
        """
      ],
      read_action: [
        type: :atom,
        doc: """
        A read action used instead of the table's `read_action` while this
        preset is selected — the escape hatch for predicates the keyword
        `filter` form can't express. Mutually exclusive with `filter`.
        """
      ]
    ]
  }

  @query %Spark.Dsl.Entity{
    name: :query,
    describe: """
    A named, server-enforced allowlist for search, sorting, equality filters,
    and pagination, referenced by a `:table` component via its `query` option.
    Client `"query"` actions are validated against these lists — anything not
    declared here is rejected before Ash is called.
    """,
    examples: [
      """
      query :default do
        search_fields [:subject, [:author, :email]]
        sortable [:subject, :inserted_at]
        filters [:status]
        default_sort inserted_at: :desc
        page_size 25
        max_page_size 100

        preset :pending do
          filter status: :pending
        end
      end
      """
    ],
    target: AshA2ui.Query,
    args: [:name],
    entities: [presets: [@preset]],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the query, referenced by a table component's `query` option."
      ],
      search_fields: [
        type: {:list, {:or, [:atom, {:list, :atom}]}},
        default: [],
        doc: """
        Fields searched with a case-insensitive contains, OR'd together. Each
        entry is a public string attribute (`:subject`) or a relationship path
        to one (`[:author, :email]` — every step but the last a public
        relationship, the last a public string attribute of the destination).
        Empty means search is rejected.
        """
      ],
      sortable: [
        type: {:list, :atom},
        default: [],
        doc: "Public attributes the client may sort by. Anything else is rejected."
      ],
      filters: [
        type: {:list, :atom},
        default: [],
        doc: """
        Public attributes or public expression calculations the client may
        equality-filter on. Anything else is rejected.
        """
      ],
      default_preset: [
        type: :atom,
        doc: "The preset applied when the client selects none. Must name a declared preset."
      ],
      default_sort: [
        type: {:list, {:tuple, [:atom, {:in, [:asc, :desc]}]}},
        default: [],
        doc:
          "The sort applied when the client requests none, e.g. `default_sort inserted_at: :desc`."
      ],
      page_size: [
        type: :pos_integer,
        default: 25,
        doc: "The page size used when the client requests none."
      ],
      max_page_size: [
        type: :pos_integer,
        default: 100,
        doc: "The hard upper bound client-requested page sizes are clamped to."
      ]
    ]
  }

  @component %Spark.Dsl.Entity{
    name: :component,
    describe: """
    A UI component of the surface. `:table` renders records from a read action;
    `:form` renders create/update forms. A surface may declare several `:table`
    components (sections) by giving each one a distinguishing name via the
    optional second argument, e.g. `component :table, :new_items do ... end`.
    """,
    examples: [
      """
      component :table do
        fields [:name, :inserted_at]
        read_action :read
        row_actions [:edit]
      end
      """,
      """
      component :table, :new_items do
        fields [:name]
        read_action :new_items
        row_actions [:approve]
      end
      """
    ],
    target: AshA2ui.Component,
    args: [:name, {:optional, :as}],
    schema: [
      name: [
        type: {:one_of, [:table, :form]},
        required: true,
        doc: "The kind of component. One of `:table` or `:form`."
      ],
      as: [
        type: :atom,
        doc: """
        The distinguishing name of this component on surfaces with several
        `:table` components (e.g. `component :table, :new_items`). Optional —
        a table without one is named `:table`. Names must be unique across
        the surface's components; `:form` components cannot be named.
        """
      ],
      fields: [
        type: {:list, :atom},
        doc:
          "Fields shown by this component. Omit to infer (public attributes for tables, action accepts for forms)."
      ],
      read_action: [
        type: :atom,
        doc: "The read action used to load records (tables). Defaults to the primary read."
      ],
      create_action: [
        type: :atom,
        doc: "The create action submitted by the form."
      ],
      update_action: [
        type: :atom,
        doc: "The update action submitted by the form."
      ],
      row_actions: [
        type: {:list, :atom},
        default: [],
        doc: "Actions rendered as per-row buttons (tables)."
      ],
      query: [
        type: :atom,
        doc:
          "Name of a `query` entity providing server-enforced search/sort/filter/pagination (tables)."
      ]
    ]
  }

  @action %Spark.Dsl.Entity{
    name: :action,
    describe: """
    Per-action metadata: refresh targets, argument prompts, and per-row
    visibility conditions.
    """,
    examples: [
      """
      action :approve do
        refreshes [:new_items]
        visible_when status: :pending
      end
      """,
      """
      action :decline do
        prompt_fields [:notes]
        prompt_title "Decline referral"
      end
      """
    ],
    target: AshA2ui.Action,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc:
          "The Ash action this metadata applies to (a row action, or the form's create/update action)."
      ],
      refreshes: [
        type: {:list, :atom},
        doc: """
        The table components refreshed after this action succeeds, by
        component name (`refreshes [:new_items]`; the unnamed table is
        `:table`). `[]` refreshes no table. Omitted (and for actions without
        an `action` entity) every table is refreshed (the default).
        """
      ],
      prompt_fields: [
        type: {:list, :atom},
        default: [],
        doc: """
        Arguments/accepts of the Ash action collected from the user in a
        per-row Modal prompt before the action is invoked (row actions only).
        Clicking the row button opens the Modal instead of invoking directly;
        its confirm button sends `invoke` with a `"values"` map.
        """
      ],
      prompt_title: [
        type: :string,
        doc: """
        Heading shown inside the prompt Modal. Defaults to the humanized
        action name.
        """
      ],
      visible_when: [
        type: :keyword_list,
        default: [],
        doc: """
        Per-record conditions gating this row action, ANDed together
        (`visible_when status: :pending`). Keys are public attributes or
        public expression calculations; `nil` values mean `is_nil`, list
        values mean membership, anything else is equality. Enforced
        server-side on every invoke; rendering hides the button per row.
        """
      ]
    ]
  }

  @a2ui %Spark.Dsl.Section{
    name: :a2ui,
    describe: """
    Declare an A2UI surface for this resource (or, in a standalone UI module,
    for the resource named by `for_resource`).
    """,
    examples: [
      """
      a2ui do
        surface_id "promotions_providers"

        component :table do
          fields [:name, :inserted_at]
          read_action :read
        end

        component :form do
          fields [:name]
          create_action :create
          update_action :update
        end

        field :name do
          label "Provider Name"
        end
      end
      """
    ],
    schema: [
      surface_id: [
        type: :string,
        doc:
          "Unique id of the A2UI surface. Defaults to the underscored short name of the resource."
      ],
      for_resource: [
        type: {:behaviour, Ash.Resource},
        doc:
          "The Ash resource this surface renders. Only used (and required) in standalone UI modules (`use AshA2ui.Standalone`)."
      ],
      add_render_action?: [
        type: :boolean,
        default: true,
        doc:
          "Whether to automatically add a generic `render_a2ui` action returning the surface's A2UI messages. Ignored in standalone UI modules."
      ]
    ],
    entities: [
      @query,
      @component,
      @field,
      @action
    ]
  }

  @sections [@a2ui]

  @transformers [
    AshA2ui.Transformers.InferFields,
    AshA2ui.Transformers.AddRenderAction
  ]

  @verifiers [
    AshA2ui.Verifiers.VerifyComponents,
    AshA2ui.Verifiers.VerifyFields,
    AshA2ui.Verifiers.VerifyActions,
    AshA2ui.Verifiers.VerifyQueries,
    AshA2ui.Verifiers.VerifyRelationships
  ]

  @moduledoc """
  A Spark DSL extension that declares an A2UI (Agent to UI) surface for an Ash
  resource, from which `AshA2ui.Info.build_surface/2` generates A2UI v0.9.1
  protocol messages.

  Use it directly on a resource:

      use Ash.Resource, extensions: [AshA2ui]

  or in a standalone UI module (see `AshA2ui.Standalone`).
  """

  use Spark.Dsl.Extension,
    sections: @sections,
    transformers: @transformers,
    verifiers: @verifiers
end
