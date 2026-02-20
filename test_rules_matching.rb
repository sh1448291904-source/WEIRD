require 'fileutils'
require 'list_matcher'
require 'regexp-examples'
require 'json'

# Configuration
RULES_DIR = "Rules"
RULES_NEW_SUFFIX = "_test_new"
RULES_STANDARD_SUFFIX = "_test-standard"
PASS_COLOR = "\e[32m"
FAIL_COLOR = "\e[31m"
RESET_COLOR = "\e[0m"
INFINITE_QUANTIFIER_PLACEHOLDER = "_LONG_STRING_"

# --- Example Usage ---
# Example 1: Pipe/Or logic
# puts generate_combinations("cat|dog") 
# Output: cat  dog

# Example 2: Infinite string replacement
# puts generate_combinations("beaver+") 
# Output: beaver_LONG_STRING_

def generate_combinations(regex_str)
  # 1. Clean the regex by replacing infinite quantifiers to simplify expansion.
  safe_regex_str = regex_str.gsub(/([\w\]])[\*\+]/, '\1' + INFINITE_QUANTIFIER_PLACEHOLDER)
                            .gsub(/([\w\]])\{\d+,\}/, '\1' + INFINITE_QUANTIFIER_PLACEHOLDER)

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
    
  rescue RegexpError => e
    "Error parsing regex: #{e.message}"
  end
end


def run_tests
  test_failures = 0
  
  # Find all the actual rules files
  rule_files = Dir.glob(File.join(RULES_DIR, "*")).reject do |f| 
    # Use File.file?(f) to ensure we don't try to process sub-folders
    !File.file?(f) || 
    f.include?(RULES_NEW_SUFFIX) || 
    f.include?(RULES_STANDARD_SUFFIX) || 
    f.downcase.include?("readme")
  end

rule_files.each do |rule_path|
  filename = File.basename(rule_path, ".*")
  ext = File.extname(rule_path)
  
  test_new_path = File.join(RULES_DIR, "#{filename}#{RULES_NEW_SUFFIX}#{ext}")
  test_standard_path = File.join(RULES_DIR, "#{filename}#{RULES_STANDARD_SUFFIX}#{ext}")

  puts "Testing: #{filename}..."

  # 1. Parse the JSON file
  begin
    json_data = JSON.parse(File.read(rule_path))
    
    # Ensure we are dealing with an array of rule objects
    rules_array = json_data.is_a?(Array) ? json_data : [json_data]

    # 2. Process each "find" field individually
    processed_content = rules_array.map do |rule|
      find_regex = rule["find"]
      
      if find_regex && !find_regex.strip.empty?
        # Generate combinations for the regex string found in the JSON
        generate_combinations(find_regex)
      else
        "" # Handle missing or empty "find" keys
      end
    end.join("\n") # Add a newline after each rule's result set

    # 3. Save result to _test_new
    File.write(test_new_path, processed_content + "\n")

    rescue JSON::ParserError => e
      puts "Error: Could not parse #{filename}. Ensure it is valid JSON. #{e.message}"
      test_failures += 1
      next
    end

    # 4. Compare with _test-standard
    standard_content = File.read(test_standard_path)
    
    if processed_content == standard_content
      puts "#{PASS_COLOR}  [PASS] Results match standard.#{RESET_COLOR}"
    else
      puts "#{FAIL_COLOR}  [FAIL] Results differ from standard! Diff below:#{RESET_COLOR}"
      output_diff(test_standard_path, test_new_path)
      test_failures += 1
    end
  end

  if test_failures > 0
    puts "\n#{FAIL_COLOR}Test Suite Failed with #{test_failures} failure(s).#{RESET_COLOR}"
    exit 1
  else
    puts "\n#{PASS_COLOR}All tests passed!#{RESET_COLOR}"
    exit 0
  end
end


def output_diff(file1, file2)
  # Uses the system's native diff command for clean output
  system("diff --color=always -u \"#{file1}\" \"#{file2}\"")
end


run_tests
