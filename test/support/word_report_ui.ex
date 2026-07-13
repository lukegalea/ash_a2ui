defmodule AshA2ui.Test.WordReportUI do
  @moduledoc """
  Fixture surface for aggregate/report queries (v0.9.1): a single `:report`
  component running the `:length_report` generic action of
  `AshA2ui.Test.BucketWord` with a `min_length` param — computed rows, not
  resource records.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BucketWord
    surface_id "word_report"

    component :report, :lengths do
      action :length_report
      params([:min_length])
      fields [:word, :length, :state]
    end
  end
end

defmodule AshA2ui.Test.WordReportV1UI do
  @moduledoc """
  The same report fixture surface as `AshA2ui.Test.WordReportUI`, but with
  `spec_version "1.0"` — validates report surfaces against the v1.0 schemas
  and the structured `/ui/response` + actionResponse result path.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BucketWord
    surface_id "word_report_v1"
    spec_version("1.0")

    component :report, :lengths do
      action :length_report
      params([:min_length])
      fields [:word, :length, :state]
    end
  end
end
