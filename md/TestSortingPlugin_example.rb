#!/usr/bin/env ruby
#
# Example TestSortingPlugin.
#
# Install as an executable named `TestSortingPlugin` (no extension) at --plugins_path.
#
# Mendoza dispatches tests longest-first, so giving it duration estimates shortens the whole
# session: without them the order is arbitrary and a slow test picked up last leaves every
# other node idle while it finishes. Durations here come from Cachi
# (https://github.com/Subito-it/Cachi), which records them from previous sessions.

require "json"
require "net/http"
require "digest"

# Mendoza always writes the envelope to stdin. Accepting a file path as well lets you run this
# under a debugger, whose run configurations cannot redirect stdin.
payload = JSON.parse(ARGV[0] ? File.read(ARGV[0]) : $stdin.read)
input = payload["input"]
data = JSON.parse(payload["data"] || "{}")

host = data["cachi_host"] || "http://localhost:8090"
device = input["device"]

def duration(host, identifier)
  response = Net::HTTP.get_response(URI("#{host}/v1/teststats?#{identifier}"))
  return nil unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)["avg_duration_sec"]
rescue StandardError => e
  # A sorting plugin is an optimization: degrade to the input order rather than failing the
  # session because a stats service is unreachable.
  warn "could not fetch stats for #{identifier}: #{e.message}"
  nil
end

estimated = input["tests"].map do |test|
  identifier = Digest::MD5.hexdigest("#{test["suite"]}-#{test["name"]}()-#{device["name"]}-#{device["runtime"]}")
  [test, duration(host, identifier) || 0.0]
end

missing = estimated.count { |_, seconds| seconds.zero? }
warn "estimated #{estimated.size - missing}/#{estimated.size} tests, #{missing} unknown"

# Longest first. Unknown tests sort last, which is the safe default: overestimating a short
# test wastes less time than discovering a long one at the end of the run.
sorted = estimated.sort_by { |_, seconds| -seconds }.map(&:first)

puts JSON.generate(sorted.map { |t| { "name" => t["name"], "suite" => t["suite"] } })
