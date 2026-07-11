defmodule AshA2ui.Test.AppointmentsUI do
  @moduledoc """
  Standalone UI fixture for surface contexts — the visits-shaped stress test:

    * `:owner` — a searchable root context,
    * `:clinic` — a dependent context (options filtered by the selected
      owner through `[:memberships, :owner_id]`), auto-selected when the
      owner has exactly one clinic,
    * `:appointment` — a pickerless context selected by the table's
      `select_context` row button (master/detail),
    * the appointments table scoped by owner + clinic (`context_filter`,
      at least one required via `require_context`), with a query carrying a
      `range_filters [:scheduled_for]` allowlist,
    * `:detail` components rendering the selected owner and appointment.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Appointment
    surface_id "appointments"

    context :owner do
      resource AshA2ui.Test.Owner
      option_label :email
      option_search [:email, :name]
      option_limit 10
    end

    context :clinic do
      resource AshA2ui.Test.Clinic
      option_label :name
      depends_on(:owner)
      depends_on_path([:memberships, :owner_id])
      auto_select_single(true)
    end

    context :appointment do
      resource AshA2ui.Test.Appointment
      option_label :title
      picker(false)
    end

    query :default do
      search_fields [:title]
      sortable [:scheduled_for]
      range_filters [:scheduled_for]
      default_sort scheduled_for: :desc
      page_size 5
      max_page_size 10
    end

    component :detail, :owner_card do
      context :owner
      fields [:name, :email]
    end

    component :table do
      fields [:title, :status, :scheduled_for]
      read_action :read
      query :default
      context_filter owner_id: :owner, clinic_id: :clinic
      require_context [:owner, :clinic]
      select_context :appointment
    end

    component :detail, :appointment_detail do
      context :appointment
      fields [:title, :status, :scheduled_for]
    end
  end
end
