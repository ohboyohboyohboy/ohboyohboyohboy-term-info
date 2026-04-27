# frozen_string_literal: true

require 'fiddle'
require 'fiddle/import'
require 'yaml'

require_relative "term_info/version"

module TermInfo
  class Error < StandardError; end

  extend Fiddle::Importer

  FUNCTION_SIGNATURE_MAPPING = YAML.load(<<~YAML)
    ---
    setupterm:
      - setupterm -> voidp int voidp -> int
    tigetstr:
      - tigetstr -> voidp -> voidp
    tiparm:
      - tiparm -> voidp variadic -> voidp
      - tparm -> voidp variadic -> voidp
    tigetflag:
      - tigetflag -> voidp -> int
      - tgetflag -> voidp -> int
    tigetnum:
      - tigetnum -> voidp -> int
      - tgetnum -> voidp -> int
  YAML

  TIGETSTR_ERROR_CODES = [0, -1].freeze

  class << self
    def possible_curses_dll_search_names
      case RUBY_PLATFORM
      when /mingw/, /mswin/ # windows
        []
      when /cygwin/ # cygwin
        %w[cygncursesw-10.dll cygncurses-10.dll].freeze
      when /darwin/ # Mac OSX
        %w[libncursesw.dylib libcursesw.dylib libncurses.dylib libcurses.dylib].freeze
      else # Linux etc...
        %w[libncursesw.so libcursesw.so libncurses.so libcurses.so].freeze
      end
    end

    def curses_dll_handle
      unless defined?(@curses_dll_handle)
        @curses_dll_handle = discover_curses_dll_handle
      end
      @curses_dll_handle
    end

    def terminfo_functions
      @terminfo_functions ||= setup_terminfo_functions
    end

    def call_terminfo!(name, *args)
      function_ref =
        terminfo_functions.fetch(name.to_s) do
          fail NameError, "#{name.inspect} is not a defined terminfo function name"
        end
      function_ref.call(*args)
    end

    private

    def setup_terminfo_functions
      Hash[
        FUNCTION_SIGNATURE_MAPPING.map do |lib_function_name, signatures|
          function =
            signatures.detect do |signature|
              f = try_function_signature(signature) and break(f)
            end

          function ||= ->(*args) {
            fail NotImplementedError, "Failed to identify terminfo function #{lib_function_name.inspect}"
          }

          [lib_function_name.to_s, function]
        end
      ]
    end

    def try_function_signature(signature_spec)
      curses = curses_dll_handle

      function_name, arg_types, return_type = signature_spec.strip.split(%r[\s*->\s*], 3)
      arg_types = parse_fiddle_types(arg_types)
      return_type = parse_fiddle_types(return_type).first
      pointer = curses[function_name]

      Fiddle::Function.new(pointer, arg_types, return_type)
    rescue => error
      warn(error)
      nil
    end

    def parse_fiddle_types(type_list_string)
      type_list_string.downcase.strip.split(/\s+/).map do |type|
        constant = "TYPE_#{type.upcase}"
        Fiddle.const_get(constant)
      end
    end

    def discover_curses_dll_handle
      possible_curses_dll_search_names.each do |lib_name|
        handle = Fiddle.dlopen(lib_name) rescue nil
        return handle unless handle.nil?
      end
      nil
    end

    def with_error_pointer
      size = Fiddle::SIZEOF_INT
      error_pointer = Fiddle::Pointer.malloc(size)
      return_value = yield(error_pointer)
      error_code = unpack_error_pointer(error_pointer, size)

      [return_value, error_code]
    end

    def unpack_error_pointer(error_pointer, size)
      error_pointer[0, size].unpack1('i')
    end
  end

  #
  # Actual terminfo library wrapper functions
  #
  class << self
    def setupterm(io: $stdout, term: nil)
      file_no = io.to_i
      result_code, error_code =
        with_error_pointer do |error_ptr|
          call_terminfo!(:setupterm, term, file_no, error_ptr)
        end

      case result_code
      when 0 then true
      when -1
        case error_code
        when 1 then fail Error, "This terminal cannot be used with curses"
        when 0 then fail Error, "Could not find terminal in terminfo db"
        when -1 then fail Error, "Could not find terminfo db"
        else false
        end
      else false
      end
    end

    def tigetstr(capname_string)
      return_pointer = call_terminfo!(:tigetstr, capname_string.to_s)

      if TIGETSTR_ERROR_CODES.include?(return_pointer.to_i)
        fail Error, "Failed to find capability named `#{capname_string.inspect}'"
      end

      return_pointer.to_s
    end

    def tigetflag(capname_string)
      result = call_terminfo!(:tigetflag, capname_string.to_s).to_i

      case result
      when -1 then fail Error, "`#{capname_string.inspect}' is not a flag capability name"
      when 0 then false
      when 1 then true
      else fail Error, "Unknown return value: #{result}"
      end
    end

    def tigetnum(capname_string)
      result = call_terminfo!(:tigetnum, capname_string.to_s).to_i

      case result
      when -1 then fail Error, "Could not find numeric capability `#{capname_string.inspect}' "
      when -2 then fail Error, "`#{capname_string.inspect}' is not a numeric capability name"
      else result
      end
    end
  end
end
