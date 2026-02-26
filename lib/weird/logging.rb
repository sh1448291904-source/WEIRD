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
  
  class Status
    # The default output file should be logs/WEIRD.log, not $stderr,
    #   but can be overridden by the cfg file.
    #   (Moving away from parms to a cfg file because complexity).
    # I am going to be reading the logs when new rules / sites, and I trigger verbose.
    # Actual error errors should go to stdout for immediate action.

    attr_reader :log_level

    class Verbosity
      none = 0
      light = 1
      verbose = 2
    end

    def initialize
      now=Time.now.strftime('%Y%m%d_%H%M%S')
      l=CONFIG['log']
      @logfilename = l['path'] + l['prefix'] + now + l['ext']
      @status_indent = 0
    end
    
    def write(msg, indent_delta: 0, level: Verbosity:none) # ARGY
      return unless level<=log_level

      # Guard
      if indent_delta > 0 then
        indent_delta = 1
      elseif indent_delta <0 
        indent_delta = -1
      end

      @status_indent+=indent_delta
      indentation = '  ' * @status_indent

      output = "#{indentation}#{msg}"

      puts output if level <= light?

      File.open(@logfilename,"a") do |f|
        f << output + "\n"
      end
    end


  # Argy's error logging stuff
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
