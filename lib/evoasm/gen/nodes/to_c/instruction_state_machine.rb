module Evoasm
  module Gen
    module Nodes
      class InstructionStateMachine
        def c_function_name
          unit.symbol_to_c instruction.name, unit.architecture_prefix
        end
      end
    end
  end
end