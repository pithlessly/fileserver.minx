function Reader(input, options)
  return pandoc.Pandoc{
    pandoc.CodeBlock(tostring(input), { class = options.indented_code_classes[1] })
  }
end
