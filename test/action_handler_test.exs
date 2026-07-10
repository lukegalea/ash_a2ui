defmodule AshA2ui.ActionHandlerTest.TestDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    allow_unregistered? true
  end
end

defmodule AshA2ui.ActionHandlerTest.Protected do
  @moduledoc false
  use Ash.Resource,
    domain: AshA2ui.ActionHandlerTest.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end

  a2ui do
    surface_id "protected"

    component :table do
      fields [:name]
      read_action :read
      row_actions [:destroy]
    end

    component :form do
      fields [:name]
      create_action :create
      update_action :update
    end
  end
end

defmodule AshA2ui.ActionHandlerTest.Gadget do
  @moduledoc false
  use Ash.Resource,
    domain: AshA2ui.ActionHandlerTest.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshA2ui]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    action :generate_secret, :map do
      argument :record_id, :uuid, allow_nil?: true

      run fn input, _context ->
        {:ok, %{secret: "s3cr3t", record_id: input.arguments[:record_id]}}
      end
    end
  end

  a2ui do
    surface_id "gadget"

    component :table do
      fields [:name]
      read_action :read
      row_actions [:generate_secret, :destroy]
    end
  end
end

defmodule AshA2ui.ActionHandlerTest do
  @moduledoc """
  Round-trip tests for `AshA2ui.ActionHandler.handle/3` against the frozen
  cross-track wire contract: client `action` envelopes in, schema-valid
  `updateDataModel` follow-ups out.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler
  alias AshA2ui.ActionHandlerTest.{Gadget, Protected}
  alias AshA2ui.Test.{KitchenSink, Minimal, MinimalUI}

  @actor %{id: "test-actor"}

  defp envelope(name, surface_id, context) do
    %{
      "version" => "v0.9.1",
      "action" => %{
        "name" => name,
        "surfaceId" => surface_id,
        "sourceComponentId" => "test_component",
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
        "context" => context
      }
    }
  end

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _ -> nil
    end)
  end

  defp paths(messages) do
    Enum.map(messages, & &1["updateDataModel"]["path"])
  end

  defp assert_all_valid(messages) do
    Enum.each(messages, &assert_valid_server_message/1)
    messages
  end

  describe "submit_form (create)" do
    test "creates a record and returns schema-valid refresh messages" do
      env =
        envelope("submit_form", "kitchen_sink", %{
          "values" => %{"name" => "Widget", "count" => 2}
        })

      assert_valid_client_message(env)

      assert {:ok, messages} = ActionHandler.handle(KitchenSink, env)
      assert_all_valid(messages)

      assert [record] = Ash.read!(KitchenSink, authorize?: false)
      assert record.name == "Widget"
      assert record.count == 2

      assert [row] = value_at(messages, "/records")
      assert row["id"] == record.id
      assert row["name"] == "Widget"
      assert row["count"] == 2

      assert value_at(messages, "/form") == %{}
      assert value_at(messages, "/errors") == %{}
      assert value_at(messages, "/ui/status") =~ ~r/creat/i
    end

    test "ignores unknown keys in values instead of failing" do
      env =
        envelope("submit_form", "kitchen_sink", %{
          "values" => %{"name" => "Lax", "bogus_key" => "ignored"}
        })

      assert {:ok, _messages} = ActionHandler.handle(KitchenSink, env)
      assert [%{name: "Lax"}] = Ash.read!(KitchenSink, authorize?: false)
    end
  end

  describe "submit_form (update)" do
    test "updates the record identified by recordId" do
      record = Ash.create!(KitchenSink, %{name: "Before"}, authorize?: false)

      env =
        envelope("submit_form", "kitchen_sink", %{
          "values" => %{"name" => "After"},
          "recordId" => record.id
        })

      assert {:ok, messages} = ActionHandler.handle(KitchenSink, env)
      assert_all_valid(messages)

      assert Ash.get!(KitchenSink, record.id, authorize?: false).name == "After"
      assert [%{"name" => "After"}] = value_at(messages, "/records")
      assert value_at(messages, "/ui/status") =~ ~r/updat/i
    end
  end

  describe "submit_form (validation errors)" do
    test "maps a missing required field to /errors/<field> and does not create the record" do
      env = envelope("submit_form", "kitchen_sink", %{"values" => %{}})

      assert {:error, messages} = ActionHandler.handle(KitchenSink, env)
      assert_all_valid(messages)

      assert value_at(messages, "/errors/name") =~ "required"
      assert is_binary(value_at(messages, "/ui/status"))
      assert Ash.read!(KitchenSink, authorize?: false) == []
    end
  end

  describe "invoke" do
    test "invokes a destroy action listed in row_actions" do
      record = Ash.create!(KitchenSink, %{name: "Doomed"}, authorize?: false)

      env =
        envelope("invoke", "kitchen_sink", %{
          "action" => "destroy",
          "recordId" => record.id
        })

      assert {:ok, messages} = ActionHandler.handle(KitchenSink, env)
      assert_all_valid(messages)

      assert Ash.read!(KitchenSink, authorize?: false) == []
      assert value_at(messages, "/records") == []
    end

    test "rejects an action that is not listed in row_actions" do
      record = Ash.create!(KitchenSink, %{name: "Safe"}, authorize?: false)

      env =
        envelope("invoke", "kitchen_sink", %{
          "action" => "create",
          "recordId" => record.id
        })

      assert {:error, messages} = ActionHandler.handle(KitchenSink, env)
      assert_all_valid(messages)

      assert value_at(messages, "/ui/status") =~ "not allowed"
      assert length(Ash.read!(KitchenSink, authorize?: false)) == 1
    end

    test "merges a generic action's map result under /ui/action_result" do
      record = Ash.create!(Gadget, %{name: "G"}, authorize?: false)

      env =
        envelope("invoke", "gadget", %{
          "action" => "generate_secret",
          "recordId" => record.id
        })

      assert {:ok, messages} = ActionHandler.handle(Gadget, env)
      assert_all_valid(messages)

      result = value_at(messages, "/ui/action_result")
      assert result["secret"] == "s3cr3t"
      assert result["record_id"] == record.id

      # the regular refresh messages still accompany the action result
      assert "/records" in paths(messages)
      assert value_at(messages, "/ui/status") =~ "generate_secret"
    end
  end

  describe "select_row" do
    test "populates /form with the selected record's values" do
      record = Ash.create!(KitchenSink, %{name: "Pick", count: 5}, authorize?: false)

      env = envelope("select_row", "kitchen_sink", %{"recordId" => record.id})

      assert {:ok, [message]} = ActionHandler.handle(KitchenSink, env)
      assert_valid_server_message(message)

      form = value_at([message], "/form")
      assert form["id"] == record.id
      assert form["name"] == "Pick"
      assert form["count"] == 5
    end

    test "missing recordId is treated as malformed" do
      env = envelope("select_row", "kitchen_sink", %{})

      assert {:error, messages} = ActionHandler.handle(KitchenSink, env)
      assert_all_valid(messages)
      assert value_at(messages, "/ui/status") =~ "recordId"
    end
  end

  describe "envelope parsing" do
    test "accepts a bare inner action map" do
      bare = %{"name" => "submit_form", "context" => %{"values" => %{"name" => "Bare"}}}

      assert {:ok, messages} = ActionHandler.handle(KitchenSink, bare)
      assert_all_valid(messages)
      assert [%{name: "Bare"}] = Ash.read!(KitchenSink, authorize?: false)
    end

    test "unknown action name returns an /ui/status error message" do
      env = envelope("explode", "kitchen_sink", %{})

      assert {:error, [message]} = ActionHandler.handle(KitchenSink, env)
      assert_valid_server_message(message)
      assert value_at([message], "/ui/status") =~ ~s(Unknown action "explode")
    end

    test "malformed message returns an /ui/status error message" do
      assert {:error, [message]} = ActionHandler.handle(KitchenSink, %{"wat" => true})
      assert_valid_server_message(message)
      assert value_at([message], "/ui/status") =~ "Malformed"
    end
  end

  describe "authorization" do
    test "Forbidden maps to a not-authorized /ui/status without field errors" do
      env = envelope("submit_form", "protected", %{"values" => %{"name" => "Nope"}})

      assert {:error, messages} = ActionHandler.handle(Protected, env)
      assert_all_valid(messages)

      assert value_at(messages, "/ui/status") =~ "not authorized"
      refute Enum.any?(paths(messages), &String.starts_with?(&1, "/errors/"))
      assert Ash.read!(Protected, authorize?: false) == []
    end

    test "the actor is honored on both the write and the refresh read" do
      env = envelope("submit_form", "protected", %{"values" => %{"name" => "Yep"}})

      assert {:ok, messages} = ActionHandler.handle(Protected, env, actor: @actor)
      assert_all_valid(messages)

      assert [%{name: "Yep"}] = Ash.read!(Protected, authorize?: false)
      assert [%{"name" => "Yep"}] = value_at(messages, "/records")
    end

    test "authorize?: false bypasses policies (explicit opt-out)" do
      env = envelope("submit_form", "protected", %{"values" => %{"name" => "Bypass"}})

      assert {:ok, _messages} = ActionHandler.handle(Protected, env, authorize?: false)
      assert [%{name: "Bypass"}] = Ash.read!(Protected, authorize?: false)
    end
  end

  describe "standalone UI modules" do
    test "a standalone UI module works as the first argument" do
      env =
        envelope("submit_form", "minimal_standalone", %{
          "values" => %{"name" => "Standalone"}
        })

      assert {:ok, messages} = ActionHandler.handle(MinimalUI, env)
      assert_all_valid(messages)

      assert [%{name: "Standalone"}] = Ash.read!(Minimal, authorize?: false)

      assert Enum.all?(messages, fn message ->
               message["updateDataModel"]["surfaceId"] == "minimal_standalone"
             end)
    end
  end
end
