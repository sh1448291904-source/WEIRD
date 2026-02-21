#!/usr/bin/env ruby
# frozen_string_literal: true

#
# WEIRD - Wiki EdIt Robot Daemon
#
# PARAMETERS:
#   --simulate              Run in simulation mode (doesn't make actual edits). This also forces verbose.
#   --log-level=LEVEL       Control logging verbosity:
#                             - none     : No status messages (default)
#                             - light    : Key progress indicators (sites, rules, pages changed)
#                             - verbose  : All status messages including details
#   --verbose               Shorthand for --log-level=verbose
#
#   RULES FILES (all enabled by default, use --no-* to disable):
#   --no-typos              Disable typos.json rules
#   --no-grammar            Disable grammar.json rules
#   --no-prose-linting      Disable prose_linting.json rules
#   --no-mw-linting         Disable mw_linting.json rules
#   --no-international-english  Disable international_english.json rules (British to American spelling)
#   --no-dubious            Disable dubious.json rules (always simulated, never written)
#   --no-glossary           Disable glossary tagging (tooltips from Glossary page)
#
# EXAMPLES:
#   ruby WEIRD.rb
#   ruby WEIRD.rb --simulate
#   ruby WEIRD.rb --log-level=light
#   ruby WEIRD.rb --log-level=verbose
#   ruby WEIRD.rb --verbose
#   ruby WEIRD.rb --simulate --no-typos --no-grammar
#   ruby WEIRD.rb --no-prose-linting
#   ruby WEIRD.rb --no-glossary
#   ruby WEIRD.rb --test
# TO DO
# <ol> lists
# Template calls:
#   Use categories_to_bottom logic for protecting templates right at the start, and restore at the end.
#   Do mw-linting first to make template's pipes nice.
#   We could whitelist templates per site that could do with an internal copyedit.
# Load a rules file with the same name as that site, just for that site.
# ET phone home
# Allow site-based rules files to have entries with function names to run.
#   This allows other sites to implement atomic Timberborn-specific functionality as required.
#
# Before running on Timberborn
# All quotes pages to have {{nobots}} as they have a lot of non-standard text that this bot will want to correct.
#
# Exclude all quote areas.
#  {{Quote}}, <blockquote>...</blockquote>, {{Quotation}}, {{Quote box}}, {{Dialogue}}
#  :'''Character1:''' Line of dialogue.
#  :'''Character2:''' Response.
#  Used on "Quotes" subpages (e.g., CharacterName/Quotes). Each line is a bullet point,
#  grouped under headings by context (intro, win, loss, etc.)
#  Quote as a heading with bullets underneath.
#  {{Quotation line}} / {{Quote line}} — Inline Styling. Eg: Terraria.wiki.gg
#  Quote=
#
# Dubious
#   Show entire sentence containing the issue, not just the word. This gives more
#   context to editors and makes it more likely they will understand the issue and fix it.
#   Build a white list of site name / page name / dubious rule combinations that are ignored,
#   to avoid repeatedly flagging the same false positives on the same pages. Editors can then
#   remove false positives from the whitelist into the actual site whitelist and fix what remains.
#
# check for too many prepositions in a sentence, probable wordiness.
#   about, above, across, after, against, along, amid, among, around, at, before, behind, below, beneath, beside, besides, between, beyond, by,
#   concerning, considering, despite, down, during, except, for, from, in, inside, into, like, near, of, off, on, onto, opposite, out, outside,
#   over, past, per, regarding, round, since, than, through, throughout, till, to, toward, towards, under, underneath, unlike, until, up, upon, via,
#   with, within, without
#
#   according to, adjacent to, ahead of, along with, apart from, as for, as of, as per, as to, aside from, away from, because of, close to, due to,
#   except for, far from, in addition to, in case of, in front of, in lieu of, in place of, in spite of, instead of, next to, on account of,
#   on behalf of, on top of, out of, outside of, owing to, prior to, regardless of, subsequent to, together with, up to
#
#   as a result of, at the expense of, by means of, by virtue of, by way of, in accordance with, in back of, in comparison with, in contrast to,
#   in keeping with, in light of, in order to, in place of, in reference to, in regard to, in relation to, in respect of, in terms of,
#   in the event of, in the face of, in view of, on the basis of, on the part of, on the side of, with reference to, with regard to,
#   with respect to, with the exception of
#
#   aboard, alongside, bar, cum, ere, minus, notwithstanding, opposite, past, plus, save, short of, times, versus, worth

# Check for sentences with too many conjunctions, probable run-on sentences.
# Check for long sentences and suggest shorter sentences, Maybe autofix at conjunctions.
# Check for passive voice, maybe flag as dubious but not auto-fix as it can be tricky to rephrase without changing meaning.
# Subject/verb agreement issues, maybe flag as dubious if we can't be sure of the correct verb form.
# Title casing headings
# Check for repeated words, e.g., "the the", "and and", etc.
# Check for common homophone confusion, e.g., "there/their/they're", "your/you're", "its/it's", "affect/effect", etc.
# Check for overuse of adverbs (words ending in -ly), which can indicate wordiness.
# Check for overuse of "very", which can often be removed without changing meaning.
# Check for "literally" used in a non-literal sense, which is a common pet peeve.
# Check for "could of" instead of "could have", "should of" instead of "should have", etc.
# Check for "alot" instead of "a lot".
# Check for "irregardless" instead of "regardless".
# Check for "then" vs "than" confusion.
# Check for "loose" vs "lose" confusion.
# Check for "accept" vs "except" confusion.
# Check for "affect" vs "effect" confusion.
# Check for "complement" vs "compliment" confusion.
# Check for "principal" vs "principle" confusion.
# Check for "stationary" vs "stationery" confusion.
# Check for "advice" vs "advise" confusion.
# Check for "allusion" vs "illusion" confusion.
# Check for "canvas" vs "canvass" confusion.
# Check for "council" vs "counsel" confusion.
# Check for "desert" vs "dessert" confusion.
# Check for "eminent" vs "imminent" confusion.
# Check for "farther" vs "further" confusion.
# Check for "gauge" vs "guage" misspelling.
# Check for "horde" vs "hoard" confusion.
# Check for "imply" vs "infer" confusion.
# Check for "jewel" vs "joule" confusion.
# Check for "kernel" vs "colonel" confusion.
# Check for "lightening" vs "lightning" confusion.
# Check for "marital" vs "martial" confusion.
# Check for "naval" vs "navel" confusion.
# Check for "opportunity" misspelled as "oppertunity".
# Check for "play" vs "plea" confusion.
# Check for "quiet" vs "quite" confusion.
# Check for "respectfully" vs "respectively" confusion.
# Check for "stationary" vs "stationery" confusion.
# Check for "their/there/they're", "your/you're", "its/it's", etc. confusion.
# Check for "a" vs "an" confusion.
# Check for "and/or" usage, which can often be simplified to just "or".
# Check for "etc." used in a non-list context, which can often be removed or replaced with "and so on".

require 'mediawiki/butt'
require 'json'
require 'time'

# Command line arguments
SIMULATE = ARGV.include?('--simulate')
TEST = ARGV.include?('--test')

# Parse logging level: none (default), light, or verbose
log_level_arg = ARGV.find { |arg| arg.start_with?('--log-level=') }
LOG_LEVEL = if log_level_arg
              log_level_arg.split('=')[1].downcase.to_sym
            elsif ARGV.include?('--verbose')
              :verbose
            else
              :none
            end

# Ensure simulation mode shows verbose logging
LOG_LEVEL = :verbose if SIMULATE

# Parse rules file flags (defaults to true/enabled)
RULES_CONFIG = {
  typos: !ARGV.include?('--no-typos'),
  grammar: !ARGV.include?('--no-grammar'),
  prose_linting: !ARGV.include?('--no-prose-linting'),
  mw_linting: !ARGV.include?('--no-mw-linting'),
  international_english: !ARGV.include?('--no-international-english'),
  dubious: !ARGV.include?('--no-dubious'),
  glossary: !ARGV.include?('--no-glossary')
}.freeze

# Status tracking and reporting
$status_indent = 0
def status(var_name, value, is_section = false, level = :verbose)
  return unless log?(level)

  if is_section
    puts "\n>>> #{var_name}"
    $status_indent = 1
  else
    indent = '  ' * $status_indent
    puts "#{indent}> #{var_name}: #{value.inspect}"
  end
end

# Helper to determine if a message should be logged based on the current LOG_LEVEL
def log?(level)
  case LOG_LEVEL
  when :none
    false
  when :light
    %i[light all].include?(level)
  when :verbose
    true
  end
end

# Helper to load JSON files with error handling
def load_json(file)
  JSON.parse(File.read(file))
rescue => e
  puts "Error loading #{file}: #{e.message}"
  exit
end

# Helper to check for bot exclusion templates or __NOEDITSECTION__ on any page
def should_edit?(text, bot_name)
  # Standard MediaWiki bot exclusion patterns
  return false if text.include?('{{nobots}}')
  return false if text.match?(/\{\{bots\s*\|\s*deny\s*=\s*(all|#{Regexp.escape(bot_name)})\s*\}\}/i)
  return false if text.include?('{{donotbot}}')
  return false if text.include?('__NOEDITSECTION__')

  true
end

# Check page text for plain page names or explicit links and convert to
# either [[PageName]] or {{icon|PageName}} when appropriate.
def page_link_check(page_title, text, pages_main, icon_map)
  # Logging: mark start of page_link_check for this page
  status('Page link checking started', page_title, true, :verbose)
  changed = false
  replacements = 0

  pages_main.each do |pname|
    next if pname == page_title
    next if pname.to_s.strip.empty?

    # If there's an explicit link [[Pagename]] and an icon exists, replace
    if icon_map[pname]
      link_regex = /\[\[\s*#{Regexp.escape(pname)}\s*\]\]/
      if text.match?(link_regex)
        text = text.gsub(link_regex, "{{icon|#{pname}}}")
        changed = true
        replacements += 1
        status('icon_replaced', pname, false, :verbose)
      end
    end

    # If there's a plain exact match (word boundary) and no existing link,
    # convert the first occurrence to a link or icon template.
    link_exists = text.match(/\[\[\s*#{Regexp.escape(pname)}(?:\|[^\]]+)?\s*\]\]/)
    next if link_exists

    plain_regex = /(?<!\[\[)(?<!\w)#{Regexp.escape(pname)}(?!\w)/
    next unless text.match?(plain_regex)

    replacement = icon_map[pname] ? "{{icon|#{pname}}}" : "[[#{pname}]]"
    text = text.sub(plain_regex, replacement)
    changed = true
    replacements += 1
    status('plain_replaced', "#{pname} -> #{replacement}", false, :verbose)
  end

  status('Page link updates:', { changed: changed, replacements: replacements }, false, :verbose)
  [text, changed]
end

# Check and manage TOC based on heading count
# If more than 10 headings: ensure {{TOC right}} exists
# If 10 or fewer headings: remove any {{TOC}} or {{TOC right}}
def manage_toc(text)
  # Count headings (== through ====== level, not including = on its own)
  heading_count = text.scan(/\n={2,6}[^=]/).length
  status('heading_count', heading_count, false, :verbose)

  changed = false
  toc_status = nil

  if heading_count > 10
    # Need a TOC - check if one exists
    has_toc_right = text.include?('{{TOC right}}')
    has_toc = text.include?('{{TOC}}')

    return text, changed, heading_count, toc_status if has_toc_right

    if has_toc
      # Convert {{TOC}} to {{TOC right}}
      text = text.gsub('{{TOC}}', '{{TOC right}}')
      status('toc_converted', '{{TOC}} -> {{TOC right}}', false, :verbose)
      toc_status = 'converted to {{TOC right}}'
      changed = true
    else
      # Add {{TOC right}} at the beginning (after any intro text before first heading)
      first_heading_idx = text.index(/\n={2,6}[^=]/)
      if first_heading_idx
        text.insert(first_heading_idx, "{{TOC right}}\n\n")
        status('toc_inserted', '{{TOC right}} added before first heading', false, :verbose)
        toc_status = 'inserted {{TOC right}}'
        changed = true
      end
    end
    # return here for a bit of a cleaner method
    return text, changed, heading_count, toc_status
  end

  # 10 or fewer headings - remove any TOC
  if text.include?('{{TOC right}}')
    text = text.gsub('{{TOC right}}', '')
    status('toc_removed', 'Removed {{TOC right}} (<=10 headings)', false, :verbose)
    toc_status = 'removed {{TOC right}}'
    changed = true
  elsif text.include?('{{TOC}}')
    text = text.gsub('{{TOC}}', '')
    status('toc_removed', 'Removed {{TOC}} (<=10 headings)', false, :verbose)
    toc_status = 'removed {{TOC}}'
    changed = true
  end

  [text, changed, heading_count, toc_status]
end

# Extract glossary terms from tables on the Glossary page
# Returns a hash of term => definition
def get_glossary_terms(wiki)
  status('get_glossary_terms', 'fetching Glossary page', false, :verbose)

  begin
    glossary_text = wiki.get_text('Glossary')
  rescue
    status('Glossary', 'page not found, skipping glossary tagging', false, :light)
    return {}
  end

  glossary_terms = {}

  # Extract all wiki tables {| ... |}
  # Tables contain rows separated by |-, cells separated by | or ||
  tables = glossary_text.scan(/\{\|(.*?)\|}/m)
  status('glossary_tables_found', tables.length, false, :verbose)

  tables.each_with_index do |table_content, table_idx|
    status('processing_glossary_table', "table #{table_idx + 1}", false, :verbose)
    rows = table_content.split(/^\|-/m)
    status('glossary_rows_count', rows.length, false, :verbose)

    rows.each do |row|
      cells = []
      row.lines.each do |line|
        # Lines starting with | (or ||) contain cell data
        next unless line.match?(/^\s*[|!]/)

        # Extract cell content (remove leading | or || and whitespace)
        cell_text = line.sub(/^\s*[|!]\s*/, '').sub('||', '').strip
        cells << cell_text unless cell_text.empty?
      end

      # First two cells are term and definition
      next if cells.length < 2

      # Remove bold/italic markup
      term = cells[0].gsub(/''+'(.+?)''+/, '\1').strip
      definition = cells[1].strip
      unless term.empty?
        glossary_terms[term] = definition
        status('glossary_term', "#{term} => #{definition.truncate(50)}", false, :verbose)
      end
    end
  end

  status('Glossary', "loaded #{glossary_terms.length} terms", false, :light) if glossary_terms.length.positive?
  glossary_terms
end

# Apply glossary tooltip tags to pages
# Adds <abbr> tags with dashed border to first instance of each glossary term
# Uses word boundaries for simple words
# Only the first instance is tagged; other instances are unwrapped if they have abbr tags
def apply_glossary_tags(text, glossary_terms)
  return text if glossary_terms.empty?

  status('apply_glossary_tags', "checking #{glossary_terms.length} terms", false, :verbose)
  terms_found = 0
  terms_updated = 0
  terms_tagged = 0
  terms_matched = 0
  terms_removed = 0

  glossary_terms.each do |term, definition|
    status('checking_term', "#{term} => #{definition.truncate(50)}", false, :verbose)
    escaped_term = Regexp.escape(term)

    # Find the first instance of the term anywhere on the page (wrapped or unwrapped)
    abbr_pattern = %r{<abbr[^>]*>#{escaped_term}</abbr>}
    plain_pattern = Regexp.new(word_boundary_pattern(term))

    abbr_match = text.match(abbr_pattern)
    plain_match = text.match(plain_pattern)

    # Determine which is first
    if abbr_match && plain_match
      first_is_abbr = abbr_match.begin(0) < plain_match.begin(0)
    elsif abbr_match
      first_is_abbr = true
    elsif plain_match
      first_is_abbr = false
    else
      # status("term_not_found", term, false, :verbose)
      next
    end

    if first_is_abbr
      # First instance is already wrapped in abbr tag
      terms_matched += 1
      status('found_existing_abbr_first', term, false, :verbose)

      # Check and update definition if it differs
      abbr_full = abbr_match[0]
      if abbr_full.match?(/title="([^"]*)"/)
        current_title = abbr_full.match(/title="([^"]*)"/)&.[](1)
        if current_title == definition
          status('glossary_definition_match', "#{term}: definition already matches", false, :verbose)
        else
          updated_abbr = abbr_full.gsub(/title="[^"]*"/, %(title="#{definition}"))
          text = text.sub(abbr_full, updated_abbr)
          terms_updated += 1
          status('glossary_updated_first', "#{term}: changed from '#{current_title}' to '#{definition}'", false, :verbose)
        end
      end

      # Remove abbr tags from any other instances of this term
      search_start = abbr_match.end(0)
      loop do
        remaining = text[search_start..]
        break unless remaining.match?(abbr_pattern)

        next_match = remaining.match(abbr_pattern)
        next_abbr_full = next_match[0]
        next_unwrapped = next_abbr_full.gsub(/<abbr[^>]*>/, '').gsub('</abbr>', '')
        search_end = search_start + next_match.end(0)
        text[search_start...search_end] = text[search_start...search_end].sub(next_abbr_full, next_unwrapped)
        terms_removed += 1
        status('glossary_removed_duplicate', "#{term}: unwrapped duplicate instance", false, :verbose)
        search_start += next_unwrapped.length
      end

    else
      # First instance is plain (not wrapped) - wrap it
      terms_found += 1
      match_text = plain_match[0]
      match_idx = plain_match.begin(0)
      replacement = %(<abbr title="#{definition}">#{match_text}</abbr>)
      text = text[0...match_idx] + replacement + text[(match_idx + match_text.length)..]
      terms_tagged += 1
      status('glossary_tagged_first', "#{term}: #{definition.truncate(40)}", false, :verbose)

      # Remove abbr tags from any other instances of this term
      unwrapped_abbr_pattern = %r{<abbr[^>]*>#{Regexp.escape(match_text)}</abbr>}
      while text.match?(unwrapped_abbr_pattern)
        match = text.match(unwrapped_abbr_pattern)
        text = text.sub(match[0], match_text)
        terms_removed += 1
        status('glossary_removed_duplicate', "#{term}: unwrapped duplicate instance", false, :verbose)
      end
    end
  end

  status_msg = "found:#{terms_found} matched:#{terms_matched} updated:#{terms_updated} tagged:#{terms_tagged} removed:#{terms_removed}"
  status('glossary_summary', status_msg, false, :verbose)
  text
end

sites = load_json('sites.json')

# Helper function to apply word boundaries to simple words
# Returns escaped pattern string with word boundaries if text is a simple word
def word_boundary_pattern(text)
  escaped = Regexp.escape(text)
  # Check if the text is a simple word (only alphanumeric, underscores, hyphens, apostrophes)
  if text.match?(/^[\w\-']+$/)
    "\\b#{escaped}\\b"
  else
    escaped
  end
end

# Enforce word boundaries on simple word patterns
# Enforce word boundaries on simple word patterns
def enforce_word_boundaries(rules)
  rules.each do |rule|
    find_pattern = rule['find']
    # Check if the pattern is a simple word (only alphanumeric, underscores, hyphens, apostrophes)
    # and contains no regex special characters
    next unless find_pattern.match?(/^[a-zA-Z0-9_\-']+$/)

    # It's a simple word - add word boundaries
    rule['find'] = word_boundary_pattern(find_pattern)
    status('rule_preprocessed', "Added word boundaries to '#{find_pattern}'", false, :verbose)
  end
  rules
end

# If a Heading 1 is detected, increase all heading levels by 1
def repair_headings(text)
  # Check if a Heading 1 exists: exactly one '=' at start/end of line
  if text.match?(/^=[^=]+=\s*$/)

    # Loop from 5 down to 1 to increment levels safely
    5.downto(1) do |i|
      # Create strings of equals signs for current and next level
      current_markers = '=' * i
      next_markers    = '=' * (i + 1)

      # Regex explanation:
      # ^#{current_markers}  -> Starts with exactly 'i' equals signs
      # (.+?)                -> Captures the heading text (non-greedy)
      # #{current_markers}   -> Ends with exactly 'i' equals signs
      # \s*$                 -> Allows for trailing whitespace
      #
      # We use [^=] in the lookarounds to ensure we aren't matching
      # a higher-level heading (e.g., ensuring H2 doesn't match H3)
      find_regex = /^(?<!=)#{current_markers}([^=].+?[^=])#{current_markers}(?!=)\s*$/

      text.gsub!(find_regex) do
        "#{next_markers}#{Regexp.last_match(1)}#{next_markers}"
      end
    end

    applied_summaries << 'MW Lint: H1 detected. All headings incremented by 1.'
    status('headings_repaired', 'Detected H1 and repaired all heading levels', false, :light)
  end

  text
end

def convert_html_lists_to_wikitext(text)
  # 1. Strip <p> tags and standardize basic tags
  # Paragraphs inside <li> tags break MediaWiki bullet logic
  text.gsub!(%r{</?p[^>]*>}i, '')
  text.gsub!(/<(ul|ol|dl)[^>]*>/i) { "<#{Regexp.last_match(1).downcase}>" }
  text.gsub!(/<(li|dt|dd)[^>]*>/i) { "<#{Regexp.last_match(1).downcase}>" }

  # 2. Tracking state with a stack
  # This remembers if we are in a *, #, or : environment
  list_stack = []

  # Regex to split by all relevant list tags
  tag_regex = %r{(<ul?>|</ul?>|<ol?>|</ol?>|<dl?>|</dl?>|<li>|</li>|<dt?>|</dt?>|<dd?>|</dd?>)}i
  parts = text.split(tag_regex)

  processed_parts = parts.map do |part|
    tag = part.downcase
    case tag
    when '<ul>'
      list_stack.push('*')
      nil
    when '<ol>'
      list_stack.push('#')
      nil
    when '<dl>'
      list_stack.push(':') # Default for definitions; <dt> will override prefix
      nil
    when '</ul>', '</ol>', '</dl>'
      list_stack.pop
      nil
    when '<li>', '<dd>'
      # Standard list item or definition description
      "#{list_stack.join} "
    when '<dt>'
      # Definition term: Uses ';' for the last level instead of ':'
      prefix = list_stack[0...-1].join
      "#{prefix}; "
    when '</li>', '</dt>', '</dd>'
      nil
    else
      part
    end
  end

  # 3. Final Assembly
  result = processed_parts.compact.join

  # Ensure every list marker starts on a fresh line
  result.gsub!(/([^\n])([*#;:])/, "\\1\n\\2")

  # Collapse multiple newlines into two (using your previous rule)
  result.gsub!(/\n{3,}/, "\n\n")

  result.strip
end

# Categories not in templates should be moved to the bottom of the page.
# Ensure 1 cat / line and proper spacing. Ignores referenced categories [[:Category:Blah]].
def categories_to_bottom(text)
  # Recursive regex for balanced {{template}} structures
  template_pattern = /\{\{(?:[^{}]|\g<0>)*}}/

  # 1. Collect only 'loose' categories (outside of templates)
  categories = []
  parts = text.split(template_pattern)
  parts.each do |segment|
    categories.concat(segment.scan(/\[\[Category:[^\]\n]+\]\]/))
  end

  return text if categories.empty?

  # Remove duplicates
  categories.uniq!

  # 2. Hide templates to protect categories inside them from removal
  placeholders = []
  protected_text = text.gsub(template_pattern) do |match|
    placeholders << match
    "___TEMPLATE_#{placeholders.size - 1}___"
  end

  # 3. Remove loose categories from the protected text
  cat_regex = /\[\[Category:[^\]\n]+\]\]/
  protected_text.gsub!(cat_regex, '')

  # 4. Restore templates and clean up whitespace
  # .strip removes leading/trailing gaps; gsub collapses 3+ newlines to 2
  clean_text = protected_text.gsub(/___TEMPLATE_(\d+)___/) { placeholders[Regexp.last_match(1).to_i] }.strip
  clean_text.gsub!(/\n{3,}/, "\n\n")

  # 5. Format category block: one per line, trimmed of trailing spaces
  category_block = categories.map(&:strip).join("\n")

  applied_summaries << "MW Lint: Moved #{categories.length} categories to bottom of page" if categories.length.positive?
  status('categories_moved', categories.length, false, :light)

  # Return reconstructed text with standard bottom-of-page spacing
  "#{clean_text}\n\n#{category_block}\n"
end

# Load multiple rules files based on configuration
rules_files = [
  { name: 'typos.json', enabled: RULES_CONFIG[:typos], dubious: false },
  { name: 'grammar.json', enabled: RULES_CONFIG[:grammar], dubious: false },
  { name: 'prose_linting.json', enabled: RULES_CONFIG[:prose_linting], dubious: false },
  { name: 'international_english.json', enabled: RULES_CONFIG[:international_english], dubious: false },
  { name: 'mw_linting.json', enabled: RULES_CONFIG[:mw_linting], dubious: false },
  { name: 'dubious.json', enabled: RULES_CONFIG[:dubious], dubious: true }
]
rules = []
rules_files.each do |rules_file_config|
  next unless rules_file_config[:enabled]

  begin
    file_rules = load_json(rules_file_config[:name])
    # Mark each rule with its source file and whether it's from dubious
    file_rules.each do |r|
      r['_source'] = rules_file_config[:name]
      r['_dubious'] = rules_file_config[:dubious]
    end
    rules.concat(file_rules)
    status('rules_file_loaded', "#{rules_file_config[:name]}: #{file_rules.length} rules", false, :verbose)
  rescue
    status('rules_file_missing', rules_file_config[:name], false, :verbose)
  end
end

# Enforce word boundaries on all single-word rules
rules = enforce_word_boundaries(rules)

report = {}
report_name = "WEIRD report #{Time.now.strftime('%Y%m%d_%H%M%S')}.txt"

status('INITIALIZATION', nil, true, :light)
status('simulation_mode', SIMULATE, false, :verbose)
status('sites_loaded', sites.length, false, :light)
status('rules_loaded', rules.length, false, :light)
status('rules_disabled', RULES_CONFIG.reject { |_, v| v }.keys.join(', '), false, :verbose) if RULES_CONFIG.any? { |_, v| !v }

puts "\nStarting Wiki Trawl... #{SIMULATE ? '[SIMULATION]' : '[LIVE]'}"

sites.each do |site_cfg|
  site_name = site_cfg['name']
  report[site_name] = {}

  status('PROCESSING_SITE', site_name, true, :light)

  api_url = "#{site_cfg['url'].chomp('/')}/#{site_cfg['api_path']}"
  status('api_url', api_url, false, :verbose)
  wiki = MediaWiki::Butt.new(api_url)

  creds = load_json(site_cfg['credentials'])
  bot_user = creds['username'].split('@').first # Get the base username
  status('authenticated_user', bot_user, false, :verbose)
  wiki.login(creds['username'], creds['password'])

  # Load glossary terms for this site (only if glossary is enabled)
  glossary_terms = RULES_CONFIG[:glossary] ? get_glossary_terms(wiki) : {}

  # Build list of main-namespace pages and map of available icon files
  pages_main = wiki.get_all_pages(namespace: 0)
  status('main_pages_count', pages_main.length, false, :light)
  icon_map = {}
  pages_main.each do |p|
    file_title = "File:#{p} icon.png"
    begin
      file_text = wiki.get_text(file_title)
    rescue
      file_text = nil
    end
    icon_map[p] = true unless file_text.nil?
  end
  status('icons_found', icon_map.keys.length, false, :light)

  site_cfg['namespaces'].each do |ns|
    status('namespace', ns, false, :verbose)
    pages = wiki.get_all_pages(namespace: ns)
    status('pages_found', pages.length, false, :light)

    pages.each do |title|
      status('processing_page', title, false, :verbose)
      original_text = wiki.get_text(title)
      next if original_text.nil?

      # --- Bot Exclusion Check ---
      unless should_edit?(original_text, bot_user)
        puts "Skipping #{title}: Bot exclusion found."
        next
      end

      current_text = original_text.dup
      # Run icon/link checks and conversions before other rule-based edits
      begin
        new_text, icon_changed = page_link_check(title, current_text, pages_main, icon_map)
      rescue => e
        new_text = current_text
        icon_changed = false
        status('page_link_check_error', e.message, false, :verbose)
      end
      # Light-level report: indicate whether pagelink/icon conversions occurred
      status('Page link added', icon_changed, false, :light)
      applied_summaries = []
      if icon_changed
        current_text = new_text
        applied_summaries << 'icon/link conversions'
      end

      if RULES_CONFIG[:mw_linting]
        # Manage TOC based on heading count (only if mw_linting is enabled)
        begin
          new_text, toc_changed, heading_count, toc_status = manage_toc(current_text)
        rescue => e
          new_text = current_text
          toc_changed = false
          heading_count = 0
          toc_status = nil
          status('manage_toc_error', e.message, false, :verbose)
        end
        if toc_changed
          current_text = new_text
          applied_summaries << "TOC management: #{toc_status} (#{heading_count} headings)"
        end

        current_text = repair_headings(current_text)
        current_text = categories_to_bottom(current_text)
        current_text = convert_html_lists_to_wikitext(current_text)
      end

      # Apply glossary tooltips
      if glossary_terms.length.positive?
        begin
          new_text = apply_glossary_tags(current_text, glossary_terms)
          if new_text != current_text
            # rubocop:disable Lint/UselessAssignment
            glossary_changed = true
            # rubocop:enable Lint/UselessAssignment
            current_text = new_text
            applied_summaries << 'glossary tooltips added'
          end
        rescue => e
          status('glossary_tags_error', e.message, false, :verbose)
        end
      end

      rules.each do |rule|
        find_reg = Regexp.new(rule['find'])

        next unless current_text.match?(find_reg)

        # Collect matches for summary mapping
        matches = current_text.scan(find_reg).flatten
        status('rule_matched', rule['summary'].truncate(50), false, :verbose)

        current_text.gsub!(find_reg, rule['replace'])

        # Replace %1 and %2 in summary template
        # Note: If multiple matches exist, we use the first one for the summary
        summary = rule['summary'].gsub('%1', matches.first.to_s).gsub('%2', rule['replace'])
        # Mark dubious changes with a prefix
        summary = "[DUBIOUS] #{summary}" if rule['_dubious']
        applied_summaries << summary
      end

      next if current_text == original_text

      # Separate dubious from non-dubious changes
      # rubocop:disable Lint/UselessAssignment
      dubious_summaries = applied_summaries.select { |s| s.start_with?('[DUBIOUS]') }
      # rubocop:enable Lint/UselessAssignment
      non_dubious_summaries = applied_summaries.reject { |s| s.start_with?('[DUBIOUS]') }

      report[site_name][title] = applied_summaries
      status('rules_applied', applied_summaries.length, false, :verbose)

      # Only write if there are non-dubious changes, or if in simulate mode
      if non_dubious_summaries.empty? && !SIMULATE
        # Only dubious changes, don't write to wiki
        status('dubious_only', title, false, :verbose)
        puts "    ◁ Dubious only (not saved): #{title}"
      elsif SIMULATE
        puts "    ◇ Simulated: #{title}"
      else
        wiki.edit(title, current_text, summary: non_dubious_summaries.join('; '), minor: true)
        puts "    ✓ Saved: #{title}"
      end
    end
  end
end

# =========================================================
# ---               Report Generation                   ---
# =========================================================

status('REPORT_GENERATION', nil, true, :light)
status('report_file', report_name, false, :light)
total_pages_changed = report.values.sum(&:length)
status('total_pages_changed', total_pages_changed, false, :light)

begin
  File.open(report_name, 'w') do |f|
    f.puts "WIKI EDIT REPORT - #{Time.now}"
    f.puts "RUN MODE: #{SIMULATE ? 'SIMULATION' : 'LIVE'}"
    f.puts '=' * 50

    report.each do |site, pages|
      f.puts "\n>>> SITE: #{site}"
      if pages.empty?
        f.puts '    No changes made.'
      else
        pages.each do |title, summaries|
          f.puts "    PAGE: #{title}"
          summaries.each { |s| f.puts "      - #{s}" }
        end
      end
    end
  end
  puts "\nDone! Report written to #{report_name}"
rescue => e
  status('report_write_error', e.message, false, :light)
  warn "Error writing report #{report_name}: #{e.message}"
  # Attempt fallback: write a minimal report to a fallback file
  fallback = "#{report_name}.fallback.txt"
  begin
    File.open(fallback, 'w') do |f2|
      f2.puts "WIKI EDIT REPORT (FALLBACK) - #{Time.now}"
      f2.puts "Original write failed: #{e.message}"
      f2.puts '=' * 50
      report.each do |site, pages|
        f2.puts "\n>>> SITE: #{site}"
        if pages.empty?
          f2.puts '    No changes made.'
        else
          pages.each do |title, summaries|
            f2.puts "    PAGE: #{title}"
            summaries.each { |s| f2.puts "      - #{s}" }
          end
        end
      end
    end
    puts "Fallback report written to #{fallback}"
  rescue => e2
    status('report_fallback_error', e2.message, false, :light)
    warn "Fallback report write failed: #{e2.message}"
    # Final attempt: stream the report to STDOUT so the user can capture it
    puts "\nFALLBACK FAILED - STREAMING REPORT TO STDOUT\n"
    puts "WIKI EDIT REPORT (STREAMED) - #{Time.now}"
    puts "Original write failed: #{e.message}"
    puts "Fallback write failed: #{e2.message}"
    puts '=' * 50
    report.each do |site, pages|
      puts "\n>>> SITE: #{site}"
      if pages.empty?
        puts '    No changes made.'
      else
        pages.each do |title, summaries|
          puts "    PAGE: #{title}"
          summaries.each { |s| puts "      - #{s}" }
        end
      end
    end
  end
end
