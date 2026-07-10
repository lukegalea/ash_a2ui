# Used by "mix format"
spark_locals_without_parens = [
  create_action: 1,
  fields: 1,
  for_resource: 1,
  format: 1,
  hidden: 1,
  label: 1,
  order: 1,
  read_action: 1,
  row_actions: 1,
  surface_id: 1,
  update_action: 1,
  widget: 1
]

[
  import_deps: [:ash, :spark],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter],
  locals_without_parens: spark_locals_without_parens,
  export: [
    locals_without_parens: spark_locals_without_parens
  ]
]
