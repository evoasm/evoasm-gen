require 'evoasm/gen/to_c/state_machine_translator'

module Evoasm
  module Gen
    module InstructionToC
      private

      def c_function_name(unit)
        unit.symbol_to_c name, unit.arch_prefix
      end
    end
  end
end