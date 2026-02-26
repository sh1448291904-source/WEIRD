# frozen_string_literal: true

require 'weird/logging'
require 'pragmatic_segmenter'

# main Weird code
module Weird
  # TO DO
  # # Helper to load JSON files with error handling
  def load_json(file, critical)
    if File.Exists(file)
      JSON.parse(File.read(file))
      status('File loaded: ', file, false, :verbose)
    elsif critical
      status('Critical file not found: ', file)
      exit
    else
      status('File not found: ', file, false, :light)
    end
  rescue StandardError => e
    status("Unexpected error loading #{file}: #{e.message}")
    exit
  end

  # Helper to check for bot exclusion templates or __NOEDITSECTION__ on any page
  def should_edit?(text, bot_name)
    # Standard MediaWiki bot exclusion patterns
    # ARGY: should this just be ORs? ||?
    return false if text.include?('{{nobots}}')
    return false if text.match?(/\{\{bots\s*\|\s*deny\s*=\s*(all|#{Regexp.escape(bot_name)})\s*\}\}/i)
    return false if text.include?('{{donotbot}}')
    return false if text.include?('__NOEDITSECTION__')

    true
  end

  def rulefilename(name)
    pre = 'rules\\'
    ext = '.json'
    name = pre + name + ext
  end

  def load_rule_file(name)
    exit unless RULES_CONFIG[name]
    pathname = rulefilename(name)
    if File.file(pathname)
      file = load_json(pathname)
      status('Rules_file_loaded', "#{rules_file_config[:name]}: #{file_rules.length} rules", false, :verbose)
    else
      status('Expected rules file missing:', pathname)
    end
    file
  end

  def load_rules_files(rules)
    status('Loading rules files', rules, true, :light) # argy - new indent level
    rules.concat(load_rule_file('grammar'))
    rules.concat(load_rule_file('idioms'))
    rules.concat(load_rule_file('international_english'))
    rules.concat(load_rule_file('latin'))
    rules.concat(load_rule_file('mw_linting'))
    rules.concat(load_rule_file('prose_linting'))
    rules.concat(load_rule_file('typos')) # TO DO after loading make summary Typo: find => replace and we can kill the summary in file
    status('All rules files loaded. Total rules: ', rules.length, true, :light) # argy - close this indent level
    rules = enforce_word_boundaries(rules)
  end

  # Build list of main-namespace pages and map of available icon files
  def map_wiki(wiki, namespaces, pages_main, icon_map)
    # TODO: pages_main should just be a list of page titles
    pages_main = wiki.get_all_pages(namespace: 0) # this should use all main namespaces from config, if type cat then prefix with :
    status('Main pages count: ', pages_main.length, false, :light)
    icon_map = {}
    pages_main.each do |p|
      file_title = "File:#{p} icon.png"
      begin
        file_text = wiki.get_text(file_title)
      rescue StandardError
        file_text = nil
      end
      icon_map[p] = true unless file_text.nil?
    end
    status('Page-related icons count: ', icon_map.keys.length, false, :light)
  end

  def load_parameters
    OptionParser.new do |opts|
      opts.banner = 'Usage: WEIRD.rb [options]'

      opts.on('-cFILEPATH', '--config_filepath=FILEPATH', 'OPTIONAL: (String) Path to the configuration JSON file. Default WEIRD.cfg') do |n|
        config_filepath = n
      end

      opts.on('-lLEVEL', '--log-level=LEVEL', 'none | $light | $verbose') do |n|
        $log_level = n
      end

      opts.on('-v', '--$verbose', 'Same as -l$verbose') do |n|
        $log_level = Status::Verbosity :$verbose
      end

      opts.on('-s', '--simulate', 'OPTIONAL: Run in simulation mode') do |n|
        $simulate = n
      end
      $log_level = Status::Verbosity :$verbose if $simulate
      # TODO: logging levels
    end.parse!

    # Guard
    config_filepath = 'WEIRD.cfg' if config_filepath.nil
    status('Parameters loaded', 0, $light)
    status("config_filepath = #{config_filepath}", 1, $verbose)
    status("$log_level = #{$log_level}", 0, $verbose)
    status("$simulate = #{$simulate}", 0, $verbose)
    status("\n", -1, $verbose)

    config_filepath
  end

  def write_default_config(config_filepath)
    $config = [
      {
        'log' => {
          'path' => 'logs/',
          'prefix' => 'WEIRD_',
          'ext' => '.log'
        },
        site_list: 'sites/Sites.json'
      }
    ]
    File.write(config_filepath, JSON.pretty_generate($config))
    status("Default parameters written:\n", 0, $light)
    status($config, 1, $verbose)
    status('\n', -1, $verbose)
  end
end
