// Prints the generated secrets so CI can assert which section was selected and that the
// `?`-marked variable reached the tool.
print("\(Secrets.demoKey)[\(Secrets.optionalKey)]")
