defmodule Mix.Tasks.AshA2ui.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs AshA2ui"
  end

  def example do
    "mix igniter.install ash_a2ui"
  end

  def long_doc do
    """
    #{short_doc()}

    Adds `:ash_a2ui` to the `import_deps` of your `.formatter.exs` and ensures
    the `Spark.Formatter` plugin is configured, so `mix format` understands the
    `a2ui` DSL.

    ## Example

    ```bash
    #{example()}
    ```
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshA2ui.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        # Groups allow for overlapping arguments for tasks by the same author
        group: :ash,
        # *other* dependencies to add and call their associated installers
        installs: [{:ash, "~> 3.0"}],
        # An example invocation
        example: __MODULE__.Docs.example()
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.Project.Formatter.import_dep(:ash_a2ui)
      |> Igniter.Project.Formatter.add_formatter_plugin(Spark.Formatter)
    end
  end
else
  defmodule Mix.Tasks.AshA2ui.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'ash_a2ui.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
