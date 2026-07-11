defmodule AshA2ui.Test.Referral do
  @moduledoc """
  Fixture resource for the Wave 4 feature set, modeled on a real
  admin-dashboard screen:

    * relationship-path search (`[:referrer, :email]` / `[:referred, :name]`
      through two `belongs_to` relationships),
    * an expression-calculation filter (`status_label`) and sort key
      (`status_priority`, a multi-key `default_sort` with a calc),
    * named filter presets — declarative keyword filters (`:active`,
      `:pending`, `:closed`) plus a `read_action` escape hatch (`:deleted`) —
      with a `default_preset`,
    * a prompt-enabled row action (`:decline` collects a required `notes`
      argument via a Modal),
    * `visible_when` conditional row actions (`:approve` only on pending,
      undeleted records; `:decline` on pending/approved).
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

    attribute :code, :string, public?: true, allow_nil?: false

    attribute :status, :atom,
      public?: true,
      constraints: [one_of: [:pending, :approved, :declined]],
      default: :pending

    attribute :notes, :string, public?: true
    attribute :deleted_at, :utc_datetime_usec, public?: true
  end

  relationships do
    belongs_to :referrer, AshA2ui.Test.Author, public?: true
    belongs_to :referred, AshA2ui.Test.Author, public?: true
  end

  calculations do
    calculate :status_label, :string, expr(type(status, :string) <> "!"), public?: true

    calculate :status_priority,
              :integer,
              expr(if status == :pending, do: 0, else: if(status == :approved, do: 1, else: 2)),
              public?: true
  end

  actions do
    defaults [:read, create: :*]

    read :deleted do
      filter expr(not is_nil(deleted_at))
    end

    update :approve do
      accept []
      change set_attribute(:status, :approved)
    end

    update :decline do
      accept []
      argument :notes, :string, allow_nil?: false
      change set_attribute(:status, :declined)
      change set_attribute(:notes, arg(:notes))
    end

    update :soft_delete do
      accept []
      change set_attribute(:deleted_at, &DateTime.utc_now/0)
    end
  end

  a2ui do
    surface_id "referrals"

    query :default do
      search_fields [:code, [:referrer, :email], [:referred, :name]]
      sortable [:code, :status_priority]
      filters [:status, :status_label]
      default_sort status_priority: :asc, code: :asc
      page_size 5
      max_page_size 10
      default_preset :active

      preset :active do
        filter deleted_at: nil
      end

      preset :pending do
        filter status: :pending, deleted_at: nil
      end

      preset :closed do
        filter status: [:approved, :declined], deleted_at: nil
      end

      preset :deleted do
        read_action :deleted
      end
    end

    component :table do
      fields [:code, :status, :status_label]
      read_action :read
      row_actions [:approve, :decline, :soft_delete]
      query :default
    end

    action :approve do
      visible_when status: :pending, deleted_at: nil
    end

    action :decline do
      prompt_fields [:notes]
      prompt_title "Decline referral"
      visible_when status: [:pending, :approved]
    end
  end
end
