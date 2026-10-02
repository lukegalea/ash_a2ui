# Start the minimal Phoenix test endpoint for LiveRenderer tests, but only
# when the Phoenix stack is present (the NO_PHOENIX CI job strips it).
if Code.ensure_loaded?(Phoenix.LiveView) do
  {:ok, _} =
    Supervisor.start_link(
      [
        {Phoenix.PubSub, name: AshA2ui.Test.PubSub},
        # The presence fixture (AshA2ui.Test.PresenceLive) supervises its
        # CRDT replica over the shared test PubSub.
        AshA2ui.Test.Presence,
        AshA2ui.Test.Endpoint
      ],
      strategy: :one_for_one,
      name: AshA2ui.Test.Supervisor
    )
end

# JUnitFormatter writes the JUnit XML evidence that .sdlc/verification.yaml
# declares (test/reports/junit/*.xml, configured in config/config.exs);
# CLIFormatter keeps the usual console output.
ExUnit.start(formatters: [ExUnit.CLIFormatter, JUnitFormatter])
