# frozen_string_literal: true

require 'logger'

module Weird
  # Things for logs/status messages
  # Use of status:
  #   none: site started ended, major sections entered. Also to STDOUT.
  #   light: how much work was done, minor sections entered. Also to STDOUT.
  #   verbose: almost a full stack trace. To logfilename.
  #
  # ARGY: This is somewhat rubbish
  # CURRENT Example use cases:
  # status('Always gunna log this', interesting_variable)
  # status('Heading', section_identifier_variable, true, logging_level)
  # status('Detail', interesting_variable,false,logging_level)
  # Noting that there is currently no mechanism in status for reducing indent
  # eg: the "true/false" needs to be more like +1, 0, -1, or keywords to that effect

  # ARGY: I am trying to provide an exposable enum for Verbosity
  # It should get used for LOG_LEVEL and each status call
  # When I produce a new function call to log
  # something, I want to be presented with a list of options for "level"

  # This is the user output handler.
  # It is used for everything from logging debugging info to indicating progress to the user,
  # to logging errors. Errors and high level messages are also written to the console.
  # I am going to be reading the logs when using new rules / sites, and I trigger verbose or simulate.
  class Status
    class Verbosity
      NONE = 0
      LIGHT = 1
      VERBOSE = 2
    end

    class ErrorLevel
      NONE = 0
      WARN = 1
      SERIOUS = 2
      FATAL = 3
    end

    # ANSI color codes
    class ANSI
      TEXT_DARK_YELLOW = '\e[33m'
      TEXT_BRIGHT_YELLOW = '\e[93m'
      TEXT_BRIGHT_RED = '\e[91m'
      RESET_ALL = '\e[0m'
    end

    def initialize
      now = Time.now.strftime('%Y%m%d_%H%M%S')
      l = CONFIG['log']
      @logfilename = l['path'] + l['prefix'] + now + l['ext']
      @status_indent = 0
      File.open(@logfilename, 'a') do |f|
        f << "Logging commenced at #{now}\n"
      end
    rescue StandardError => e
      puts "#{ANSI::TEXT_BRIGHT_RED}Unable to write to logfile #{@logfilename}. #{e} #{e.message}"
      puts e.backtrace.join("\n")
      puts "Terminating execution.#{ANSI::RESET_ALL}"
      exit
    end

    # The main workhorse
    def write(msg, indent_delta: 0, level: Verbosity::NONE, error_level: ErrorLevel::NONE)
      return unless level <= $log_level # rubocop:disable Style/GlobalVars

      # Guard
      if indent_delta.positive?
        indent_delta = 1
      elsif indent_delta.negative?
        indent_delta = -1
      end
      level = 0 if error_level.positive

      @status_indent += indent_delta
      return if msg == '' # it's just being used to adjust the indenting

      indentation = '  ' * @status_indent
      case error_level
      when ErrorLevel::NONE
        color = ''
        color_reset = ''
      when ErrorLevel::WARN
        color = ANSI::TEXT_DARK_YELLOW
      when ErrorLevel::SERIOUS
        color = ANSI::TEXT_BRIGHT_YELLOW
      when ErrorLevel::FATAL
        color = ANSI::TEXT_BRIGHT_RED
      else
        puts("#{ANSI::TEXT_BRIGHT_YELLOW}Unknown error_level #{error_level}#{ANSI::RESET_ALL}")
      end
      color_reset = ANSI::RESET_ALL unless color == '' # reset all colors

      output = indentation + color + msg + color_reset

      puts output if level == Verbosity::NONE

      File.open(@logfilename, 'a') do |f| # ARGY: Neater way?
        f << "#{output}\n"
      end
    end

    def std_err_writer(msg, e, error_level: Status::ErrorLevel::SERIOUS)
      status(msg, 0, 0, error_level)
      status("#{e} #{e.message}", 1, 0, error_level)
      status(e.backtrace.join("\n"), 0, 0, error_level)
      status('', -1)
    end
  end

  # Argy's error logging stuff.
  class Logging
    attr_reader :log_level

    def initialize(dest: $stderr, level: Logger::Severity::DEBUG)
      @logger = Logger.new(dest, level: level)
      @indent = 0
      @log_level = Logger::Severity.coerce(level)
      @enabled = true
    rescue ArgumentError
      @enabled = false
    end

    def status(var_name, value, level: Logger::Severity::DEBUG)
      return unless @enabled

      indent = ' ' * @indent
      @logger.log(level, "#{indent}> #{var_name}: #{value.inspect}")
    end

    def section(title, level: Logger::Severity::DEBUG)
      return unless @enabled

      @logger.log(level, "\n>>> #{title}")
      @indent = 1
    end

    def end_section(title, level: Logger::Severity::DEBUG)
      return unless @enabled

      @logger.log(level, "<<< #{title}")
      @indent = 0
    end
  end
end
