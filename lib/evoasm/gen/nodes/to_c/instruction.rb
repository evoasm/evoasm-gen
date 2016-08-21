module Evoasm
  module Gen
    module Nodes
      class Instruction
        def c_function_name
          unit.symbol_to_c name, unit.architecture_prefix
        end

        def c_constant_name
          unit.constant_to_c name, unit.architecture_prefix(:inst)
        end

        def ruby_ffi_name
          unit.const_name_to_ruby_ffi name, unit.architecture_prefix(:inst)
        end
      end

      class Operand
        def c_type_name
          unit.symbol_to_c :operand, architecture_prefix, type: true
        end
      end
    end
  end
end