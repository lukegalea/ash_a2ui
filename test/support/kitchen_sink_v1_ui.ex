defmodule AshA2ui.Test.KitchenSinkV1UI do
  @moduledoc """
  The v1.0 twin of `AshA2ui.Test.KitchenSink`'s surface: the same table +
  form over the same resource, but with `spec_version "1.0"` — the fixture
  every v1.0 encoder/handler/conformance test drives so v1.0 coverage spans
  the full field-type matrix (string, boolean, integer, decimal, date,
  utc_datetime, enum, timestamps with a `formatDate` function cell).
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.KitchenSink
    surface_id "kitchen_sink_v1"
    spec_version("1.0")

    component :table do
      fields [:name, :active, :count, :price, :birthday, :scheduled_at, :status, :inserted_at]
      read_action :read
      row_actions [:update, :destroy]
    end

    component :form do
      fields [:name, :active, :count, :price, :birthday, :scheduled_at, :status]
      create_action :create
      update_action :update
    end

    field :name do
      label "Name"
      widget :text_field
      order 1
    end

    field :inserted_at do
      label "Created"
      format :date
      order 99
    end

    field :updated_at do
      hidden true
    end
  end
end
