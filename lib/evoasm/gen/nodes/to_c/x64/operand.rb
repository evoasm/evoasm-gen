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
              flags_to_c io

              parameters_to_c io

              io.puts operand_type_to_c(type), eol: ','

              size_to_c io, size1
              size_to_c io, size2

              register_type_to_c io

              if accessed_bits.key? :w
                io.puts unit.bit_mask_to_c(accessed_bits[:w]), eol: ','
              else
                io.puts unit.bit_masks.all_symbol_to_c, eol: ','
              end

              type_to_c io
            end
            io.puts '}'
          end

          private

          def flags_to_c(io)
            io.puts read? ? '1' : '0', eol: ','
            io.puts written? ? '1' : '0', eol: ','
            io.puts undefined? ? '1' : '0', eol: ','
            io.puts cwritten? ? '1' : '0', eol: ','
            io.puts implicit? ? '1' : '0', eol: ','
            io.puts mnemonic? ? '1' : '0', eol: ','
          end

          def parameters_to_c(io)
            parameters = instruction.parameters
            if parameter_name
              parameter_index = parameters.index do |parameter|
                parameter.name == parameter_name
              end

              if parameter_index.nil?
                raise "parameter #{parameter_name.inspect} for #{name} not found in"\
                        " #{parameters.map(&:name).inspect}" \
                        " (#{instruction.mnemonic}/#{instruction.index})"
              end
              io.puts parameter_index, eol: ','
            else
              io.puts parameters.size, eol: ','
            end
          end

          def size_to_c(io, size)
            if size
              io.puts operand_size_to_c(size), eol: ','
            else
              io.puts 'EVOASM_X64_N_OPERAND_SIZES', eol: ','
            end
          end

          def register_type_to_c(io)
            if register_type
              io.puts unit.register_type_to_c(register_type), eol: ','
            else
              io.puts unit.register_types.n_symbol_to_c, eol: ','
            end
          end

          def type_to_c(io)
            io.puts '{'
            io.indent do
              case type
              when :register, :rm
                if register
                  io.puts unit.register_name_to_c(register), eol: ','
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
        end
      end
    end
  end
end
