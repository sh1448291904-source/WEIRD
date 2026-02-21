# frozen_string_literal: true

require 'fileutils'
require 'list_matcher'
require 'regexp-examples'
require 'json'

# Configuration

RULES_NEW_SUFFIX = '_test_new'
RULES_STANDARD_SUFFIX = '_test-standard'
PASS_COLOR = "\e[32m"
FAIL_COLOR = "\e[31m"
RESET_COLOR = "\e[0m"

def generate_combinations(regex_str)
  any_string_quantifier = '_ANY_STRING_'
  # 1. Clean the regex by replacing infinite quantifiers, and look aheads/behinds/arounds to simplify expansion.
  safe_regex_str = regex_str.gsub(/([\w\]])[*+]/, "\\1#{any_string_quantifier}")
                            .gsub(/([\w\]])\{\d+,\}/, "\\1#{any_string_quantifier}")
                            .gsub(/\(\?<?[=!][^)]*\)/, any_string_quantifier.to_s) # lookaheads, lookbehinds, lookarounds: (?=...), (?!...), (?<=...), (?<!...)
                            .gsub(/\(\?[^)]*\)/, any_string_quantifier) # other non-capturing groups like (?i), (?m) etc
                            .gsub(/(?<!\\)\^/, '') # anchors: ^ (not escaped)
                            .gsub(/(?<!\\)\$/, '') # anchors: $
                            .gsub(/\\[bBAZz]/, '') # word boundary \b \B and string anchors \A \Z \z

  begin
    # 2. Convert string to a Ruby Regexp object
    regex_obj = Regexp.new(safe_regex_str)

    # 3. Use regexp-examples to generate all possible matching strings.
    # It handles complex groupings and pipes automatically.
    matches = regex_obj.examples

    # 4. Use List::Matcher as a final pass if you need to ensure the
    # results are reduced to a unique, clean set of strings.
    # Note: .examples already returns an array of strings.
    unique_matches = matches.uniq

    # 5. Return double space separated on a single line
    unique_matches.join('  ')
  rescue StandardError => e
    puts "Error parsing regex: #{e.message} for #{regex_str}"
  end
end

# FrozenStringLiteralComment
def load_actual_rules(dir, ext)
  Dir.glob(File.join(dir, "*#{ext}")).reject do |f|
    !File.file?(f) ||
      f.include?(RULES_NEW_SUFFIX) ||
      f.include?(RULES_STANDARD_SUFFIX) ||
      f.downcase.include?('readme')
  end
end

# FrozenStringLiteralComment
def run_tests
  rules_dir = 'Rules'
  rules_ext = '.json'
  test_failures = 0

  # Find all the actual rules files
  rule_files = load_actual_rules(rules_dir, rules_ext)

  rule_files.each do |rule_path|
    filename = File.basename(rule_path, rules_ext)

    test_new_path = File.join(rules_dir, "#{filename}#{RULES_NEW_SUFFIX}#{rules_ext}")
    test_standard_path = File.join(rules_dir, "#{filename}#{RULES_STANDARD_SUFFIX}#{rules_ext}")

    puts "Testing: #{filename}..."

    # 1. Parse the JSON file
    begin
      json_data = JSON.parse(File.read(rule_path))

      # Ensure we are dealing with an array of rule objects
      rules_array = json_data.is_a?(Array) ? json_data : [json_data]

      # 2. Process each "find" field individually
      processed_content = rules_array.map do |rule|
        find_regex = rule['find']

        if find_regex && !find_regex.strip.empty?
          # Generate combinations for the regex string found in the JSON
          generate_combinations(find_regex)
        else
          puts 'Found empty find key.'
          test_failures += 1
        end
      end.join("\n") # Add a newline after each rule's result set

      # 3. Save result to _test_new
      File.write(test_new_path, "#{processed_content}\n")

      # 4. Compare with _test-standard
      # If the standard file doesn't exist, we consider this a failure and skip comparison
      unless File.exist?(test_standard_path)
        puts "#{FAIL_COLOR}  [FAIL] Standard test file does not exist: #{test_standard_path}#{RESET_COLOR}"
        test_failures += 1
        next
      end

      standard_content = File.read(test_standard_path)

      if processed_content == standard_content
        puts "#{PASS_COLOR}  [PASS] Results match standard.#{RESET_COLOR}"
      else
        puts "#{FAIL_COLOR}  [FAIL] Results differ from standard! Diff below:#{RESET_COLOR}"
        output_diff(test_standard_path, test_new_path)
        test_failures += 1
      end
    rescue JSON::ParserError => e
      puts "Error: Could not parse #{filename}. Ensure it is valid JSON. #{e.message}"
      test_failures += 1
      next
    end

    if test_failures.positive?
      puts "\n#{FAIL_COLOR}Test Suite Failed with #{test_failures} failure(s).#{RESET_COLOR}"
      exit 1
    else
      puts "\n#{PASS_COLOR}All tests passed!#{RESET_COLOR}"
      exit 0
    end
  end
end

def output_diff(file1, file2)
  # Uses the system's native diff command for clean output
  system("diff --color=always -u \"#{file1}\" \"#{file2}\"")
end

run_tests
