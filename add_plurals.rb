require 'json'
file = 'international_english.json'
data = JSON.parse(File.read(file))
finds = data.map{|r| r['find']}
added = []

data.each do |r|
  f = r['find']
  # Skip if already plural-like or contains non-simple chars
  next if f.end_with?('s')
  next if f =~ /[^a-zA-Z\-']/
  plural = f + 's'
  next if finds.include?(plural)
  # Determine replacement plural simply by appending 's' to replacement
  repl = r['replace'] + 's'
  data << {'find' => plural, 'replace' => repl, 'summary' => "Int Eng: '#{plural}' --> '#{repl}'"}
  finds << plural
  added << plural
end

# Sort by find
data.sort_by!{|r| r['find'].downcase}
File.write(file, JSON.pretty_generate(data))
puts "Added #{added.length} plural entries: #{added.join(', ')}" unless added.empty?
puts "No plurals added" if added.empty?
puts "Total entries now: #{data.length}"
