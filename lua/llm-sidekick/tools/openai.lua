local function convert_spec(spec)
  return {
    type = "function",
    ["function"] = {
      name = spec.name,
      description = spec.description,
      parameters = spec.input_schema,
    }
  }
end

return {
  convert_spec = convert_spec
}
