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
# Exclude all:
#  <blockquote>...</blockquote> 
#  :'''Character1:''' Line of dialogue.
#  :'''Character2:''' Response.
#  Used on "Quotes" subpages (e.g., CharacterName/Quotes). Each line is a bullet point,
#  grouped under headings by context (intro, win, loss, etc.)
#  Quote as a heading with bullets underneath.
#  Quote=
# Title casing or sentence casing for headings

require 'mediawiki/butt'
require 'json'
require 'time'
require 'lib/weird.rb'
require 'lib/WEIRD/dubious.rb' # ARGY - right?
require 'lib/WEIRD/logging.rb'

# Command line arguments
SIMULATE = ARGV.include?('--simulate')
$status_indent = 0


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




def process_site(site_cfg)
  site_name = site_cfg['name']
  report[site_name] = {} #TO DOL we dont need to keep reports for each site, we write them, close them, start a new one. IS THIS EVEN USED?

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

  # TODO: use all main namespaces nominated in config
  map_wiki(wiki, namespaces, pages_main, icon_map)


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
        applied_summaries << summary
      end

      # TO DO
      # All other page processing logics
      # 
      next if current_text == original_text

      report[site_name][title] = applied_summaries
      status('rules_applied', applied_summaries.length, false, :verbose)

      # Only write if there are non-dubious changes, or if in simulate mode
      if applied_summaries.empty? && !SIMULATE
        status('No changes to apply', title, false, :verbose)
        puts "    ◁ No changes to apply: #{title}"
      elsif SIMULATE
        puts "    ◇ Simulated: #{title}"
        # write the content to a copyedits_<sitename>.txt file
      else
        wiki.edit(title, current_text, summary:applied_summaries.join('; '), minor: true)
        puts "    ✓ Saved: #{title}"
        # append all dubious to the copyedits file (see above).  
      end
      # for memory minimization we should null sites after we write their stuff
    end
  end
end



start_time=Time.local
status("Dependencies loaded "), start_time.strftime('%Y%m%d_%H%M%S', true, :light)
status('simulation_mode', SIMULATE, false, :verbose)

sites = load_json('sites.json')
status('Sites loaded: ', sites.length, false, :light)

# TODO: Load all the old ARGV from a <sitename>_config.json
status('rules_disabled', RULES_CONFIG.reject { |_, v| v }.keys.join(', '), false, :verbose) if RULES_CONFIG.any? { |_, v| !v }

puts "\nStarting Wiki Trawl... #{SIMULATE ? '[SIMULATION]' : '[LIVE]'}"
runtime=Time.local-start_time
status('Initialization completed. Seconds:', runtime)

sites.each do |site_cfg|
  site_started=Time.local
  status('Starting ',site_cfg[Name],true)
  process_site(site.cfg)

  runtime=Time.local-site_started
  status("Finished #{site_cfg[Name]}. It took ", runtime.strftime(%H%M%S)) # ARGY: Need to pass indent-1 to logger somehow
end

# =========================================================
# ---               Report Generation                   ---
# =========================================================
# TODO: Accumulated stats
# status('total_pages_changed', total_pages_changed, false, :light)

runtime=Time.local-start_time
status ("Exiting. Runtime: ",runtime.strftime(%H%M%S))
