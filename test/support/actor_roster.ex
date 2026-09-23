defmodule AshA2ui.Test.ActorRoster.Domain do
  @moduledoc false

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshA2ui.Test.ActorRoster
  end
end

defmodule AshA2ui.Test.ActorRoster do
  @moduledoc """
  A *shared* (public ETS) roster fixture for the actor tests.

  The picker's async read and the live_session's `on_mount` resolve actors
  in LiveView/task processes, which `private?: true` tables (Owner et al.)
  cannot serve — private tables are scoped to the creating process. The
  primary read records the filter it was invoked with, so tests can assert
  `AshA2ui.Actor.load/1` performs a primary-key read instead of scanning
  the roster.
  """

  use Ash.Resource,
    domain: AshA2ui.Test.ActorRoster.Domain,
    data_layer: Ash.DataLayer.Ets,
    primary_read_warning?: false

  require Ash.Query

  ets do
    private? false
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
  end

  actions do
    defaults [:destroy, create: :*, update: :*]

    read :read do
      primary? true

      prepare fn query, _context ->
        :persistent_term.put({__MODULE__, :last_filter}, query.filter)
        query
      end
    end

    # A non-primary read the actor config's :read_action can name: only
    # "Ada" rows survive it, so honoring it is observable through both
    # list/0 and load/1.
    read :ada_only do
      prepare fn query, _context ->
        Ash.Query.filter(query, name == "Ada")
      end
    end
  end
end
