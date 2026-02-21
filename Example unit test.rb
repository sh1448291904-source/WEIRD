# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'add_plurals' # Links to your script

# TestPlurals
class TestPlurals < Minitest::Test
  def test_basic_pluralization
    # 'Arrange' - Setup your input
    input = 'Beaver'

    # 'Act' - Call your function
    result = add_plural_logic(input) # Replace with your actual function name

    # 'Assert' - Verify the output
    assert_equal 'Beavers', result
  end
end
