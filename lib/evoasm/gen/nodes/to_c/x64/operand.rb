module Evoasm
  module Gen
    module Nodes
      module X64
        class Operand
          def to_c(io)
            p 'operand#to_c'
            io.puts '{'
            io.indent do
              io.puts access.include?(:r) ? '1' : '0', eol: ','
              io.puts access.include?(:w) ? '1' : '0', eol: ','
              io.puts access.include?(:u) ? '1' : '0', eol: ','
              io.puts access.include?(:c) ? '1' : '0', eol: ','
              io.puts implicit? ? '1' : '0', eol: ','
              io.puts mnem? ? '1' : '0', eol: ','

              parameters = instruction.parameters
              if param
                param_idx = parameters.index(param) or \
                raise "param #{param} not found in #{parameters.map(&:name).inspect}" \
                        " (#{instruction.mnem}/#{instruction.index})"
                io.puts param_idx, eol: ','
              else
                io.puts parameters.size, eol: ','
              end

              io.puts unit.operand_type_to_c(type), eol: ','

              if size1
                io.puts unit.operand_size_to_c(size1), eol: ','
              else
                io.puts 'EVOASM_X64_N_OPERAND_SIZES', eol: ','
              end

              if size2
                io.puts unit.operand_size_to_c(size2), eol: ','
              else
                io.puts 'EVOASM_X64_N_OPERAND_SIZES', eol: ','
              end

              if reg_type
                io.puts unit.reg_type_to_c(reg_type), eol: ','
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
