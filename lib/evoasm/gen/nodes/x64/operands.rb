require 'evoasm/gen/nodes'

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
            @operands = filter_operands(parse_operands_spec(operands_spec)).map do |name, flags, access|
              Operand.new unit, self, name, flags, access
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
            case operand_name
            when 'xmm', 'xmm/m128', 'XMM0', 'xmm/m16'
              if instruction.encodes_vex?
                (0..256)
              else
                (0..127)
              end
            when 'ymm', 'ymm/m256'
              (0..256)
            when 'EAX', 'RAX', 'r/m32', 'r/m64', 'r32',
                 'r64', 'xmm/m64', 'xmm/m32', 'ESI', 'EDI', 'RSI',
                 'RDI', 'EDX', 'ECX', 'EBX', 'RDX', 'RCX', 'RBX', 'mm',
                 'mm/m64', 'RSP', 'RBP', 'r32/m8', 'r32/m16'
              (0..64)
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
              name = $1

              flags = %i(m e).select { |flag| $2.include? flag.to_s }
              access = $2.scan(/(r|w|c)(?:\[(\d+)\.\.(\d+)\])?/).map do |mode, range_min, range_max|
                mode = mode.to_sym
                range = range_min && Range.new(range_min, range_max)
                [mode, range || default_range(mode, name)]
              end.to_h

              [name, flags, access]
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
              operands << [
                'RFLAGS',
                [],
                rflags.map { |name, _, access| [name.to_sym, access.keys.uniq] }.to_h
              ]
            end

            operands
          end
        end
      end
    end
  end
end
