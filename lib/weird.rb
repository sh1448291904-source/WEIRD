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
# other sentence checking are:
#   verbosity: excessive adverb check (-ly word count)
#   too many conjunctions as probable run-on sentences.
#     for, and, nor, but, or, yet, so, commas, semicolons, whether, if, then, as, than, after, as long as,
#     as soon as, by the time, long before, now that, once, since, till, until, when, whenever, while
#     although, as far as, as if, as long as, as though, because, before, even if, even though, every time,
#     in order that, so that, that, though, unless, where, whereas, wherever
#   Check for repeated words, e.g., "the the", "and and", etc.

# Dubious
#   use sentence checking to show entire sentence for context
#   long sentences and suggest shorter sentences. Far future: autofix at conjunctions.
#   Show entire sentence containing the issue for the rules check, not just the word. This gives more
#   context to editors and makes it more likely they will understand the issue and fix it.
#   Build a white list of site name / page name / dubious rule combinations that are ignored,
#   to avoid repeatedly flagging the same false positives on the same pages. Editors can then
#   remove false positives from the whitelist into the actual site whitelist and fix what remains.
#   Check for passive voice, tricky to rephrase without changing meaning.
#   Subject/verb agreement issues, maybe flag as dubious if we can't be sure of the correct verb form.
#     Find a word form identifier solution. Eg: Is this word a verb, a noun...
  Class Dubious
    { name: 'dubious.json', enabled: RULES_CONFIG[:dubious]}

  end
end
