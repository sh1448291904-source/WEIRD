# frozen_string_literal: true

require 'logger'

module Weird
  # Things for logs/status messages
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
