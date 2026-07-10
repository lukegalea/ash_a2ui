import Config

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [],
    "AshA2ui.Standalone": []
  ]

if Mix.env() == :dev do
  config :git_ops,
    mix_project: AshA2ui.MixProject,
    github_handle_lookup?: true,
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/lukegalea/ash_a2ui",
    manage_mix_version?: true,
    manage_readme_version: "README.md",
    version_tag_prefix: "v"
end

if Mix.env() == :test do
  config :ash, :validate_domain_resource_inclusion?, false
  config :ash, :validate_domain_config_inclusion?, false

  # SchemaHelper resolves the A2UI spec's cross-file $refs from the vendored
  # copies in priv/a2ui/v0_9_1 instead of the network.
  config :ex_json_schema, :remote_schema_resolver, {AshA2ui.Test.SchemaHelper, :resolve_remote}

  config :logger, level: :warning

  # Minimal Phoenix endpoint used only by (future) LiveRenderer tests.
  # Harmless when the Phoenix stack is excluded (NO_PHOENIX=1): the endpoint
  # module is never compiled or started in that case.
  config :ash_a2ui, AshA2ui.Test.Endpoint,
    url: [host: "localhost", port: 4002],
    secret_key_base: String.duplicate("a", 64),
    live_view: [signing_salt: "aaaaaaaaaaaaaaaa"],
    render_errors: [
      formats: [html: AshA2ui.Test.ErrorHTML],
      layout: false
    ],
    check_origin: false,
    server: false,
    pubsub_server: AshA2ui.Test.PubSub

  config :phoenix, :json_library, Jason
end
