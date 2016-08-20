require 'evoasm/gen/nodes/x64/instruction'
require 'evoasm/gen/nodes/enum'

module Evoasm
  module Gen
    module X64Unit
      include Nodes

      STATIC_PARAMETERS = %i(reg0 reg1 reg2 reg3 imm)
      PARAMETER_ALIASES = {imm0: :imm, imm1: :disp, moffs: :imm0, rel: :imm0}

      attr_reader :bit_masks
      attr_reader :exceptions
      attr_reader :register_types
      attr_reader :operand_types
      attr_reader :features
      attr_reader :instruction_flags
      attr_reader :register_names
      attr_reader :displacement_sizes
      attr_reader :address_sizes
      attr_reader :parameter_names

      private

      def load(table)
        load_instructions(table)
        load_enums
      end

      def load_enums
        @features = Enum.new self, :feature, prefix: architecture
        @instruction_flags = Enum.new self, :inst_flag, prefix: architecture, flags: true
        @exceptions = Enum.new self, :exception, prefix: architecture
        @register_types = Enum.new self, :reg_type, Gen::X64::REGISTERS.keys, prefix: architecture
        @operand_types = Enum.new self, :operand_type, Nodes::X64::Instruction::OPERAND_TYPES, prefix: architecture
        @register_names = Enum.new self, :reg_id, Gen::X64::REGISTER_NAMES, prefix: architecture
        @bit_masks = Enum.new self, :bit_mask, %i(rest 64_127 32_63 0_31), prefix: architecture, flags: true
        @address_sizes = Enum.new self, :addr_size, %i(64 32), prefix: architecture
        @displacement_sizes = Enum.new self, :disp_size, %i(16 32), prefix: architecture

        @instructions.each do |inst|
          @features.add_all inst.features
          @instruction_flags.add_all inst.flags
          @exceptions.add_all inst.exceptions
        end

        @parameter_names = Enum.new self, :inst_param_id, STATIC_PARAMETERS, prefix: architecture
        PARAMETER_ALIASES.each do |alias_key, key|
          @parameter_names.alias alias_key, key
        end
      end

      def load_instructions(table)

        @instructions = table.reject do |row|
          row[Nodes::X64::Instruction::COL_FEATURES] =~ /AVX512/
        end.map.with_index do |row, index|
          Nodes::X64::Instruction.new(self, index, row)
        end

        # make sure name is unique
        @instructions.group_by(&:name).each do |_name, group|
          next if group.size <= 1
          group.each_with_index do |inst, index|
            inst.name << "_#{index}"
          end
        end
      end
    end
  end
end
