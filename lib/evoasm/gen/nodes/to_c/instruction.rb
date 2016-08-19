module Evoasm
  module Gen
    module Nodes
      class Instruction
        def c_function_name(unit)
          unit.symbol_to_c name, unit.arch_prefix
        end
      end
    end
  end
end