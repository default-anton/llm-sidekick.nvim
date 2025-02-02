local function convert_spec(spec)
  return {
    type = "function",
    ["function"] = {
      name = spec.name,
      description = spec.description,
      strict = true,
      parameters = vim.tbl_extend("force", spec.input_schema, { additionalProperties = false }),
    }
  }
end

return {
  convert_spec = convert_spec
}
