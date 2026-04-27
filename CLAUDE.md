# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- **Run tests**: `rake spec` or `bundle exec rspec`
- **Install dependencies**: `bin/setup` or `bundle install`
- **Interactive console**: `bin/console`
- **Build gem**: `bundle exec rake build`
- **Install locally**: `bundle exec rake install`
- **Default task**: `rake` (runs specs)

## Architecture

This is a Ruby gem project with a standard structure:
- Main module: `TermInfo` in `lib/term_info.rb`
- Version defined in: `lib/term_info/version.rb`
- Tests use RSpec framework in `spec/` directory
- Gem specification in `term_info.gemspec`

The project is currently in early development stage with placeholder TODO content in the gemspec and README. The main module is mostly empty with just an Error class defined.

## Development Notes

- Ruby version requirement: >= 3.2.0
- Uses bundler for dependency management
- RSpec configuration in `.rspec` enables documentation format and color output
- Frozen string literals are enabled across all Ruby files