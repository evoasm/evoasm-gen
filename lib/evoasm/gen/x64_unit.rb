require 'evoasm/gen/nodes/x64/instruction'
require 'evoasm/gen/nodes/enumeration'

module Evoasm
  module Gen
    module X64Unit
      include Nodes

      STATIC_PARAMETERS = %i(reg0 reg1 reg2 reg3).freeze

      attr_reader :access_masks
      attr_reader :exceptions
      attr_reader :register_types
      attr_reader :operand_types
      attr_reader :features
      attr_reader :instruction_flags
      attr_reader :register_ids
      attr_reader :address_sizes
      attr_reader :instruction_ids
      attr_reader :scales
      attr_reader :rflags_flags
      attr_reader :mxcsr_flags

      def parameter_ids(basic: false)
        if basic
          @basic_parameter_ids
        else
          @parameter_ids
        end
      end

      def undefinedable_parameter?(parameter_name, basic:)
        undefinedable_parameters(basic)[parameter_name]
      end

      private

      def load(table)
        load_instructions(table)
        load_enums
      end

      def load_enums
        @features = Enumeration.new self, :feature, prefix: architecture
        @instruction_flags = Enumeration.new self, :inst_flag, prefix: architecture, flags: true
        @exceptions = Enumeration.new self, :exception, prefix: architecture
        @register_types = Enumeration.new self, :reg_type, Gen::X64::REGISTERS.keys, prefix: architecture
        @operand_types = Enumeration.new self, :operand_type, Nodes::X64::Instruction::OPERAND_TYPES, prefix: architecture
        @register_ids = Enumeration.new self, :reg_id, Gen::X64::REGISTER_NAMES, prefix: architecture
        @access_masks = Enumeration.new self, :access_mask, %i(rest 64_127 32_63 16_31 8_15 0_7) + X64::RFLAGS, prefix: architecture, flags: true
        @address_sizes = Enumeration.new self, :addr_size, %i(64 32), prefix: architecture
        @scales = Enumeration.new self, :scale, %i(1 2 4 8), prefix: architecture
        @parameter_ids = Enumeration.new self, :param_id, STATIC_PARAMETERS, prefix: architecture
        @basic_parameter_ids = Enumeration.new self, :basic_param_id, STATIC_PARAMETERS, prefix: architecture
        @instruction_ids = Enumeration.new self, :inst_id, prefix: architecture
        @rflags_flags = Enumeration.new self, :rflags_flag, X64::RFLAGS, prefix: architecture
        @mxcsr_flags = Enumeration.new self, :mxcsr_flag, X64::MXCSR, prefix: architecture

        @undefinedable_parameters = {}
        @basic_undefinedable_parameters = {}

        #PARAMETER_ALIASES.each do |alias_key, key|
        #  @parameter_ids.define_alias alias_key, key
        #end

        #BASIC_PARAMETER_ALIASES.each do |alias_key, key|
        #  @basic_parameter_ids.define_alias alias_key, key
        #end


        @instructions.each do |instruction|
          @features.add_all instruction.features
          @instruction_flags.add_all instruction.flags
          @exceptions.add_all instruction.exceptions
          @instruction_ids.add instruction.name

          register_parameters(instruction, basic: false)
          register_parameters(instruction, basic: true) if instruction.basic?
        end

      end

      def helper_state_machine_nodes
        nodes_of_class Nodes::X64::VEX, Nodes::X64::REX, Nodes::X64::ModRMSIB
      end

      def load_instructions(table)

        @instructions = table.reject do |row|
          row[Nodes::X64::Instruction::COL_FEATURES] =~ /AVX512/
        end.map.with_index do |row, index|
          Nodes::X64::Instruction.new self, index, row
        end

        # make sure name is unique
        @instructions.group_by(&:name).each do |_name, group|
          next if group.size <= 1
          group.each_with_index do |instruction, index|
            instruction.resolve_name_conflict! index
          end
        end
      end

      def undefinedable_parameters(basic)
        if basic
          @basic_undefinedable_parameters
        else
          @undefinedable_parameters
        end
      end

      def register_parameters(instruction, basic:)
        parameters = instruction.parameters basic: basic
        parameter_ids(basic: basic).add_all parameters.map(&:name)
        parameters.each do |parameter|
          undefinedable_parameters(basic)[parameter.name] ||= parameter.undefinedable?
        end
      end
    end
  end
end
