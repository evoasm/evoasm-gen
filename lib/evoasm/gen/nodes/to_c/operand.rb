module Evoasm
  module Gen
    module Nodes
      class Operand
        def c_type_name
          unit.symbol_to_c :operand, unit.architecture_prefix, type: true
        end
      end
    end
  end
end