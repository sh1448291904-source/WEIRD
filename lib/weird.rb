# frozen_string_literal: true

require 'weird/logging'
require 'pragmatic_segmenter'
require 'optparse'

# main Weird code
module Weird
  # TO DO

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

  def map_icons(page_titles)
    page_titles.each do |title|
      file_title = "File:#{title} icon.png"
      begin
        icon_map[page] = true if wiki.page_exists?(file_title)
      rescue StandardError => e # TODO: expand
        std_err_writer("Error with wiki.page_exists?(#{file_title}).", e, Status::ErrorLevel::WARN)
      end
    end
    status("Page-related icons count: #{icon_map.keys.size}", 0, Status::Verbosity::LIGHT)
  end

  # Adds a string prefix to every array element
  def prefix_array(prefix, array)
    array.map { |s| "#{prefix}#{s}" }
  end

  # Build list of page titles and map of matching icon files for main namespace only
  def map_wiki(wiki, namespaces, do_icon_mapping)
    # If the link titles isn't needed, the wiki config wont provide namespaces
    return if namespaces.nil?

    all_page_titles = []
    namespaces.each do |namespace|
      # we dont map file pages
      next if namespace == 6

      # TODO: site config for both these uses
      page_titles = wiki.get_all_pages_in_namespace(namespace: namespace) # this should use all main namespaces from config, if type cat then prefix with :
      status("Namespace: #{namespace} page count: #{page_titles.size}", 0, Status::Verbosity::LIGHT)
      icon_map = map_icons(page_titles) if namespace.zero? # only map icons for main namespace

      # Build page title list
      if namespace == 14 and wiki_config blah blah # categories
        status('Using category namespace titles', 1, Status::Verbosity::LIGHT)
        page_titles.map { |title| ":#{title}" }
        status(page_titles, 0, Status::Verbosity::VERBOSE)
        status('', -1, Status::Verbosity::VERBOSE)
      end

      all_page_titles.concat(page_titles)
    end
    status('Page titles: ', all_page_titles.size, 0, Status::Verbosity::LIGHT)
    [all_page_titles, icon_map]
  end

  def load_parameters
    OptionParser.new do |opts|
      opts.banner = 'Usage: WEIRD.rb [options]'

      opts.on('-cFILEPATH', '--config_filepath=FILEPATH', 'OPTIONAL: (String) Path to the configuration JSON file. Default WEIRD.cfg') do |n|
        config_filepath = n
      end

      opts.on('-lLEVEL', '--log-level=LEVEL', 'none | light | verbose') do |n|
        case n # ARGY, I am sure you have a clever way of simplfiying this
        when 'none'
          Status.log_level = Status::Verbosity::NONE
        when 'light'
          Status.log_level = Status::Verbosity::LIGHT
        when 'verbose'
          Status.log_level = Status::Verbosity::VERBOSE
        else
          status("Unknown log-level parameter value provided: #{n}")
        end
      end

      opts.on('-v', '--verbose', 'Same as --log-level=verbose') do |n|
        Status.log_level = Status::Verbosity::VERBOSE
      end

      opts.on('-s', '--simulate', 'OPTIONAL: Run in simulation mode') do |n|
        $simulate = n
      end
      Status.log_level = Status::Verbosity::VERBOSE if $simulate
    end.parse!

    # Guard
    config_filepath = 'WEIRD.cfg' if config_filepath.nil
    status('Parameters loaded', 0, Status::Verbosity::LIGHT)
    status("config_filepath = #{config_filepath}", 1, Status::Verbosity::VERBOSE)
    status("log_level = #{Status.log_level}", 0, Status::Verbosity::VERBOSE)
    status("$simulate = #{$simulate}", 0, Status::Verbosity::VERBOSE)
    status('', -1, Status::Verbosity::VERBOSE)

    config_filepath
  end

  # Guarded wrapper.
  # TODO FUTURE: Handle some exceptions properly, maybe add to end of queue to retry once
  #
  def wiki_connect(api_url)
    status("API URL #{api_url}", 0, Status::Verbosity::VERBOSE)
    MediaWiki::Butt.new(api_url)
  rescue StandardError => e
    std_err_writer("Error connecting to wiki at #{api_url}, skipping site.", e, Status::ErrorLevel::SEVERE)
    nil
  end

  def wiki_login(wiki, site_name)
    creds = load_credentials(site_name)
    err_msg = "Cannot log into #{sitename} as #{creds['username']}, skipping site."
    # login
    if wiki.login(creds['username'], creds['password'])
      status("Logged in as #{creds['username']}.", 0, Status::Verbosity::VERBOSE)
      true
    else
      status(err_msg, 0, 0, Status::ErrorLevel::SEVERE)
      false
    end
  rescue StandardError => e
    std_err_writer(err_msg, e, Status::ErrorLevel::SEVERE)
    false
  end

  # time numeric to human-friendly string
  def hhmmss(time_variable)
    hours   = (time_variable / 3600).to_i
    minutes = ((time_variable % 3600) / 60).to_i
    seconds = (time_variable % 60).to_i

    format('%02d:%02d:%02d', hours, minutes, seconds)
  end
end
