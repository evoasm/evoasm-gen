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

          def operand_word_to_c(register_word)
            unit.constant_name_to_c register_word, unit.architecture_prefix(:operand_word)
          end

          def to_c(io)
            initializer = ToC::StructInitializer.new

            {
              read?: 'read',
              written?: 'written',
              maybe_written?: 'maybe_written',
              implicit?: 'implicit',
              mnemonic?: 'mnem'
            }.each do |attr, field_name|
              initializer[field_name] = send(attr) ? '1' : '0'
            end

            initializer[:param_idx] = parameter_index
            initializer[:type] = operand_type_to_c(type)
            initializer[:word] = word_to_c word
            initializer[:size] = size_to_c size
            initializer[:reg_type] = register_type_to_c

            if flags?
              if read_flags&.any?
                initializer[:read_flags] = unit.flags_to_c(read_flags, flags_type)
              end
              if written_flags&.any?
                initializer[:written_flags] = unit.flags_to_c(written_flags, flags_type)
              end
            else
              implicit_imm_or_reg_to_c initializer
            end

            io.puts initializer.to_s
          end

          private

          def size_to_c(size)
            return 'EVOASM_X64_OPERAND_SIZE_NONE' if size.nil?
            operand_size_to_c(size)
          end

          def word_to_c(type)
            return 'EVOASM_X64_OPERAND_WORD_NONE' if word.nil?
            operand_word_to_c type
          end

          def parameter_index
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
              parameter_index
            else
              parameters.size
            end
          end

          def register_type_to_c
            if register_type
              unit.register_type_to_c(register_type)
            else
              unit.register_types.none_symbol_to_c
            end
          end

          def implicit_imm_or_reg_to_c(initializer)
            case type
            when :reg, :rm
              initializer[:reg_id] =
                if register
                  unit.register_name_to_c(register)
                else
                  unit.register_ids.none_symbol_to_c
                end
            when :imm
              initializer[:imm] =
                if imm
                  imm
                else
                  '-128'
                end
            else
              initializer[:unused] = '255u'
            end
          end
        end
      end
    end
  end
end
