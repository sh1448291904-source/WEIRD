# frozen_string_literal: true

require 'weird/logging'
require 'pragmatic_segmenter'

# main Weird code
module Weird
  # TO DO
  # everything in this class is just pseudocode
  class Prepositions
    # part of the dubious check, must include
    words = %w[about above across after against along amid among around at before behind below beneath beside besides between beyond by
               concerning considering despite down during except for from in inside into like near of off on onto opposite out outside over past per regarding round since than through throughout till to toward towards under underneath unlike until up upon via with within without].freeze

    def count_preps(sentence)
      # TO DO use preps class to count preps in this sentence

      prepositions.words.each do |preposition|
        prep_count += sentence.regexpcount(preposition)
      end

      # might need to make it a ratio rather than an absolute
      summary "Verbosity: Many prepositions, try and recast: #{sentence}" if prep_count > 4
    end
  end

  # Will probably need to do paras then sentences to get \nl right if we do edits
  def preposition_check(page)
    ps = PragmaticSegmenter::Segmenter.new(text: page)
    ps.segment.each_with_index do |sentence, i|
      count_preps(sentence)
    end
  end
end
