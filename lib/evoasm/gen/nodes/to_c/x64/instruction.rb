module Evoasm
  module Gen
    module Nodes
      module X64
        class Instruction

          def flags_to_c
            if flags.empty?
              '0'
            else
              flags.map do |flag|
                unit.constant_name_to_c flag, unit.architecture_prefix(:inst_flag)
              end.join ' | '
            end
          end

          def to_c(io)

            initializer = ToC::StructInitializer.new

            initializer[:n_operands] = operands.size
            initializer[:id] = c_constant_name
            initializer[:n_params] = parameters.size
            initializer[:exceptions] = exceptions_bitmap
            initializer[:flags] = flags_to_c
            initializer[:features] = "#{features_bitmap}ull"
            initializer[:params] = parameters_to_c
            initializer[:enc_func] = '(evoasm_x64_inst_enc_func_t)' + state_machine.c_function_name
            initializer[:basic_enc_func] =
              if basic?
                '(evoasm_x64_inst_enc_func_t)' + basic_state_machine.c_function_name
              else
                'NULL'
              end

            initializer[:operands] = operands_to_c
            initializer[:mnem] = "(char *) #{unit.c_instruction_mnemonic_variable_name(self)}"

            io.puts initializer.to_s
          end

          private

          def parameters_to_c
            if parameters.empty?
              'NULL'
            else
              "(#{parameters.first.c_type_name} *)" + unit.c_instruction_parameters_variable_name(self)
            end
          end

          def operands_to_c
            if operands.empty?
              'NULL'
            else
              "(#{operands.first.c_type_name} *)#{unit.c_instruction_operands_variable_name(self)}"
            end
          end
        end
      end
    end
  end
end
