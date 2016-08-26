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
            io.puts '{'
            io.indent do
              io.puts operands.size, eol: ','
              io.puts c_constant_name, eol: ','
              io.puts parameters.size, eol: ','
              io.puts exceptions_bitmap, eol: ','
              io.puts flags_to_c, eol: ','
              io.puts "#{features_bitmap}ull", eol: ','

              parameters_to_c io
              operands_to_c io

              io.puts "(char *) #{unit.c_instruction_mnemonic_variable_name(self)}"
            end
            io.puts '}'
          end

          private

          def parameters_to_c(io)
            if parameters.empty?
              io.puts 'NULL,'
            else
              io.puts "(#{parameters.first.c_type_name} *)" + unit.c_instruction_parameters_variable_name(self), eol: ','
            end
            io.puts '(evoasm_x64_inst_enc_func_t)' + state_machine.c_function_name, eol: ','
          end

          def operands_to_c(io)
            if operands.empty?
              io.puts 'NULL,'
            else
              io.puts "(#{operands.first.c_type_name} *)#{unit.c_instruction_operands_variable_name(self)}", eol: ','
            end
          end
        end
      end
    end
  end
end
