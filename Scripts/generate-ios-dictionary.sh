#!/bin/bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(dirname -- "$script_dir")"
source_dictionary="$project_root/Resources/fy.dict.yaml"
allowed_characters="$project_root/iOS/Resources/allowed_characters.txt"
output_dictionary="$project_root/iOS/Resources/fy.dict.yaml"
temporary_dictionary="$output_dictionary.tmp"

cleanup() { rm -f "$temporary_dictionary"; }
trap cleanup EXIT

ruby - "$allowed_characters" "$source_dictionary" "$temporary_dictionary" <<'RUBY'
require "digest"
allowed_path, source_path, output_path = ARGV
lines = File.readlines(allowed_path, chomp: true).reject { |line| line.start_with?("#") }
characters = lines.join.each_char.to_a
abort "allowed character list must contain 8,105 characters" unless characters.length == 8_105
abort "allowed character list contains duplicates" unless characters.uniq.length == 8_105
abort "allowed character list checksum changed" unless Digest::SHA256.file(allowed_path).hexdigest == "9da0c863a53b9d5330b3740d2593ef66be8e15ab8933c2be88222a7d5e1d455f"
allowed = characters.to_h { |character| [character, true] }
counts = Hash.new(0)
seen_rows = {}
data_started = false

File.open(output_path, "w") do |output|
  File.foreach(source_path).with_index(1) do |line, line_number|
    data_started = true if line.start_with?("...")
    if !data_started || line.start_with?("#", "---", "...") || line.strip.empty?
      output.write(line)
      next
    end
    fields = line.chomp.split("\t", -1)
    abort "invalid dictionary row at line #{line_number}" unless fields.length == 5
    text, code, weight_text, source, order_text = fields
    abort "invalid text/source at line #{line_number}" if text.empty? || !%w[flypy pinyin essay].include?(source)
    abort "invalid weight/order at line #{line_number}" unless Integer(weight_text, exception: false) && Integer(order_text, exception: false)
    abort "invalid code at line #{line_number}" unless !code.empty? && code.match?(/\A[a-z']+\z/)
    next unless text.each_char.all? { |character| allowed[character] }
    keep = (source == "flypy" && code.length <= 4) || source == "pinyin" ||
      (source == "essay" && weight_text.to_i >= 1_000)
    next unless keep
    key = fields.join("\t")
    abort "duplicate dictionary row at line #{line_number}" if seen_rows[key]
    seen_rows[key] = true
    counts[source] += 1
    output.write(line)
  end
end

expected = { "flypy" => 74_022, "pinyin" => 9_510, "essay" => 8_545 }
abort "unexpected dictionary counts: #{counts.inspect}" unless counts == expected
abort "iOS dictionary exceeds 3.2 MB" if File.size(output_path) > 3_200_000
puts "Entries: #{counts.sort.map { |source, count| "#{source}=#{count}" }.join(" ")}"
puts "Allowed characters: #{characters.length}; bytes: #{File.size(output_path)}"
RUBY

mv "$temporary_dictionary" "$output_dictionary"
trap - EXIT
printf 'Generated %s\n' "$output_dictionary"
