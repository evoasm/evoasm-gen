module Evoasm
  module Gen
    module Nodes
      class Instruction
        def c_constant_name
          unit.constant_name_to_c name, unit.architecture_prefix(:inst)
        end

        def ruby_ffi_name
          unit.constant_name_to_ruby_ffi name, unit.architecture_prefix(:inst)
        end
      end
    end
  end
end