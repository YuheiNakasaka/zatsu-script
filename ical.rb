#! /usr/bin/env ruby
# https://ja.wikipedia.org/wiki/ICalendar

lines = File.open("./ical_data/example001.txt").read.split("\n")
tag = ARGV[0]
if tag.nil?
  puts 'tag is required'
  exit 1
end

ans = {}
i = 0
loop do
  line = lines[i]
  break if line.nil?

  if line.match?(/^#{tag}/)
    splits = line.split(':')
    key = splits[0]
    value = splits[1..].join(':').strip
    raise 'value is empty' if value.length <= 0
    raise 'key is already set' if ans.key?(key)
    raise 'line is too long' if value.length > 75

    ans[key] = value
    loop do
      i += 1
      break unless lines.length > i

      next_line = lines[i]
      if next_line.match?(/^[\s|\t]/)
        ans[key] += next_line.strip
      else
        break
      end
    end
  end
  i += 1
end

ans.each do |k, v|
  puts "#{k}: #{v}"
end
