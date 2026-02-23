# frozen_string_literal: true

# rules.rb
# Rules processing.

require 'logger'

module Weird
  # Categories not in templates should be moved to the bottom of the page.
  # Ensure 1 cat / line and proper spacing. Ignores referenced categories [[:Category:Blah]].
  # TODO:
  #   Ensure it doesnt make changes when none needed, eg, finding cats already at bottom and replacing them at bottom.
  #   Absolute bottom should be for __keyword__ stuff that is already there.
  #     Eg: __HIDDENCAT__. There's at least one more, the expected empty cat keyword.
  #   Status reporting.
  #     Always log starting a new class.
  #     Light log entering a method, finishing a method or class.
  #     Verbose log changes to major vars inside of loops 

  
  class mw_linting
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

        status('headings_repaired', 'Detected H1 and repaired all heading levels', false, :light)
      end

      text
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



  end # class mw_linting


  # These methods don't belong to any one rules class, they operate across multiple

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

  def main(page)
      # call all classes.main one by one
  end

end
