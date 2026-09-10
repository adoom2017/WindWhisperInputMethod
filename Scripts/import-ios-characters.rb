#!/usr/bin/env ruby
require "digest"
require "open-uri"

revision = "923b108dc5d45dee061324c011b478fb649f8b73"
source = "https://raw.githubusercontent.com/mozillazg/pinyin-data/#{revision}/tools/china-8105-06062014.txt"
data = URI.open(source, open_timeout: 15, read_timeout: 30, &:read)
abort "upstream character list checksum changed" unless Digest::SHA256.hexdigest(data) ==
  "2a86c196f2d3b35610597f550bc7a9c3377ac0e9a93bf41dae6feea07c35cbc3"
characters = data.lines.filter_map do |line|
  next if line.start_with?("#") || line.strip.empty?
  match = /\AU\+([0-9A-F]+)\s+\d+\s*\z/.match(line)
  abort "invalid upstream row: #{line.inspect}" unless match
  match[1].to_i(16).chr(Encoding::UTF_8)
end
abort "expected 8,105 unique characters" unless characters.length == 8_105 && characters.uniq.length == 8_105
header = [
  "# General Standard Chinese Characters: 8,105 unique characters.",
  "# Source: mozillazg/pinyin-data, tools/china-8105-06062014.txt",
  "# Revision: #{revision}",
  "# License: MIT; Copyright (c) 2016 mozillazg",
  "# Full notice: LICENSES/pinyin-data-MIT.txt"
]
output = (header + characters.each_slice(100).map(&:join)).join("\n") + "\n"
path = File.expand_path("../iOS/Resources/allowed_characters.txt", __dir__)
File.write(path, output)
puts "Imported #{characters.length} characters; SHA256: #{Digest::SHA256.hexdigest(output)}"
