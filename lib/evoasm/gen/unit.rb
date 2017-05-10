require 'erubis'
require 'evoasm/gen/core_ext/string_io'
require 'evoasm/gen/nodes/enumeration'
require 'evoasm/gen/core_ext/string'

require 'evoasm/gen/nodes/x64/instruction'
require 'evoasm/gen/nodes/to_c/instruction'
require 'evoasm/gen/nodes/to_c/state_machine'
require 'evoasm/gen/nodes/to_c/enumeration'
require 'evoasm/gen/nodes/to_c/parameters_type'
require 'evoasm/gen/x64'
require 'evoasm/gen/x64_unit'
require 'evoasm/gen/unit'

module Evoasm
  module Gen

    class Unit
      attr_reader :architecture
      attr_reader :instructions
      attr_reader :parameters_type
      attr_reader :similar_instructions


      def initialize(arch, table, similar_insts)
        @architecture = arch
        @parameters_type = Nodes::ParametersType.new self

        extend Gen.const_get(:"#{arch.to_s.camelcase}Unit")
        load table

        @similar_instructions = similar_insts
      end

      def node(node_class, *array, **hash)
        @nodes ||= Hash.new { |h, k| h[k] = []}

        attrs = array.empty? ? hash : array

        node = @nodes[node_class].find do |node|
          node.match?(attrs)
        end

        return node if node

        if attrs.is_a? Hash
          add_node node_class, hash_to_attr_args(node_class, attrs)
        else
          add_node node_class, attrs
        end
      end

      def nodes_of_class(*node_classes)
        @nodes.values_at(*node_classes).flatten
      end

      def parameters_type_to_c(header:)
        @parameters_type.to_c header: header
      end

      def c_context_type
        "evoasm_#{architecture}_enc_ctx_t"
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
            elsif prefix && prefix.last =~ /scale/
              'scale' + ruby_ffi_name
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
        'int64_t'
      end

      def c_function_call(function_name, args, prefix = nil)
        "#{symbol_to_c function_name, prefix}(#{args.join ','})"
      end

      def nodes_of_class_to_c(*node_classes)
        nodes_to_c nodes_of_class(*node_classes)
      end

      def nodes_to_c(nodes)
        io = StringIO.new
        nodes.each do |node|
          node.to_c io
        end
        io.string
      end

      def permutation_tables_to_c
        nodes_of_class_to_c Nodes::PermutationTable
      end

      def unordered_writes_to_c
        nodes_of_class_to_c Nodes::UnorderedWrites
      end

      def state_machines_to_c
        nodes_to_c helper_state_machine_nodes
      end

      def domains_to_c
        nodes_of_class_to_c Nodes::EnumerationDomain, Nodes::RangeDomain
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
            io.write ','
          end
          io.puts '};'
          io.puts
        end
      end

      def instruction_state_machines_to_c
        nodes = @instructions.each_with_object([]) do |instruction, nodes|
          nodes << instruction.state_machine
          nodes << instruction.basic_state_machine if instruction.basic?
        end
        nodes_to_c nodes
      end

      def c_instruction_type_name
        "evoasm_#{architecture}_inst_t"
      end

      def instructions_to_c
        io = StringIO.new
        io.puts "static const #{c_instruction_type_name} #{c_static_instructions_variable_name}[] ="
        io.block do
          @instructions.each do |instruction|
            instruction.to_c(io)
            io.write ','
          end
        end
        io.write ';'
        io.puts "const #{c_instruction_type_name} *#{c_instructions_variable_name} = #{c_static_instructions_variable_name};"
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

      def flags_to_c(flags, flags_type)
        enum =
          case flags_type
          when :rflags
            rflags_flags
          when :mxcsr
            mxcsr_flags
          else
            raise "unknown flags operand #{flags_type}"
          end

        flags.map do |flag|
          "(1 << #{enum.symbol_to_c flag})"
        end.join('|')
      end

      def word_size_to_c(mask)
        case mask
        when Range
          word_sizes.symbol_to_c "#{mask.min}_#{mask.max}"
        when nil
          word_sizes.all_symbol_to_c
        else
          word_sizes.symbol_to_c mask.to_s
        end
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

      def c_parameters_type_name(basic)
        if basic
          'evoasm_x64_basic_params_t'
        else
          'evoasm_x64_params_t'
        end
      end

      def mnemonics_to_c
        io = StringIO.new

        @instructions.each do |instruction|
          variable_name = c_instruction_mnemonic_variable_name instruction
          io.puts "static const char #{variable_name}[] = "\
                  "\"#{instruction.mnemonic}\";"
        end

        io.string
      end

      private

      def hash_to_attr_args(node_class, hash)
        attrs = []
        node_class.attributes.each do |attr|
          attrs.push hash.delete attr
        end
        raise ArgumentError, "invalid attributes #{hash.keys}" unless hash.empty?
        attrs
      end

      def add_node(node_class, attrs)
        node = node_class.new self, *attrs
        @nodes[node_class] << node
        node
      end
    end
  end
end
