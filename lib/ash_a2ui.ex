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
      ]
    ]
  }

  @component %Spark.Dsl.Entity{
    name: :component,
    describe: """
    A UI component of the surface. `:table` renders records from a read action;
    `:form` renders create/update forms.
    """,
    examples: [
      """
      component :table do
        fields [:name, :inserted_at]
        read_action :read
        row_actions [:edit]
      end
      """
    ],
    target: AshA2ui.Component,
    args: [:name],
    schema: [
      name: [
        type: {:one_of, [:table, :form]},
        required: true,
        doc: "The kind of component. One of `:table` or `:form`."
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
      @component,
      @field
    ]
  }

  @sections [@a2ui]

  @transformers [
    AshA2ui.Transformers.InferFields,
    AshA2ui.Transformers.AddRenderAction
  ]

  @verifiers [
    AshA2ui.Verifiers.VerifyFields,
    AshA2ui.Verifiers.VerifyActions
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
