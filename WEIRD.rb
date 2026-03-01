#!/usr/bin/env ruby
# frozen_string_literal: true

#
# WEIRD - Wiki EdIt Robot Daemon
#
# PARAMETERS:
#   --simulate                    Run in simulation mode (doesn't make actual edits). This also forces Status::Verbosity::VERBOSE.
#   --config_filepath = FILEPATH  Location of the configuration file for all other global parameters.
#   --log-level=LEVEL             Control logging verbosity:
#                                   - none     : No status messages (default)
#                                   - Status::Verbosity::LIGHT    : Key progress indicators (sites, rules, pages changed)
#                                   - Status::Verbosity::VERBOSE  : All status messages including details
#   --Status::Verbosity::VERBOSE                     Shorthand for --log-level=Status::Verbosity::VERBOSE
#
# EXAMPLES:
#   ruby WEIRD.rb
#   ruby WEIRD.rb --simulate
#   ruby WEIRD.rb --log-level=Status::Verbosity::LIGHT
#   ruby WEIRD.rb --log-level=Status::Verbosity::VERBOSE
#   ruby WEIRD.rb --Status::Verbosity::VERBOSE
#   ruby WEIRD.rb --simulate --no-typos --no-grammar
#
# GLOBAL $config FILE
#   log
#     path
#     prefix
#     ext
#   site_list = FILEPATH      Location of the json file containing the list of sites. Default: sites/Sites.json
#
# SITE $config FILES
#   api = URL
#
#   RULES PROCESSING
#   These are all disabled by default,
#   include them to enable them.
#
#   grammar
#   prose_linting
#      general
#      typos
#   mw_linting                                      mediawiki linting
#      force_heading_case: none, title, sentence
#      general
#      H1_fix
#      TOC_fix
#   international-english                           UK spellings to US
#   dubious                                         Produces a copyedits.txt of suggested changes
#   glossary                                        Takes terms and defs from a Glossary page and tags them in content.
#
#
#
#
# TO DO
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
require 'lib/weird'
require 'lib/WEIRD/dubious'
require 'lib/WEIRD/logging'
require 'lib/WEIRD/file_handler'

# simplified global wrapper - ARGY: Is there a better way to achieve this?

def status(msg, indent_delta: 0, level: Status::Verbosity::NONE, error_level: Status::ErrorLevel::NONE)
  Status.write(msg, indent_delta, level, error_level)
end

###############################################
###            Site loop (pages)            ###
###############################################
def process_site(site_name, site_cfg)
  # Initialize site
  # _______________

  # Connect
  wiki = wiki_connect(site_cfg['url'] + site_cfg['api_path'])
  if wiki.nil
    status("Unable to connect to wiki at #{site_cfg['url'] + site_cfg['api_path']}. Skipping wiki.", 0, 0, Status::ErrorLevel::SEVERE)
    return
  end

  # Login
  return unless wiki_login(wiki, site_name)

  # Pre-load all wiki-specific vars
  # _______________________________

  # Load glossary terms for this site (only if glossary is enabled)
  # Note that glossary terms are wiki specific, not global to all wikis
  glossary_terms = get_glossary_terms(wiki) if site_cfg['rules{glossary}']

  if site_cfg['rules{mw_linting{link_page_titles}}']
    pagenames, icon_map = map_wiki(wiki, site_cfg['wiki{namespaces}'], site_cfg['rules{mw_linting{icon_template}}'])
  end

  site_cfg['wiki{namespaces}'].each do |ns|
    # TODO: Careful with ns 6 (File)
    status('Starting namespace: #{ns}', 1, Status::Verbosity::VERBOSE)
    pages = wiki.get_all_pages(namespace: ns)
    status('pages_found', pages.length, false, Status::Verbosity::LIGHT)

    pages.each do |title|
      status('processing_page', title, false, Status::Verbosity::VERBOSE)
      original_text = wiki.get_text(title)
      next if original_text.nil

      # --- Bot Exclusion Check ---
      unless should_edit?(original_text, bot_user)
        puts "Skipping #{title}: Bot exclusion found."
        next
      end

      current_text = original_text.dup
      # Run icon/link checks and conversions before other rule-based edits
      begin
        new_text, icon_changed = page_link_check(title, current_text, pages_main, icon_map)
      rescue => e # rubbish?
        new_text = current_text
        icon_changed = false
        status('page_link_check_error', e.message, false, Status::Verbosity::VERBOSE)
      end
      # Status::Verbosity::LIGHT-level report: indicate whether pagelink/icon conversions occurred
      status('Page link added', icon_changed, false, Status::Verbosity::LIGHT)
      applied_summaries = []
      if icon_changed
        current_text = new_text
        applied_summaries << 'icon/link conversions'
      end

      if RULES_CONFIG[:mw_linting]
        # Manage TOC based on heading count (only if mw_linting is enabled)
        begin
          new_text, toc_changed, heading_count, toc_status = manage_toc(current_text)
        rescue => e # rubbish?
          new_text = current_text
          toc_changed = false
          heading_count = 0
          toc_status = nil
          status('manage_toc_error', e.message, false, Status::Verbosity::VERBOSE)
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
      if glossary_terms.length.positive
        begin
          new_text = apply_glossary_tags(current_text, glossary_terms)
          unless new_text = current_text
            glossary_changed = true
            current_text = new_text
            applied_summaries << 'glossary tooltips added'
          end
        rescue => e # rubbish?
          status('glossary_tags_error', e.message, false, Status::Verbosity::VERBOSE)
        end
      end

      rules.each do |rule|
        find_reg = Regexp.new(rule['find'])

        next unless current_text.match?(find_reg)

        # Collect matches for summary mapping
        matches = current_text.scan(find_reg).flatten
        status('rule_matched', rule['summary'].truncate(50), false, Status::Verbosity::VERBOSE)

        current_text.gsub!(find_reg, rule['replace'])
      end

      # TO DO
      # All other page processing logics
      #
      next if current_text == original_text

      report[site_name][title] = applied_summaries
      status('rules_applied', applied_summaries.length, false, Status::Verbosity::VERBOSE)

      # Only write if there are non-dubious changes, or if in simulate mode
      if applied_summaries.empty? && !SIMULATE
        status('No changes to apply', title, false, Status::Verbosity::VERBOSE)
        puts "    ◁ No changes to apply: #{title}"
      elsif $simulate
        puts "    ◇ Simulated: #{title}"
        # write the content to a copyedits_<sitename>.txt file
      else
        wiki.edit(title, current_text, summary: applied_summaries.join('; '), minor: true)
        puts "    ✓ Saved: #{title}"
        # append all dubious to the copyedits file (see above).
      end
      # for memory minimization we should null sites after we write their stuff
    end
  end
end

############################
###         Init         ###
############################

start_time = Time.local
status("Dependencies loaded at #{start_time.strftime('%Y%m%d_%H%M%S', 0, :none)}")

$simulate = false
config_filepath = load_parameters

# Load global config
if File.File?(config_filepath)
  $config = load_json(config_filepath, True)
  status('Parameters loaded:', 0, Status::Verbosity::VERBOSE)
  status('', 1)
  status($config, 0, Status::Verbosity::VERBOSE)
  status('', -1)

else # if there is no config file, write a default one
  status("No config file #{config_filepath}", 0, Status::Verbosity::VERBOSE)
  write_default_config(config_filepath)
end

if File.file?($config['site_list'])
  status('Reading site list from #{$config["site_list"]}', 0, Status::Verbosity::VERBOSE)
  sites = load_text($config['site_list'])
else
  status("No #{$config['site_list']} file with a list of site names to process.") # TODO: FUTURE: Logger?
  exit
end

if $log_level.positive
  runtime = Time.local - start_time
  status('Initialization completed. Runtime: #{runtime}', 0, Status::Verbosity::LIGHT)
end

###############################################
###            Main loop (sites)            ###
###############################################
sites.each do |site|
  site_start_time = Time.local
  status('Starting site: #{site}', 1)
  site_config = load_json('sites/#{site}.json') # TODO: Use global config
  next if site_config.nil

  status('Site config loaded.', 0, Status::Verbosity::LIGHT)
  status(site_config, 1, Status::Verbosity::VERBOSE)
  status("\n", -1, Status::Verbosity::VERBOSE)

  process_site(site, site_config)

  runtime = Time.local - site_started
  status("Finished #{site_cfg[Name]}. It took #{hhmmss(runtime)}.", 0, Status::Verbosity::LIGHT)
  status("\n", -1)
end

# =========================================================
# ---               Report Generation                   ---
# =========================================================
# TODO: Accumulated stats
# status('total_pages_changed', total_pages_changed, false, Status::Verbosity::LIGHT)

runtime = Time.local - start_time
status("Exiting. Runtime: #{hhmmss(runtime)}")
