# Start the minimal Phoenix test endpoint for LiveRenderer tests, but only
# when the Phoenix stack is present (the NO_PHOENIX CI job strips it).
if Code.ensure_loaded?(Phoenix.LiveView) do
  {:ok, _} =
    Supervisor.start_link(
      [
        {Phoenix.PubSub, name: AshA2ui.Test.PubSub},
        AshA2ui.Test.Endpoint
      ],
      strategy: :one_for_one,
      name: AshA2ui.Test.Supervisor
    )
end

ExUnit.start()
