module Evoasm
  module Gen
    module Nodes
      module X64
        class Operand

          def operand_type_to_c(name)
            unit.constant_name_to_c name, unit.architecture_prefix(:operand_type)
          end

          def operand_size_to_c(size)
            unit.constant_name_to_c size, unit.architecture_prefix(:operand_size)
          end

          def to_c(io)
            io.puts '{'
            io.indent do
              io.puts read? ? '1' : '0', eol: ','
              io.puts written? ? '1' : '0', eol: ','
              io.puts undefined? ? '1' : '0', eol: ','
              io.puts cwritten? ? '1' : '0', eol: ','
              io.puts implicit? ? '1' : '0', eol: ','
              io.puts mnemonic? ? '1' : '0', eol: ','

              parameters = instruction.parameters
              if parameter_name
                parameter_index = parameters.index { |parameter| parameter.name == parameter_name }

                if parameter_index.nil?
                  raise "parameter #{parameter_name.inspect} for #{name} not found in"\
                        " #{parameters.map(&:name).inspect}" \
                        " (#{instruction.mnemonic}/#{instruction.index})"
                end
                io.puts parameter_index, eol: ','
              else
                io.puts parameters.size, eol: ','
              end

              io.puts operand_type_to_c(type), eol: ','

              if size1
                io.puts operand_size_to_c(size1), eol: ','
              else
                io.puts 'EVOASM_X64_N_OPERAND_SIZES', eol: ','
              end

              if size2
                io.puts operand_size_to_c(size2), eol: ','
              else
                io.puts 'EVOASM_X64_N_OPERAND_SIZES', eol: ','
              end

              if reg_type
                io.puts unit.register_type_to_c(reg_type), eol: ','
              else
                io.puts unit.register_types.n_symbol_to_c, eol: ','
              end

              if accessed_bits.key? :w
                io.puts unit.bit_mask_to_c(accessed_bits[:w]), eol: ','
              else
                io.puts unit.bit_masks.all_symbol_to_c, eol: ','
              end

              io.puts '{'
              io.indent do
                case type
                when :reg, :rm
                  if reg
                    io.puts unit.register_name_to_c(reg), eol: ','
                  else
                    io.puts unit.register_names.n_symbol_to_c, eol: ','
                  end
                when :imm
                  if imm
                    io.puts imm, eol: ','
                  else
                    io.puts 255, eol: ','
                  end
                else
                  io.puts '255'
                end
              end
              io.puts '}'
            end
            io.puts '}'
          end
        end
      end
    end
  end
end
