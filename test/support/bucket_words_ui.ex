defmodule AshA2ui.Test.BucketWordsUI do
  @moduledoc """
  Fixture surface for dynamic table sets (v0.9.1): a static `:new_words`
  table plus a sectioned `:per_bucket` template expanded at runtime into one
  table per `AshA2ui.Test.Bucket` — the misspellings-buckets proving case.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BucketWord
    surface_id "bucket_words"

    query :word_q do
      search_fields [:word]
      sortable [:word]
      default_sort word: :asc
      page_size 5
    end

    component :table, :new_words do
      fields [:word, :replacement]
      read_action :new_words
      row_actions [:approve]
    end

    component :table, :per_bucket do
      fields [:word, :replacement]
      read_action :bucketed
      row_actions [:destroy]
      query :word_q

      sections do
        source AshA2ui.Test.Bucket
        scope_by :bucket_id
        label :name
        sort :name
      end
    end

    action :approve do
      refreshes [:new_words, :per_bucket]
    end

    action :destroy do
      refreshes [:per_bucket]
    end
  end
end

defmodule AshA2ui.Test.BucketWordsV1UI do
  @moduledoc """
  The same dynamic-table-set fixture surface as `AshA2ui.Test.BucketWordsUI`,
  but with `spec_version "1.0"` — validates section expansion against the
  v1.0 schemas and the actionResponse handshake.
  """

  use AshA2ui.Standalone

  a2ui do
    for_resource AshA2ui.Test.BucketWord
    surface_id "bucket_words_v1"
    spec_version("1.0")

    query :word_q do
      search_fields [:word]
      sortable [:word]
      default_sort word: :asc
      page_size 5
    end

    component :table, :per_bucket do
      fields [:word, :replacement]
      read_action :bucketed
      row_actions [:destroy]
      query :word_q

      sections do
        source AshA2ui.Test.Bucket
        scope_by :bucket_id
        label :name
        sort :name
      end
    end
  end
end
