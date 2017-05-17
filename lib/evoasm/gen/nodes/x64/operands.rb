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
                          .map do |operand_name, operand_flags, read_flags, written_flags, maybe_written_flags|
              Operand.new unit, self, operand_name, operand_flags, read_flags, written_flags, maybe_written_flags
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

          def parse_operands_spec(operands_spec)
            operands_spec.split('; ').map do |op|
              op =~ /(.*?):(.*)/ || raise
              operand_name = $1
              operand_flags = $2.scan(/[a-z01]\??/).map(&:to_sym)
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
              read_flags = rflags.select do |_, operand_flags|
                operand_flags.include? :r
              end.map(&:first)

              written_flags = rflags.select do |_, operand_flags|
                operand_flags.include?(:'0') || operand_flags.include?(:'1')
              end.map(&:first)

              maybe_written_flags = rflags.select do |_, operand_flags|
                # NOTE: handling undefined as maybe_written
                operand_flags.include?(:w) || operand_flags.include?(:u)
              end.map(&:first)

              operands << ['RFLAGS', nil, read_flags, written_flags, maybe_written_flags]
            end

            operands
          end
        end
      end
    end
  end
end
