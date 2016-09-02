module Evoasm
  module Gen
    module Nodes
      class InstructionStateMachine
        def c_function_name
          function_name = unit.symbol_to_c instruction.name, unit.architecture_prefix
          function_name << '_basic' if basic?

          function_name
        end
      end
    end
  end
end