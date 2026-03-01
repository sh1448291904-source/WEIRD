# frozen_string_literal: true

# rules.rb
# Rules processing.



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

  # MediaWiki page linting logic
  class MW_linting
    
    def categories_to_bottom(page)
      # Recursive regex for balanced {{template}} structures
      template_pattern = /\{\{(?:[^{}]|\g<0>)*}}/

      # 1. Collect only 'loose' categories (outside of templates)
      categories = []
      parts = page.split(template_pattern)
      parts.each do |segment|
        categories.concat(segment.scan(/\[\[Category:[^\]\n]+\]\]/))
      end

      return page if categories.empty?

      # Remove duplicates
      categories.uniq!

      # 2. Hide templates to prevent removing categories inside them from 
      placeholders = []
      protected_text = page.gsub(template_pattern) do |match|
        placeholders << match
        "___TEMPLATE_#{placeholders.size - 1}___"
      end

      # 3. Remove loose categories from the protected page
      # TO DO: Exclude leading : (:Category:whatever)
      cat_regex = /\[\[Category:[^\]\n]+\]\]/
      protected_text.gsub!(cat_regex, '')

      # TODO
      # If no loose cats exit. No err msg, they have special:uncatted cats for that.
      # See if the loose cats appear in the templates, and if so, remove them.
      # If no loose cats now, exit.
      # 
      # 4. Restore templates and clean up whitespace
      # .strip removes leading/trailing gaps; 
      clean_text = protected_text.gsub(/___TEMPLATE_(\d+)___/) { placeholders[Regexp.last_match(1).to_i] }.strip
      # Clean up any holes that may have been left by the extraction
      clean_text = clean_text.gsub(/[ \t]+$/, '') # remove trailing spaces
      clean_text.gsub!(/\n{3,}/, "\n\n") # collapse 3+ newlines to 2

      # 5. Format category block: one per line, trimmed of trailing spaces
      category_block = categories.map(&:strip).join("\n")

      # TO DO: Check original page against changed for if there was a REAL difference.

      status("Categories moved #{categories.size}", 0, Status::Verbosity::LIGHT) # Rubbish

      # Return reconstructed page with standard bottom-of-page spacing
      "#{clean_text}\n\n#{category_block}\n"
    end

    def convert_html_lists_to_wikitext(page)
      # 1. Strip <p> tags and standardize basic tags
      # Paragraphs inside <li> tags break MediaWiki bullet logic
      page.gsub!(%r{</?p[^>]*>}i, '')
      page.gsub!(/<(ul|ol|dl)[^>]*>/i) { "<#{Regexp.last_match(1).downcase}>" }
      page.gsub!(/<(li|dt|dd)[^>]*>/i) { "<#{Regexp.last_match(1).downcase}>" }

      # 2. Tracking state with a stack
      # This remembers if we are in a *, #, or : environment
      list_stack = []

      # Regex to split by all relevant list tags
      tag_regex = %r{(<ul?>|</ul?>|<ol?>|</ol?>|<dl?>|</dl?>|<li>|</li>|<dt?>|</dt?>|<dd?>|</dd?>)}i
      parts = page.split(tag_regex)

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
    def repair_headings(page)
      # Check if a Heading 1 exists: exactly one '=' at start/end of line
      return unless page.match?(/^=[^=]+=\s*$/)
      status('Detected H1 - reducing all heading levels.', 1, Status::Verbosity::LIGHT)

      # Loop from 5 down to 1 to increment levels safely
      5.downto(1) do |i|
        # Create strings of equals signs for current and next level
        current_markers = '=' * i
        next_markers    = '=' * (i + 1)

        # Regex explanation:
        # ^#{current_markers}  -> Starts with exactly 'i' equals signs
        # (.+?)                -> Captures the heading page (non-greedy)
        # #{current_markers}   -> Ends with exactly 'i' equals signs
        # \s*$                 -> Allows for trailing whitespace
        #
        # We use [^=] in the lookarounds to ensure we aren't matching
        # a higher-level heading (e.g., ensuring H2 doesn't match H3)
        find_regex = /^(?<!=)#{current_markers}([^=].+?[^=])#{current_markers}(?!=)\s*$/

        page.gsub!(find_regex) do |match|
          status("Replacing: #{match}", 0, Status::Verbosity::VERBOSE)
          puts 
          next_markers + Regexp.last_match(1) + next_markers
        end
      end

      status('Repaired all heading levels', 0, Status::Verbosity::VERBOSE)
      status("\n", -1, Status::Verbosity::VERBOSE)

      page
    end

    # Check page page for plain page names or explicit links and convert to
    # either [[PageName]] or {{icon|PageName}} when appropriate.
    def page_link_check(page_title, page, pages_main, icon_map)
      # Logging: mark start of page_link_check for this page
      status('Page link checking started', page_title, true, Status::Verbosity::VERBOSE)
      changed = false
      replacements = 0

      pages_main.each do |pname|
        next if pname == page_title
        next if pname.to_s.strip.empty?

        # If there's an explicit link [[Pagename]] and an icon exists, replace
        if icon_map[pname]
          link_regex = /\[\[\s*#{Regexp.escape(pname)}\s*\]\]/
          if page.match?(link_regex)
            page = page.gsub(link_regex, "{{icon|#{pname}}}")
            changed = true
            replacements += 1
            status('icon_replaced', pname, false, Status::Verbosity::VERBOSE)
          end
        end

        # If there's a plain exact match (word boundary) and no existing link,
        # convert the first occurrence to a link or icon template.
        link_exists = page.match(/\[\[\s*#{Regexp.escape(pname)}(?:\|[^\]]+)?\s*\]\]/)
        next if link_exists

        plain_regex = /(?<!\[\[)(?<!\w)#{Regexp.escape(pname)}(?!\w)/
        next unless page.match?(plain_regex)

        replacement = icon_map[pname] ? "{{icon|#{pname}}}" : "[[#{pname}]]"
        page = page.sub(plain_regex, replacement)
        changed = true
        replacements += 1
        status('plain_replaced', "#{pname} -> #{replacement}", false, Status::Verbosity::VERBOSE)
      end

      status('Page link updates:', { changed: changed, replacements: replacements }, false, Status::Verbosity::VERBOSE)
      [page, changed]
    end

    # Check and manage TOC based on heading count
    # If more than 10 headings: ensure {{TOC right}} exists
    # If 10 or fewer headings: remove any {{TOC}} or {{TOC right}}
    def manage_toc(page)
      # Count headings (== through ====== level, not including = on its own)
      heading_count = page.scan(/\n={2,6}[^=]/).length
      status('heading_count', heading_count, false, Status::Verbosity::VERBOSE)

      changed = false
      toc_status = nil

      if heading_count > 10
        # Need a TOC - check if one exists
        has_toc_right = page.include?('{{TOC right}}')
        has_toc = page.include?('{{TOC}}')

        return page, changed, heading_count, toc_status if has_toc_right

        if has_toc
          # Convert {{TOC}} to {{TOC right}}
          page = page.gsub('{{TOC}}', '{{TOC right}}')
          status('toc_converted', '{{TOC}} -> {{TOC right}}', false, Status::Verbosity::VERBOSE)
          toc_status = 'converted to {{TOC right}}'
          changed = true
        else
          # Add {{TOC right}} at the beginning (after any intro page before first heading)
          first_heading_idx = page.index(/\n={2,6}[^=]/)
          if first_heading_idx
            page.insert(first_heading_idx, "{{TOC right}}\n\n")
            status('toc_inserted', '{{TOC right}} added before first heading', false, Status::Verbosity::VERBOSE)
            toc_status = 'inserted {{TOC right}}'
            changed = true
          end
        end
        # return here for a bit of a cleaner method
        return page, changed, heading_count, toc_status
      end

      # 10 or fewer headings - remove any TOC
      if page.include?('{{TOC right}}')
        page = page.gsub('{{TOC right}}', '')
        status('toc_removed', 'Removed {{TOC right}} (<=10 headings)', false, Status::Verbosity::VERBOSE)
        toc_status = 'removed {{TOC right}}'
        changed = true
      elsif page.include?('{{TOC}}')
        page = page.gsub('{{TOC}}', '')
        status('toc_removed', 'Removed {{TOC}} (<=10 headings)', false, Status::Verbosity::VERBOSE)
        toc_status = 'removed {{TOC}}'
        changed = true
      end

      [page, changed, heading_count, toc_status]
    end



    
    # Extract glossary terms from tables on the Glossary page
    # Returns a hash of term => definition
    def get_glossary_terms(wiki)
      status('get_glossary_terms', 'fetching Glossary page', false, Status::Verbosity::VERBOSE)

      begin
        glossary_text = wiki.get_text('Glossary')
      rescue
        status('Glossary', 'page not found, skipping glossary tagging', false, Status::Verbosity::LIGHT)
        return {}
      end

      glossary_terms = {}

      # Extract all wiki tables {| ... |}
      # Tables contain rows separated by |-, cells separated by | or ||
      tables = glossary_text.scan(/\{\|(.*?)\|}/m)
      status('glossary_tables_found', tables.length, false, Status::Verbosity::VERBOSE)

      tables.each_with_index do |table_content, table_idx|
        status('processing_glossary_table', "table #{table_idx + 1}", false, Status::Verbosity::VERBOSE)
        rows = table_content.split(/^\|-/m)
        status('glossary_rows_count', rows.length, false, Status::Verbosity::VERBOSE)

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
            status('glossary_term', "#{term} => #{definition.truncate(50)}", false, Status::Verbosity::VERBOSE)
          end
        end
      end

      status('Glossary', "loaded #{glossary_terms.length} terms", false, Status::Verbosity::LIGHT) if glossary_terms.length.positive?
      glossary_terms
    end


    # Apply glossary tooltip tags to pages
    # Adds <abbr> tags with dashed border to first instance of each glossary term
    # Uses word boundaries for simple words
    # Only the first instance is tagged; other instances are unwrapped if they have abbr tags
    def apply_glossary_tags(page, glossary_terms)
      return page if glossary_terms.empty?

      status('apply_glossary_tags', "checking #{glossary_terms.length} terms", false, Status::Verbosity::VERBOSE)
      terms_found = 0
      terms_updated = 0
      terms_tagged = 0
      terms_matched = 0
      terms_removed = 0

      glossary_terms.each do |term, definition|
        status('checking_term', "#{term} => #{definition.truncate(50)}", false, Status::Verbosity::VERBOSE)
        escaped_term = Regexp.escape(term)

        # Find the first instance of the term anywhere on the page (wrapped or unwrapped)
        abbr_pattern = %r{<abbr[^>]*>#{escaped_term}</abbr>}
        plain_pattern = Regexp.new(word_boundary_pattern(term))

        abbr_match = page.match(abbr_pattern)
        plain_match = page.match(plain_pattern)

        # Determine which is first
        if abbr_match && plain_match
          first_is_abbr = abbr_match.begin(0) < plain_match.begin(0)
        elsif abbr_match
          first_is_abbr = true
        elsif plain_match
          first_is_abbr = false
        else
          # status("term_not_found", term, false, Status::Verbosity::VERBOSE)
          next
        end

        if first_is_abbr
          # First instance is already wrapped in abbr tag
          terms_matched += 1
          status('found_existing_abbr_first', term, false, Status::Verbosity::VERBOSE)

          # Check and update definition if it differs
          abbr_full = abbr_match[0]
          if abbr_full.match?(/title="([^"]*)"/)
            current_title = abbr_full.match(/title="([^"]*)"/)&.[](1)
            if current_title == definition
              status('glossary_definition_match', "#{term}: definition already matches", false, Status::Verbosity::VERBOSE)
            else
              updated_abbr = abbr_full.gsub(/title="[^"]*"/, %(title="#{definition}"))
              page = page.sub(abbr_full, updated_abbr)
              terms_updated += 1
              status('glossary_updated_first', "#{term}: changed from '#{current_title}' to '#{definition}'", false, Status::Verbosity::VERBOSE)
            end
          end

          # Remove abbr tags from any other instances of this term
          search_start = abbr_match.end(0)
          loop do
            remaining = page[search_start..]
            break unless remaining.match?(abbr_pattern)

            next_match = remaining.match(abbr_pattern)
            next_abbr_full = next_match[0]
            next_unwrapped = next_abbr_full.gsub(/<abbr[^>]*>/, '').gsub('</abbr>', '')
            search_end = search_start + next_match.end(0)
            page[search_start...search_end] = page[search_start...search_end].sub(next_abbr_full, next_unwrapped)
            terms_removed += 1
            status('glossary_removed_duplicate', "#{term}: unwrapped duplicate instance", false, Status::Verbosity::VERBOSE)
            search_start += next_unwrapped.length
          end

        else
          # First instance is plain (not wrapped) - wrap it
          terms_found += 1
          match_text = plain_match[0]
          match_idx = plain_match.begin(0)
          replacement = %(<abbr title="#{definition}">#{match_text}</abbr>)
          page = page[0...match_idx] + replacement + page[(match_idx + match_text.length)..]
          terms_tagged += 1
          status('glossary_tagged_first', "#{term}: #{definition.truncate(40)}", false, Status::Verbosity::VERBOSE)

          # Remove abbr tags from any other instances of this term
          unwrapped_abbr_pattern = %r{<abbr[^>]*>#{Regexp.escape(match_text)}</abbr>}
          while page.match?(unwrapped_abbr_pattern)
            match = page.match(unwrapped_abbr_pattern)
            page = page.sub(match[0], match_text)
            terms_removed += 1
            status('glossary_removed_duplicate', "#{term}: unwrapped duplicate instance", false, Status::Verbosity::VERBOSE)
          end
        end
      end

      status_msg = "found:#{terms_found} matched:#{terms_matched} updated:#{terms_updated} tagged:#{terms_tagged} removed:#{terms_removed}"
      status('glossary_summary', status_msg, false, Status::Verbosity::VERBOSE)
      page
    end



  end # class mw_linting


  # These methods don't belong to any one rules class, they operate across multiple

  # Helper function to apply word boundaries to simple words
  # Returns escaped pattern string with word boundaries if page is a simple word
  def word_boundary_pattern(page)
    escaped = Regexp.escape(page)
    # Check if the page is a simple word (only alphanumeric, underscores, hyphens, apostrophes)
    if page.match?(/^[\w\-']+$/)
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
      status('rule_preprocessed', "Added word boundaries to '#{find_pattern}'", false, Status::Verbosity::VERBOSE)
    end
    rules
  end

  class prose_linting(page)

    # force all headings into sentence case or title case 
    def heading_casing(page)
      # read casing from site cfg        
    end

  end


end
