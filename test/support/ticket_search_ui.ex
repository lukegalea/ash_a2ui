defmodule AshA2ui.Test.TicketSearchUI do
  @moduledoc """
  Standalone UI module fixture for the searchable variants of
  `AshA2ui.Test.Ticket`'s relationship inputs: a searchable `belongs_to`
  select (`option_search` on `:author_id`) and a searchable pick_existing
  nested form (`option_search` on the `:tags` nested form).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.Ticket
    surface_id "tickets_search"

    component :table do
      fields [:subject]
      read_action :read
    end

    component :form do
      fields [:subject, :author_id]
      create_action :create
      update_action :update

      nested_form :tags do
        option_search [:name]
      end
    end

    field :author_id do
      option_search [:name, :email]
    end
  end
end
