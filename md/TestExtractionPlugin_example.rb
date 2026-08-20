#!/usr/bin/env ruby
#
# Example TestExtractionPlugin.
#
# Install as an executable named `TestExtractionPlugin` (no extension) at --plugins_path.
#
# Mendoza's built-in extraction already finds every test method in the UI testing target, so
# only write this plugin when you need to *narrow* that list — here, honouring a
# `// mendoza:ipad-only` marker so those tests are dispatched only when running on an iPad.

require "json"
require "uri"

payload = JSON.parse($stdin.read)
input = payload["input"]
data = JSON.parse(payload["data"] || "{}")

device_name = input["device"]["name"]
ipad = device_name.downcase.include?("ipad")

tests = []

input["candidates"].each do |candidate|
  # `candidates` are absolute file:// URLs, not plain paths: File.read would fail on them.
  path = URI(candidate).path
  source = File.read(path)

  suite = File.basename(path, ".swift")
  ipad_only = source.include?("// mendoza:ipad-only")

  next if ipad_only && !ipad

  source.scan(/func\s+(test\w*)\s*\(\s*\)/) do |method|
    tests << { "name" => method.first, "suite" => suite }
  end
end

# Diagnostics belong on stderr. Anything written to stdout has to be the result.
warn "extracted #{tests.size} tests from #{input["candidates"].size} files for #{device_name}"
warn "plugin data: #{data.inspect}" unless data.empty?

puts JSON.generate(tests)
