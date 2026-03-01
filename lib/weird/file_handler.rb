# frozen_string_literal: true

require 'weird/logging'
require 'pragmatic_segmenter'

# main Weird code
module Weird
  # TO DO

  # # Helper to load JSON files with error handling
  def load_json(file, critical)
    if File.Exists(file)
      jsonfile = JSON.parse(File.read(file))
      status("Loaded: #{file}", 0, Status::Verbosity::VERBOSE)
      jsonfile
    elsif critical
      status("Critical file not found: #{file}", 0, 0, Status::ErrorLevel::FATAL)
      exit
    else
      status("File not found: #{file}", 0, 0, Status::ErrorLevel::SEVERE)
      nil
    end
  rescue StandardError => e
    if critical
      std_err_writer("Unexpected error loading #{file}.", e, Status::ErrorLevel::FATAL)
      exit
    else
      std_err_writer("Unexpected error loading #{file}.", e, Status::ErrorLevel::SEVERE)
    end
  end

  def rule_file_path(name)
    pre = 'rules/'
    ext = '.json' # low pri - efficiency?
    pre + name + ext
  end

  # TODO: FUTURE: load into an array for re-use between wikis. Tiny relative performance hit as is.
  def load_rule_file(name)
    pathname = rule_file_path(name)
    if File.file(pathname)
      rules = load_json(pathname)
      status("#{rules.size} rules loaded from #{pathname}", 0, Status::Verbosity::LIGHT)
      status(rules, 1, Status::Verbosity::VERBOSE)
      status("\n", -1, Status::Verbosity::VERBOSE)
    else
      std_err_writer("Expected rules file missing: #{pathname}", e, Status::ErrorLevel::SEVERE)
    end
    rules
  end

  def write_default_config(config_filepath)
    # TODO: Keep in synch with actual file
    $config = [ # rubocop:disable Style/GlobalVars
      {
        log: {
          path: 'logs/',
          prefix: 'WEIRD_',
          ext: '.log'
        },
        site_list: 'sites/Sites.json',
        credentials_path: 'sites',
        credentials_suffix: '_creds.json'
      }
    ]
    File.write(config_filepath, JSON.pretty_generate($config)) # rubocop:disable Style/GlobalVars
    status("Default parameters written:\n", 0, 0, Status::ErrorLevel::WARN)
    status($config, 1, Status::Verbosity::VERBOSE) # rubocop:disable Style/GlobalVars
    status('', -1)
  rescue StandardError => e
    std_err_writer("Couldn't write default config: #{config_filepath}", e, Status::ErrorLevel::SEVERE)
  end

  def load_credentials(site_name)
    # Load creds
    credentials_filepath = $config['credentials_path'] + site_name + $config['credentials_suffix'] # rubocop:disable Style/GlobalVars
    status("credentials_filepath: #{credentials_filepath}", 0, Status::Verbosity::VERBOSE)
    if File.file(credentials_filepath)
      creds = load_json(credentials_filepath)
      if creds.nil
        status('Empty credentials file, skipping site.', 0, 0, Status::ErrorLevel::SEVERE)
        return nil
      elsif creds['username'].nil || creds['password'].nil
        status("Credentials file #{credentials_filepath} doesn't have username and password, skipping site.", 0, 0, Status::ErrorLevel::SEVERE)
        return nil
      end
      creds
    else
      status("No credentials file #{credentials_filepath}, skipping site.", 0, 0, Status::ErrorLevel::SEVERE)
      nil
    end
  end

  # very safe load text file as array of strings
  def load_txt(pathfilename)
    if File.file(pathfilename)
      text_file = File.readlines($config['site_list'], chomp: true).reject(&:empty?) # rubocop:disable Style/GlobalVars
      if text_file.nil
        status("Text file #{pathfilename} unexpectedly empty.", 0, 0, Status::ErrorLevel::SEVERE)
      else
        status("Text file #{pathfilename} loaded: #{text_file.size} lines.", 0, Status::Verbosity::LIGHT)
      end
      text_file
    else
      status("No such text file #{pathfilename}.", 0, 0, Status::ErrorLevel::WARN)
      nil
    end
  rescue StandardError => e
    std_err_writer("SEVERE error loading #{pathfilename}.", e, Status::ErrorLevel::SEVERE)
    nil
  end
end
