defmodule AshA2ui.ServerCallTest do
  @moduledoc """
  `AshA2ui.ActionHandler.ash_action_call/3` builds the `callAgentFunction` a
  renderer would send, for a server to run an action nobody clicked; every
  message it builds round-trips through `AshA2ui.ActionHandler.handle/3`
  exactly as the renderer's call does. `agent_function_response?/1` picks
  out the follow-up that settles it.
  """

  use ExUnit.Case, async: true

  import AshA2ui.Test.SchemaHelper

  alias AshA2ui.ActionHandler

  alias AshA2ui.Test.{
    BucketWord,
    KitchenSink,
    Messages,
    Minimal,
    MinimalUI,
    Paginated,
    WordReportV1UI
  }

  doctest AshA2ui.ActionHandler, only: [ash_action_call: 3, agent_function_response?: 1]

  @catalogs Messages.catalogs()

  defp value_at(messages, path) do
    Enum.find_value(messages, fn
      %{"updateDataModel" => %{"path" => ^path, "value" => value}} -> value
      _other -> nil
    end)
  end

  defp surface_ids(messages),
    do: for(message <- messages, {_kind, %{"surfaceId" => id}} <- message, do: id)

  describe "ash_action_call/3" do
    test "is a renderer-to-agent message the 1.0 schemas accept" do
      call = ActionHandler.ash_action_call(KitchenSink, "submit_form", %{"values" => %{}})

      assert_valid_renderer_message(call, catalogs: @catalogs)

      assert %{
               "version" => "1.0",
               "callAgentFunction" => %{
                 "surfaceId" => "kitchen_sink",
                 "functionCallId" => "server-submit_form-" <> n,
                 "callFunction" => %{
                   "@call" => "ashAction",
                   "catalogId" => catalog_id,
                   "args" => %{"name" => "submit_form", "context" => %{"values" => %{}}}
                 }
               }
             } = call

      assert catalog_id == AshA2ui.Encoder.ash_catalog_id()
      assert String.to_integer(n) > 0
    end

    test "names the surface the module is built with, declared or default" do
      assert ActionHandler.ash_action_call(MinimalUI, "query", %{})["callAgentFunction"][
               "surfaceId"
             ] == AshA2ui.ResolvedView.resolve(MinimalUI, []).surface_id

      assert ActionHandler.ash_action_call(Minimal, "query", %{})["callAgentFunction"][
               "surfaceId"
             ] == AshA2ui.ResolvedView.resolve(Minimal, []).surface_id
    end

    test "gives every call its own id" do
      ids =
        for _ <- 1..3,
            do:
              ActionHandler.ash_action_call(MinimalUI, "query", %{})["callAgentFunction"][
                "functionCallId"
              ]

      assert length(Enum.uniq(ids)) == 3
    end

    test "a write round-trips: the action runs and the call is answered under its id" do
      call =
        ActionHandler.ash_action_call(KitchenSink, "submit_form", %{
          "values" => %{"name" => "From the server"}
        })

      call_id = call["callAgentFunction"]["functionCallId"]

      assert {:ok, messages} = ActionHandler.handle(KitchenSink, call)
      Enum.each(messages, &assert_valid_agent_message(&1, catalogs: @catalogs))

      assert [%{name: "From the server"}] = Ash.read!(KitchenSink, authorize?: false)
      assert Enum.uniq(surface_ids(messages)) == ["kitchen_sink"]
      assert %{"kind" => "success", "functionCallId" => ^call_id} = Messages.feedback(messages)

      assert ActionHandler.agent_function_response?(List.last(messages))

      assert %{"functionCallId" => ^call_id, "value" => %{"kind" => "success"}} =
               Messages.response(messages)
    end

    test "a refused write is answered as a renderer's call is" do
      call = ActionHandler.ash_action_call(KitchenSink, "submit_form", %{"values" => %{}})
      call_id = call["callAgentFunction"]["functionCallId"]

      assert {:error, messages} = ActionHandler.handle(KitchenSink, call)
      assert value_at(messages, "/errors/name")

      assert %{"functionCallId" => ^call_id, "error" => %{"code" => "VALIDATION_FAILED"}} =
               Messages.response(messages)
    end

    test "a table query round-trips (a URL replay)" do
      for name <- ["Ada", "Grace"], do: Ash.create!(Paginated, %{name: name}, authorize?: false)

      call =
        ActionHandler.ash_action_call(Paginated, "query", %{
          "query" => %{"search" => "ada", "page" => 1}
        })

      assert {:ok, messages} = ActionHandler.handle(Paginated, call, actor: nil)
      Enum.each(messages, &assert_valid_agent_message(&1, catalogs: @catalogs))

      assert Enum.uniq(surface_ids(messages)) == ["paginated"]
      assert [%{"name" => "Ada"}] = value_at(messages, "/records")
      assert %{"search" => "ada", "page" => 1, "totalCount" => 1} = value_at(messages, "/query")

      assert Messages.response(messages)["functionCallId"] ==
               call["callAgentFunction"]["functionCallId"]
    end

    test "a report runs on arrival, and dropping the response leaves its data-model writes" do
      Ash.create!(BucketWord, %{word: "abcdef"}, authorize?: false)

      call =
        ActionHandler.ash_action_call(WordReportV1UI, "report", %{
          "component" => "lengths",
          "params" => %{"min_length" => "3"}
        })

      assert {:ok, messages} = ActionHandler.handle(WordReportV1UI, call, authorize?: false)

      pushed = Enum.reject(messages, &ActionHandler.agent_function_response?/1)

      assert length(pushed) == length(messages) - 1
      assert Enum.all?(pushed, &match?(%{"updateDataModel" => _}, &1))
      assert [%{"word" => "abcdef"}] = value_at(pushed, "/report/lengths/rows")
    end

    test "a pinned surface refuses a server-built write like any other" do
      call =
        ActionHandler.ash_action_call(KitchenSink, "submit_form", %{
          "values" => %{"name" => "Then"}
        })

      assert {:error, messages} =
               ActionHandler.handle(KitchenSink, call, as_of: ~U[2026-01-01 00:00:00Z])

      assert %{"error" => %{"code" => "READ_ONLY_AS_OF"}} = Messages.response(messages)
      assert Ash.read!(KitchenSink, authorize?: false) == []
    end
  end

  describe "agent_function_response?/1" do
    test "is false for anything that is not an agentFunctionResponse" do
      refute ActionHandler.agent_function_response?(%{"updateDataModel" => %{}})
      refute ActionHandler.agent_function_response?(nil)
      refute ActionHandler.agent_function_response?("agentFunctionResponse")
    end
  end
end
