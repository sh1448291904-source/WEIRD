# WEIRD
Wiki EdIt Robot Daemon

Automated scripting tools to auto-edit wikis without supervision. Requires Ruby and MediaWiki-Butt-Ruby. A combination of an MW linter, a grammar checker, a standards enforcer for Timberborn, and a syntactic report tool. 

Some inputs:
* regex-based grammar rules: https://github.com/languagetool-org/languagetool/tree/master/languagetool-language-modules
* a linter for prose. rules are defined in YAML files. https://github.com/errata-ai/vale
* grammar nagger: https://github.com/automattic/harper
** sentence_capitalization.rs: Handles checking if the first word of a sentence is capitalized.
** spaces.rs: Detects multiple simultaneous spaces.
** an_a.rs: Logic for the correct use of "a" vs "an".
** harper-core/src/linting/phrase_corrections/
** https://writewithharper.com/docs/weir
** Dictionaries: Built-in: Located within the harper-core source.
