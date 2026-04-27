# frozen_string_literal: true

RSpec.describe TermInfo do
  describe "module structure" do
    it "has a version number" do
      expect(TermInfo::VERSION).not_to be_nil
      expect(TermInfo::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    end

    it "defines an Error class" do
      expect(TermInfo::Error).to be < StandardError
    end

    it "extends Fiddle::Importer" do
      expect(TermInfo.singleton_class.ancestors).to include(Fiddle::Importer)
    end
  end

  describe "constants" do
    it "defines FUNCTION_SIGNATURE_MAPPING" do
      expect(TermInfo::FUNCTION_SIGNATURE_MAPPING).to be_a(Hash)
      expect(TermInfo::FUNCTION_SIGNATURE_MAPPING).to have_key('setupterm')
      expect(TermInfo::FUNCTION_SIGNATURE_MAPPING).to have_key('tigetstr')
      expect(TermInfo::FUNCTION_SIGNATURE_MAPPING).to have_key('tiparm')
      expect(TermInfo::FUNCTION_SIGNATURE_MAPPING).to have_key('tigetflag')
      expect(TermInfo::FUNCTION_SIGNATURE_MAPPING).to have_key('tigetnum')
    end

    it "defines TIGETSTR_ERROR_CODES" do
      expect(TermInfo::TIGETSTR_ERROR_CODES).to eq([0, -1])
      expect(TermInfo::TIGETSTR_ERROR_CODES).to be_frozen
    end
  end

  describe ".possible_curses_dll_search_names" do
    it "returns appropriate library names for the current platform" do
      names = TermInfo.possible_curses_dll_search_names
      expect(names).to be_an(Array)

      case RUBY_PLATFORM
      when /mingw/, /mswin/
        expect(names).to be_empty
      when /cygwin/
        expect(names).to include('cygncursesw-10.dll')
        expect(names).to include('cygncurses-10.dll')
      when /darwin/
        expect(names).to include('libncursesw.dylib')
        expect(names).to include('libcursesw.dylib')
      else
        expect(names).to include('libncursesw.so')
        expect(names).to include('libcursesw.so')
      end
    end
  end

  describe ".curses_dll_handle" do
    it "returns a consistent handle object" do
      handle1 = TermInfo.curses_dll_handle
      handle2 = TermInfo.curses_dll_handle
      expect(handle1).to equal(handle2)
    end

    it "returns nil or a Fiddle::Handle" do
      handle = TermInfo.curses_dll_handle
      expect(handle).to be_nil.or be_a(Fiddle::Handle)
    end
  end

  describe ".terminfo_functions" do
    it "returns a hash of function names to callables" do
      functions = TermInfo.terminfo_functions
      expect(functions).to be_a(Hash)
      expect(functions).to have_key('setupterm')
      expect(functions).to have_key('tigetstr')
      expect(functions).to have_key('tigetflag')
      expect(functions).to have_key('tigetnum')

      functions.each do |name, func|
        expect(name).to be_a(String)
        expect(func).to respond_to(:call)
      end
    end

    it "memoizes the result" do
      functions1 = TermInfo.terminfo_functions
      functions2 = TermInfo.terminfo_functions
      expect(functions1).to equal(functions2)
    end
  end

  describe ".call_terminfo!" do
    context "when function exists" do
      it "calls the function with given arguments" do
        expect(TermInfo.terminfo_functions).to receive(:fetch)
          .with('setupterm')
          .and_return(double(call: 'result'))

        expect(TermInfo.call_terminfo!(:setupterm, 'arg1', 'arg2')).to eq('result')
      end
    end

    context "when function does not exist" do
      it "raises NameError" do
        expect do
          TermInfo.call_terminfo!(:nonexistent_function)
        end.to raise_error(NameError, /nonexistent_function.*is not a defined terminfo function name/)
      end
    end
  end

  describe "terminfo wrapper functions" do
    before do
      # Skip actual terminfo calls in tests by default
      allow(TermInfo).to receive(:call_terminfo!)
    end

    describe ".setupterm" do
      it "accepts io and term parameters" do
        allow(TermInfo).to receive(:with_error_pointer).and_yield(double(to_i: 0))
        allow(TermInfo).to receive(:call_terminfo!).and_return(0)

        expect { TermInfo.setupterm(io: $stdout, term: 'xterm') }.not_to raise_error
      end

      context "when setupterm succeeds" do
        it "returns true for success code 0" do
          allow(TermInfo).to receive(:with_error_pointer).and_yield(double(to_i: 0))
          allow(TermInfo).to receive(:call_terminfo!).and_return(0)

          expect(TermInfo.setupterm).to eq(true)
        end
      end

      context "when setupterm fails" do
        it "raises appropriate error for terminal not usable with curses" do
          allow(TermInfo).to receive(:unpack_error_pointer).and_return(1)
          allow(TermInfo).to receive(:call_terminfo!).and_return(-1)

          expect { TermInfo.setupterm }.to raise_error(TermInfo::Error, /cannot be used with curses/)
        end

        it "raises appropriate error for terminal not found in terminfo db" do
          allow(TermInfo).to receive(:unpack_error_pointer).and_return(0)
          allow(TermInfo).to receive(:call_terminfo!).and_return(-1)

          expect { TermInfo.setupterm }.to raise_error(TermInfo::Error, /Could not find terminal in terminfo db/)
        end

        it "raises appropriate error for terminfo db not found" do
          allow(TermInfo).to receive(:unpack_error_pointer).and_return(-1)
          allow(TermInfo).to receive(:call_terminfo!).and_return(-1)

          expect { TermInfo.setupterm }.to raise_error(TermInfo::Error, /Could not find terminfo db/)
        end
      end
    end

    describe ".tigetstr" do
      it "accepts a capability name string" do
        pointer = double(to_i: 1, to_s: 'capability_string')
        allow(TermInfo).to receive(:call_terminfo!).and_return(pointer)

        result = TermInfo.tigetstr('bold')
        expect(result).to eq('capability_string')
      end

      it "raises error for invalid capability names" do
        pointer = double(to_i: 0)
        allow(TermInfo).to receive(:call_terminfo!).and_return(pointer)

        expect { TermInfo.tigetstr('invalid') }.to raise_error(TermInfo::Error, /Failed to find capability/)
      end

      it "raises error for error return codes" do
        pointer = double(to_i: -1)
        allow(TermInfo).to receive(:call_terminfo!).and_return(pointer)

        expect { TermInfo.tigetstr('invalid') }.to raise_error(TermInfo::Error, /Failed to find capability/)
      end
    end

    describe ".tigetflag" do
      it "returns true for flag set (return value 1)" do
        allow(TermInfo).to receive(:call_terminfo!).and_return(double(to_i: 1))

        expect(TermInfo.tigetflag('auto_margin')).to eq(true)
      end

      it "returns false for flag unset (return value 0)" do
        allow(TermInfo).to receive(:call_terminfo!).and_return(double(to_i: 0))

        expect(TermInfo.tigetflag('auto_margin')).to eq(false)
      end

      it "raises error for invalid flag name (return value -1)" do
        allow(TermInfo).to receive(:call_terminfo!).and_return(double(to_i: -1))

        expect { TermInfo.tigetflag('invalid') }.to raise_error(TermInfo::Error, /is not a flag capability name/)
      end

      it "raises error for unknown return values" do
        allow(TermInfo).to receive(:call_terminfo!).and_return(double(to_i: 99))

        expect { TermInfo.tigetflag('test') }.to raise_error(TermInfo::Error, /Unknown return value/)
      end
    end

    describe ".tigetnum" do
      it "returns numeric value for valid numeric capabilities" do
        allow(TermInfo).to receive(:call_terminfo!).and_return(double(to_i: 80))

        expect(TermInfo.tigetnum('columns')).to eq(80)
      end

      it "raises error for capability not found (return value -1)" do
        allow(TermInfo).to receive(:call_terminfo!).and_return(double(to_i: -1))

        expect { TermInfo.tigetnum('invalid') }.to raise_error(TermInfo::Error, /Could not find numeric capability/)
      end

      it "raises error for non-numeric capability name (return value -2)" do
        allow(TermInfo).to receive(:call_terminfo!).and_return(double(to_i: -2))

        expect { TermInfo.tigetnum('invalid') }.to raise_error(TermInfo::Error, /is not a numeric capability name/)
      end
    end
  end

  describe "private methods" do
    describe ".with_error_pointer" do
      it "yields an error pointer and returns result with error code" do
        result = TermInfo.send(:with_error_pointer) do |error_ptr|
          expect(error_ptr).to respond_to(:[])
          expect(error_ptr).to respond_to(:to_i)
          'test_result'
        end

        expect(result).to be_an(Array)
        expect(result.first).to eq('test_result')
        expect(result.last).to be_an(Integer)
      end
    end
  end
end
