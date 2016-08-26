require 'erubis'
require 'evoasm/gen/core_ext/string_io'
require 'evoasm/gen/nodes/enumeration'
require 'evoasm/gen/core_ext/string'

require 'evoasm/gen/nodes/x64/instruction'
require 'evoasm/gen/nodes/to_c/instruction'
require 'evoasm/gen/nodes/to_c/state_machine'
require 'evoasm/gen/nodes/to_c/enumeration'
require 'evoasm/gen/x64'
require 'evoasm/gen/x64_unit'
require 'evoasm/gen/unit'

module Evoasm
  module Gen

    class CUnit < Unit
      attr_reader :architecture
      attr_reader :instructions

      def initialize(architecture, table)
        @architecture = architecture
        @nodes = []
        @parameter_names = []
        @undefinedable_paramters = {}

        extend Gen.const_get(:"#{architecture.to_s.camelcase}Unit")
        load table
      end

      def register_parameter(parameter_name, undefinedable)
        @parameter_names.add parameter_name
        @undefinable_parameters[parameter_name] ||= undefinedable
      end

      def c_context_type
        "evoasm_#{architecture}_inst_enc_ctx"
      end

      def namespace
        'evoasm'
      end

      def constant_name_to_c(name, prefix)
        symbol_to_c name, prefix, const: true
      end

      def constant_name_to_ruby_ffi(name, prefix)
        symbol_to_ruby_ffi name, prefix, const: true
      end

      def symbol_to_ruby_ffi(name, prefix = nil, const: false, type: false)
        ruby_ffi_name = name.to_s.downcase
        ruby_ffi_name =
          if ruby_ffi_name =~ /^\d+$/
            if prefix && prefix.last =~ /reg/
              'r' + ruby_ffi_name
            elsif prefix && prefix.last =~ /disp/
              'disp' + ruby_ffi_name
            elsif prefix && prefix.last =~ /addr/
              'addr_size' + ruby_ffi_name
            else
              raise
            end
          else
            ruby_ffi_name
          end

        ruby_ffi_name
      end

      def symbol_to_c(name, prefix = nil, const: false, type: false)
        c_name = [namespace, *prefix, name.to_s.sub(/\?$/, '')].compact.join '_'
        if const
          c_name.upcase
        elsif type
          c_name + '_t'
        else
          c_name
        end
      end

      def architecture_prefix(name = nil)
        ["#{architecture}", name]
      end

      def register_name_to_c(name)
        constant_name_to_c name, architecture_prefix(:reg)
      end

      def register_type_to_c(name)
        constant_name_to_c name, architecture_prefix(:reg_type)
      end

      def feature_name_to_c(name)
        constant_name_to_c name, architecture_prefix(:feature)
      end

      def c_instructions_variable_name
        "_evoasm_#{architecture}_insts"
      end

      def c_static_instructions_variable_name
        "_#{c_instructions_variable_name}"
      end

      def c_parameter_value_type_name
        symbol_to_c :inst_param_val, type: true
      end

      def c_bitmap_type_name
        symbol_to_c :bitmap, type: true
      end

      def c_function_call(function_name, args, prefix = nil)
        "#{symbol_to_c function_name, prefix}(#{args.join ','})"
      end

      def nodes_of_kind(node_class)
        @nodes.select { |node| node.is_a? node_class }
      end

      def nodes_of_kind_to_c(node_class)
        nodes_to_c nodes_of_kind node_class
      end

      def nodes_to_c(nodes)
        io = StringIO.new
        nodes.each do |node|
          node.to_c io
        end
        io.string
      end

      def permutation_tables_to_c
        nodes_of_kind_to_c Nodes::PermutationTable
      end

      def unordered_writes_to_c
        nodes_of_kind_to_c Nodes::UnorderedWrites
      end

      def state_machines_to_c
        nodes_of_kind_to_c Nodes::StateMachine
      end

      def domains_to_c
        nodes_of_kind_to_c Nodes::Domain
      end

      def parameters_to_c
        io = StringIO.new
        @instructions.each do |instruction|
          instruction_parameters_to_c instruction, io
        end
        io.string
      end

      def operands_to_c
        io = StringIO.new
        @instructions.each do |instruction|
          instruction_operands_to_c instruction, io
        end
        io.string
      end

      def instruction_parameters_to_c(instruction, io)
        parameters = instruction.parameters

        return if parameters.empty?

        io.puts "static const #{parameters.first.c_type_name} #{c_instruction_parameters_variable_name instruction}[] = {"
        io.indent do
          parameters.each do |parameter|
            io.puts '{'
            io.indent do
              io.puts parameter.c_constant_name, eol: ','
              io.puts '(evoasm_domain_t *) &' + parameter.domain.c_variable_name
            end
            io.puts '},'
          end
        end
        io.puts '};'
        io.puts
      end


      def instruction_operands_to_c(instruction, io)
        operands = instruction.operands

        return if operands.empty?

        io.puts "static const #{operands.first.c_type_name} #{c_instruction_operands_variable_name instruction}[] = {"
        io.indent do
          operands.each do |operand|
            operand.to_c io
          end
          io.puts '};'
          io.puts
        end
      end

      def instructions_to_c
        nodes_to_c @instructions.map(&:state_machine)
        nodes_to_c @instructions
      end

      def parameter_set_function(io = StringIO.new)
        io.puts 'void evoasm_x64_inst_params_set(evoasm_x64_inst_params_t *params, '\
                'evoasm_x64_inst_param_id_t param, evoasm_inst_param_val_t param_val) {'
        io.indent do
          io.puts 'switch(param) {'
          io.indent do
            @parameter_names.each do |parameter_name, _|
              next if @parameter_names.alias? parameter_name

              field_name = parameter_field_name parameter_name

              io.puts "case #{parameter_names.symbol_to_c parameter_name}:"
              io.puts "  params->#{field_name} = param_val;"
              if undefinedable_parameter? parameter_name
                io.puts "  params->#{field_name}_set = true;"
              end
              io.puts '  break;'
            end
          end
          io.puts '}'
        end

        io.puts '}'
        io.string
      end

      def max_parameters_per_instructions
        @instructions.map do |intruction|
          intruction.parameters.size
        end.max
      end

      def parameter_index_bitsize
        Math.log2(max_parameters_per_instructions + 1).ceil.to_i
      end

      def undefinedable_parameter?(parameter_name)
        @undefinedable_parameters[parameter_name]
      end

      def c_instruction_parameters_type_declaration(search: false)
        io = StringIO.new
        io.puts 'typedef struct {'
        io.indent do
          parameters =
            if search
              search_parameter_names
            else
              parameter_names.symbols.select do |key|
                !parameter_names.alias? key
              end
            end

          fields = []
          parameters.each do |parameter_name|
            field_name = parameter_field_name parameter_name

            fields << [field_name, c_parameter_bitsize(parameter_name, search: search)]

            if undefinedable_parameter? parameter_name
              fields << ["#{field_name}_set", 1]
            end
          end

          fields.sort_by do |name, bitsize|
            [bitsize, name]
          end.each do |param, size|
            io.puts "uint64_t #{param} : #{size};"
          end

          p fields.inject(0) { |acc, (n, s)| acc + s }./(64.0)
        end

        io.puts '} evoasm_x64_inst_params_t;'
        io.string
      end

      def bit_mask_to_c(mask)
        name =
          case mask
          when Range
            "#{mask.min}_#{mask.max}"
          else
            mask.to_s
          end
        constant_name_to_c name, architecture_prefix(:bit_mask)
      end

      def c_instruction_parameters_variable_name(instruction)
        "params_#{instruction.name}"
      end

      def c_instruction_mnemonic_variable_name(instruction)
        "mnem_#{instruction.name}"
      end

      def c_instruction_operands_variable_name(instruction)
        "operands_#{instruction.name}"
      end

      def mnemonics_to_c
        io = StringIO.new

        @instructions.each do |instruction|
          variable_name = c_instruction_mnemonic_variable_name instruction
          io.puts "static const char #{variable_name}[]"\
                  "\"#{instruction.mnemonic}\";"
        end

        io.string
      end

      private
      def parameter_field_name(param)
        param.to_s.sub(/\?$/, '')
      end

      def c_parameter_bitsize(parameter_name, search: false)
        case parameter_name
        when :rex_b, :rex_r, :rex_x, :rex_w,
          :vex_l, :force_rex?, :lock?, :force_sib?,
          :force_disp32?, :force_long_vex?, :reg0_high_byte?,
          :reg1_high_byte?
          1
        when :addr_size
          @address_sizes.bitsize
        when :disp_size
          @displacement_sizes.bitsize
        when :scale
          2
        when :modrm_reg
          3
        when :vex_v
          4
        when :reg_base, :reg_index, :reg0, :reg1, :reg2, :reg3, :reg4
          @register_names.bitsize
        when :imm
          search ? 32 : 64
        when :moffs, :rel
          64
        when :disp
          32
        when :legacy_prefix_order
          3
        else
          raise "missing C type for param #{parameter_name}"
        end
      end
    end
  end
end
