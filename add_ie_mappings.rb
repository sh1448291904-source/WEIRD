require 'json'
file = 'international_english.json'
data = JSON.parse(File.read(file))
existing = data.map{|r| r['find']}
new = {
  'calibre' => 'caliber',
  'centre' => 'center',
  'fibre' => 'fiber',
  'goitre' => 'goiter',
  'litre' => 'liter',
  'lustre' => 'luster',
  'manoeuvre' => 'maneuver',
  'meagre' => 'meager',
  'metre' => 'meter',
  'mitre' => 'miter',
  'nitre' => 'niter',
  'ochre' => 'ocher',
  'reconnoitre' => 'reconnoiter',
  'sabre' => 'saber',
  'saltpetre' => 'saltpeter',
  'sepulchre' => 'sepulcher',
  'sombre' => 'somber',
  'spectre' => 'specter',
  'theatre' => 'theater',
  'titre' => 'titer'
}

new.each do |k,v|
  unless existing.include?(k)
    data << { 'find' => k, 'replace' => v, 'summary' => "Int Eng: '#{k}' --> '#{v}'" }
    puts "Added #{k} -> #{v}"
  else
    puts "Skipped existing: #{k}"
  end
end

# sort by find (case-insensitive)
data.sort_by!{|r| r['find'].downcase}
File.write(file, JSON.pretty_generate(data))
puts "Wrote #{data.length} entries to #{file}"
