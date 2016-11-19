require 'evoasm/gen/nodes'
require 'evoasm/gen/core_ext/array'

module Evoasm
  module Gen
    module Nodes
      module X64
        class Operands < Node
          include Enumerable

          def initialize(unit, instruction, operands_spec)
            super(unit)

            self.parent = instruction

            @imm_counter = 0
            @reg_counter = 0
            @operands = filter_operands(parse_operands_spec(operands_spec))
                          .map do |operand_name, operand_flags, read_flags, written_flags|
              Operand.new unit, self, operand_name, operand_flags, read_flags, written_flags
            end
          end

          def instruction
            parent
          end

          def [](index)
            @operands[index]
          end

          def empty?
            @operands.empty?
          end

          def size
            @operands.size
          end

          def each(&block)
            @operands.each(&block)
          end

          def next_imm_index
            c = @imm_counter
            @imm_counter += 1
            c
          end

          def next_reg_index
            c = @reg_counter
            @reg_counter += 1
            c
          end

          private

          def default_range(mode, operand_name)
            read = mode == :r
            vex = instruction.encodes_vex?

            case operand_name
            when 'xmm',  'XMM0'
              if vex
                (0..:vlmax)
              else
                (0..127)
              end
            when 'xmm/m64'
              if vex
                (0..:vlmax)
              else
                (0..63)
              end
            when 'xmm/m128'
            when 'xmm/m16'

            when 'ymm', 'ymm/m256'
              (0..256)
            when 'RAX', 'r/m64',
                 'r64', 'RSI',
                 'RDI',  'RDX', 'RCX', 'RBX', 'mm',
                 'mm/m64', 'RSP', 'RBP'
              (0..64)
            when 'EAX', 'ESI', 'EDI','EDX', 'ECX', 'EBX',
                  'r/m32', 'r32', 'xmm/m32', 'r32/m8', 'r32/m16'


            when 'AL', 'SIL', 'DIL'
              (0..7)
            when 'AH'
              (8..15)
            when 'AX', 'r/m8', 'r8', 'r/m16', 'r16', 'SI', 'DI',
                 'DX', 'SP', 'BP'
              # r/m8 can either be high or low byte
              (0..15)
            when 'imm8', 'imm16', 'imm32', 'OF', 'SF', 'ZF',
                 'AF', 'CF', 'PF', 'PE', 'UE', 'OE', 'DE', 'IE',
                 'rel32', 'RIP', 'DF', 'm8', '[SIL]', '[DIL]', '[SI]',
                 '[DI]', '[ESI]', '[EDI]', '[RSI]', '[RDI]', 'm64', 'm128',
                 'ZE', 'rel8', 'm256', 'm32', 'MM', 'FZ', 'RC', 'PM', 'UM', 'OM',
                 'ZM', 'DM', 'IM', 'DAZ', 'm16', 'IF', 'moffs8', 'moffs16', 'moffs32',
                 'moffs64', 'imm64'
              nil
            else
              raise "unknown operand #{operand_name}"
            end
          end

          def parse_operands_spec(operands_spec)
            operands_spec.split('; ').map do |op|
              op =~ /(.*?):(.*)/ || raise
              operand_name = $1
              operand_flags = $2.each_char.map(&:to_sym)
              [operand_name, operand_flags]
            end
          end

          def filter_operands(operands)
            rflags, operands = operands.reject do |name, _, _|
              next true if Gen::X64::IGNORED_MXCSR.include?(name.to_sym)
              next true if Gen::X64::IGNORED_RFLAGS.include?(name.to_sym)

              #FIXME
              next true if Gen::X64::MXCSR.include?(name.to_sym)

            end.partition do |name, _, _|
              Gen::X64::RFLAGS.include?(name.to_sym)
            end

            unless rflags.empty?
              written_flags = rflags.select do |_, operand_flags|
                operand_flags.include? :w
              end.map(&:first)

              read_flags = rflags.select do |_, operand_flags|;
                # NOTE: handling undefined as written
                operand_flags.include?(:w) || operand_flags.include?(:u)
              end.map(&:first)

              operand_flags = rflags.map(&:second).flatten.uniq.sort

              operands << ['RFLAGS', operand_flags, read_flags, written_flags]
            end

            operands
          end
        end
      end
    end
  end
end
