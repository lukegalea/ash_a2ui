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
        Maximum number of options loaded for a relationship select (and returned per
        `option_search` request). Non-searchable option sets larger than this are
        truncated — declare `option_search` for genuinely large sets.
        """
      ],
      option_search: [
        type: {:list, :atom},
        default: [],
        doc: """
        Public string attributes of the destination searched (case-insensitive
        contains, OR'd) by the `"option_search"` client action. Non-empty turns the
        relationship select into a searchable select: a search input plus a result
        list refreshed through `/options/<field>`, instead of a static ChoicePicker.
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

  @context %Spark.Dsl.Entity{
    name: :context,
    describe: """
    A named, surface-level record selection ("pick a user") whose selected
    record scopes other sections: tables reference it via `context_filter`,
    dependent contexts via `depends_on`, and `:detail` components render the
    selected record. Selection state lives at the reserved `/context/<name>`
    data-model path, option lists at `/options/<name>`, and the client
    interacts through the `"context_search"` / `"context_select"` /
    `"context_clear"` actions — the client only ever sends a record id, and
    every selection round-trips through an authorized read (dependency
    filters included).
    """,
    examples: [
      """
      context :user do
        resource MyApp.Accounts.User
        option_label :email
        option_search [:email, :name]
      end
      """,
      """
      context :practice do
        resource MyApp.Practices.Practice
        option_label :name
        depends_on :user
        depends_on_path [:memberships, :user_id]
        auto_select_single true
      end
      """
    ],
    target: AshA2ui.Context,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: """
        The name of the context: the `<name>` segment of the reserved
        `/context/<name>` and `/options/<name>` data-model paths, and how
        `context_filter` / `depends_on` / `:detail` components reference it.
        Must be unique across the surface's contexts, relationship-select
        fields and nested-form arguments (they share the `/options`
        namespace).
        """
      ],
      resource: [
        type: {:behaviour, Ash.Resource},
        required: true,
        doc: "The Ash resource whose records this context selects."
      ],
      label: [
        type: :string,
        doc: "Heading shown above the picker. Defaults to the humanized context name."
      ],
      option_label: [
        type: :atom,
        doc: """
        The attribute shown as the option/selection label. Defaults like a
        relationship select's `option_label` (first existing public attribute
        of `[:name, :title, :label, :username, :email]`, else the primary
        key).
        """
      ],
      option_value: [
        type: :atom,
        doc: """
        The attribute submitted as the selected value. Defaults to the
        resource's primary key (required explicitly when composite).
        """
      ],
      option_sort: [
        type: :atom,
        doc: "The attribute options are sorted by (ascending). Defaults to `option_label`."
      ],
      option_limit: [
        type: :pos_integer,
        default: 100,
        doc: "Maximum number of options loaded (and returned per `context_search`)."
      ],
      option_search: [
        type: {:list, :atom},
        default: [],
        doc: """
        Public string attributes of the resource searched (case-insensitive
        contains, OR'd) by the `"context_search"` client action. Non-empty
        adds a search input to the emitted picker.
        """
      ],
      depends_on: [
        type: :atom,
        doc: """
        The context this one depends on: its options are filtered by the
        parent's selected value (through `depends_on_path`), its options are
        empty while the parent is unselected, and its selection is cleared
        whenever the parent changes.
        """
      ],
      depends_on_path: [
        type: {:list, :atom},
        doc: """
        The relationship path on this context's resource whose terminal
        attribute must equal the parent context's selected value, e.g.
        `[:memberships, :user_id]` — every step but the last a public
        relationship, the last a public attribute of the final destination
        (to-many paths get `exists` semantics). Required with `depends_on`.
        """
      ],
      auto_select_single: [
        type: :boolean,
        default: false,
        doc: """
        Automatically select this context when a parent selection leaves it
        exactly one option (dependent contexts only).
        """
      ],
      picker: [
        type: :boolean,
        default: true,
        doc: """
        Whether to emit a picker section for this context. Set `false` for
        contexts selected only through a table's `select_context` row button
        (master/detail) — no options are loaded or rendered.
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
      range_filters: [
        type: {:list, :atom},
        default: [],
        doc: """
        Public attributes (or expression-backed public calculations) of
        orderable types (date/datetime/numeric) the client may range-filter
        on through `/query/ranges/<field>` (`{"from", "to"}`, each optional).
        Anything else is rejected.
        """
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

  @nested_form %Spark.Dsl.Entity{
    name: :nested_form,
    describe: """
    A nested relationship form inside a `:form` component, named by the
    **action argument** a `manage_relationship` change consumes on the form's
    create/update action. The interaction mode is inferred from that change's
    options (via `Ash.Changeset.ManagedRelationshipHelpers`): lookups
    (`on_lookup`, e.g. `type: :append_and_remove`) render as **pick_existing**
    (a select adding existing records, current rows with remove buttons);
    otherwise creates (`on_no_match: :create`, e.g. `type: :direct_control`)
    render as **create_inline** (sub-form rows appended to the argument's
    array of maps).
    """,
    examples: [
      """
      nested_form :notes do
        fields [:body, :rating]
      end
      """,
      """
      nested_form :tags do
        option_search [:name]
      end
      """
    ],
    target: AshA2ui.NestedForm,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: """
        The action argument this nested form edits. Must be consumed by a
        `manage_relationship` change on every create/update action the form
        submits (verified at compile time).
        """
      ],
      label: [
        type: :string,
        doc: "Heading shown above the nested rows. Defaults to the humanized argument name."
      ],
      fields: [
        type: {:list, :atom},
        doc: """
        Destination attributes rendered as sub-form inputs (create_inline
        mode only). Omit to infer from the destination action the
        `manage_relationship` change creates through, minus the relationship's
        destination attribute.
        """
      ],
      option_label: [
        type: :atom,
        doc: """
        The destination attribute shown as the label of pick_existing options
        and rows. Defaults like the `field` entity's `option_label`.
        """
      ],
      option_value: [
        type: :atom,
        doc: """
        The destination attribute submitted as the pick_existing value.
        Defaults to the destination's primary key (required explicitly when
        composite).
        """
      ],
      option_sort: [
        type: :atom,
        doc: """
        The destination attribute pick_existing options are sorted by
        (ascending). Defaults to the resolved `option_label`.
        """
      ],
      option_limit: [
        type: :pos_integer,
        default: 100,
        doc: """
        Maximum number of pick_existing options loaded (and returned per
        `option_search` request).
        """
      ],
      option_search: [
        type: {:list, :atom},
        default: [],
        doc: """
        Public string attributes of the destination searched (case-insensitive
        contains, OR'd) by the `"option_search"` client action. Non-empty
        replaces the pick_existing ChoicePicker with a search input plus a
        result list refreshed through `/options/<argument>`.
        """
      ]
    ]
  }

  @group %Spark.Dsl.Entity{
    name: :group,
    describe: """
    A labeled section of form fields laid out in an N-column grid, declared
    inside a `:form` component. Grouped fields render inside the section (in
    the group's declaration order, chunked into rows of `columns`); ungrouped
    fields keep rendering individually. A group renders at the position of
    its first member in the form's field order.
    """,
    examples: [
      """
      group :scheduling do
        label "Scheduling"
        columns 2
        fields [:trial_days, :expires_at]
      end
      """
    ],
    target: AshA2ui.Group,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the group. Group names must be unique within the form."
      ],
      label: [
        type: :string,
        doc: "Heading shown above the group. Defaults to the humanized group name."
      ],
      columns: [
        type: :pos_integer,
        default: 1,
        doc: """
        Number of grid columns the group's fields are laid out in. Fields are
        chunked into rows of this many equal-weight columns, in the group's
        declaration order; the last row is padded with empty spacer columns.
        """
      ],
      fields: [
        type: {:list, :atom},
        required: true,
        doc: """
        The form fields this group renders. Every entry must be one of the
        form component's fields, and no field may belong to more than one
        group (verified at compile time).
        """
      ]
    ]
  }

  @row_layout %Spark.Dsl.Entity{
    name: :row_layout,
    describe: """
    Card-style record layout for a `:table` component. Each record renders as
    a `Card` with a header row — the `title` field (with the row's actions
    alongside, and the `badge` field's display text when declared) — above an
    N-column grid of caption-labeled `meta` values. Without a `row_layout`,
    records keep rendering as flat rows of cells.
    """,
    examples: [
      """
      row_layout do
        title :name
        badge :is_active
        badge_text true: "Active", false: "Inactive"
        meta [:slug, :referral_type, :trial_days]
        columns 3
      end
      """
    ],
    target: AshA2ui.RowLayout,
    schema: [
      title: [
        type: :atom,
        required: true,
        doc: "The field rendered as the card's heading. Must be one of the table's fields."
      ],
      badge: [
        type: :atom,
        doc: """
        A field rendered as a status badge in the card header. Its display
        text is served per row at the reserved `_badge_<field>` row key:
        the `badge_text` mapping when the value matches, else the humanized
        value.
        """
      ],
      badge_text: [
        type: :keyword_list,
        default: [],
        doc: """
        Display text per badge value, matched against atom (including
        boolean) values — e.g. `badge_text true: "Active", false: "Inactive"`.
        Unmatched values fall back to the humanized value.
        """
      ],
      meta: [
        type: {:list, :atom},
        doc: """
        The fields rendered in the card's labeled metadata grid, in order.
        Defaults to the table's fields minus `title` and `badge`.
        """
      ],
      columns: [
        type: :pos_integer,
        default: 2,
        doc: """
        Number of grid columns the metadata values are laid out in. Values
        are chunked into rows of this many equal-weight columns; the last
        row is padded with empty spacer columns.
        """
      ]
    ]
  }

  @component %Spark.Dsl.Entity{
    name: :component,
    describe: """
    A UI component of the surface. `:table` renders records from a read action;
    `:form` renders create/update forms; `:detail` renders the record selected
    into a `context` as a read-only field grid. A surface may declare several
    `:table` (or `:detail`) components (sections) by giving each one a
    distinguishing name via the optional second argument, e.g.
    `component :table, :new_items do ... end`.
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
    entities: [nested_forms: [@nested_form], groups: [@group], row_layout: [@row_layout]],
    singleton_entity_keys: [:row_layout],
    schema: [
      name: [
        type: {:one_of, [:table, :form, :detail]},
        required: true,
        doc: "The kind of component. One of `:table`, `:form` or `:detail`."
      ],
      as: [
        type: :atom,
        doc: """
        The distinguishing name of this component on surfaces with several
        `:table` (or `:detail`) components (e.g.
        `component :table, :new_items`). Optional — an unnamed component is
        named by its kind. Names must be unique across the surface's
        components; `:form` components cannot be named.
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
      ],
      context_filter: [
        type: :keyword_list,
        default: [],
        doc: """
        Context scoping for a `:table`: keys are public attributes of the
        table's resource, values are declared context names
        (`context_filter user_id: :user`). Each context with a selected value
        ANDs `attribute == selected value` onto the table's reads; unselected
        contexts contribute nothing.
        """
      ],
      require_context: [
        type: {:list, :atom},
        default: [],
        doc: """
        Context names (a subset of this table's `context_filter` contexts) of
        which **at least one** must be selected before the table reads —
        otherwise it renders no records (and no read is executed).
        """
      ],
      select_context: [
        type: :atom,
        doc: """
        A declared context (over the same resource as this table) the table's
        per-row Select button selects into — the master/detail pattern: the
        button sends `"context_select"` with the row's record id instead of
        `"select_row"`.
        """
      ],
      context: [
        type: :atom,
        doc: """
        The declared context a `:detail` component renders: its selected
        record's fields are written to `/detail/<context>` and displayed as a
        read-only label/value grid. Required on `:detail` components.
        """
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
      @context,
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
    AshA2ui.Verifiers.VerifyLayouts,
    AshA2ui.Verifiers.VerifyContexts,
    AshA2ui.Verifiers.VerifyFields,
    AshA2ui.Verifiers.VerifyActions,
    AshA2ui.Verifiers.VerifyQueries,
    AshA2ui.Verifiers.VerifyRelationships,
    AshA2ui.Verifiers.VerifyNestedForms
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
