require 'json'
path = 'international_english.json'
arr = JSON.parse(File.read(path))
# Deduplicate by lowercase 'find', keeping first occurrence
seen = {}
uniq = []
arr.each do |e|
  k = e['find'].downcase
  unless seen.key?(k)
    uniq << e
    seen[k] = true
  end
end
sorted = uniq.sort_by { |e| e['find'].downcase }
File.write(path, JSON.pretty_generate(sorted))
puts "Wrote #{sorted.size} entries to #{path}"