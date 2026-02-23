# frozen_string_literal: true

require 'logger'

module Weird
  # Things for logs/status messages

  # ARGY: Always log any status messages ?? as well as them going to STDOUT with a timestamp??
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
