require 'erubis'
require 'evoasm/gen/strio'
require 'evoasm/gen/nodes/enum'
require 'evoasm/gen/core_ext/string'

#require 'evoasm/gen/to_c/translator_util'
require 'evoasm/gen/nodes/x64/instruction'
require 'evoasm/gen/nodes/to_c/instruction'
require 'evoasm/gen/nodes/to_c/state_machine'
require 'evoasm/gen/nodes/to_c/enum'
require 'evoasm/gen/x64'
require 'evoasm/gen/x64_unit'
require 'evoasm/gen/unit'

module Evoasm
  module Gen

    module NameUtil
      def namespace
        'evoasm'
      end

      def constant_to_c(name, prefix)
        symbol_to_c name, prefix, const: true
      end

      def const_name_to_ruby_ffi(name, prefix)
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

      def base_arch_ctx_prefix(name = nil)
        ['arch_ctx', name]
      end

      def base_arch_prefix(name = nil)
        ['arch', name]
      end

      def arch_ctx_prefix(name = nil)
        ["#{architecture}_ctx", name]
      end

      def architecture_prefix(name = nil)
        ["#{architecture}", name]
      end

      def error_code_to_c(name)
        prefix = name == :ok ? :error_code : base_arch_prefix(:error_code)
        constant_to_c name, prefix
      end

      def register_name_to_c(name)
        constant_to_c name, architecture_prefix(:reg)
      end

      def exception_to_c(name)
        constant_to_c name, architecture_prefix(:exception)
      end

      def reg_type_to_c(name)
        constant_to_c name, architecture_prefix(:reg_type)
      end

      def operand_type_to_c(name)
        constant_to_c name, architecture_prefix(:operand_type)
      end

      def operand_size_to_c(size)
        constant_to_c size, architecture_prefix(:operand_size)
      end

      def feature_name_to_c(name)
        constant_to_c name, architecture_prefix(:feature)
      end

      def inst_flag_to_c(flag)
        constant_to_c flag, architecture_prefix(:inst_flag)
      end

      def inst_param_name_to_c(name)
        constant_to_c name, architecture_prefix(:inst_param)
      end

      def inst_params_var_name(inst)
        "params_#{inst.name}"
      end

      def inst_mnem_var_name(inst)
        "name_#{inst.name}"
      end

      def insts_var_name
        "_evoasm_#{architecture}_insts"
      end

      def static_insts_var_name
        "_#{insts_var_name}"
      end

      def inst_operands_var_name(inst)
        "operands_#{inst.name}"
      end

      def inst_param_domains_var_name(inst)
        "domains_#{inst.name}"
      end

      def param_domain_var_name(domain)
        case domain
        when Range
          "param_domain__#{domain.begin.to_s.tr('-', 'm')}_#{domain.end}"
        when Array
          "param_domain_enum__#{domain.join '_'}"
        when Symbol
          "param_domain_#{domain}"
        else
          raise "unexpected domain type #{domain.class} (#{domain.inspect})"
        end
      end

      def inst_enc_func_name(inst)
        symbol_to_c inst.name, architecture_prefix
      end

      def operand_c_type
        symbol_to_c :operand, architecture_prefix, type: true
      end

      def inst_param_c_type
        symbol_to_c :inst_param, type: true
      end

      def acc_c_type
        symbol_to_c :bitmap128, type: true
      end

      def inst_enc_ctx_c_type
        symbol_to_c "#{unit.architecture}_inst_enc_ctx", type: true
      end

      def inst_param_val_c_type
        symbol_to_c :inst_param_val, type: true
      end

      def bitmap_c_type
        symbol_to_c :bitmap, type: true
      end

      def inst_id_c_type
        symbol_to_c :inst_id, type: true
      end

      def pref_func_name(id)
        "prefs_#{id}"
      end

      def state_machine_ctx_var_name
        'ctx'
      end
    end

    class CUnit < Unit
      include NameUtil

      attr_reader :registered_param_domains

      attr_reader :architecture

      attr_reader :instructions

      OUTPUT_FORMATS = %i(c h ruby_ffi)

      def initialize(architecture, table)
        @architecture = architecture
        @pref_funcs = {}
        @called_funcs = {}

        @functions = []

        @state_machine_functions = {}

        @registered_param_domains = Set.new

        @permutation_tables = []
        @unordered_writes = []
        @nodes = []
        @parameter_domains = []
        @parameters = []
        @operands = []
        @mnemonics = []

        extend Gen.const_get(:"#{architecture.to_s.camelcase}Unit")
        load table
      end

      def register_parameter(param_name)
        @parameter_names.add param_name
      end

      def c_context_type
        "evoasm_#{architecture}_inst_enc_ctx"
      end

      def request_permutation_table(n)
        @permutation_tables ||= Hash.new { |h, k| h[k] = (0...k).to_a.permutation }
        [permutation_table_var_name(n), @permutation_tables[n].size]
      end

      def c_function_call(function_name, args, prefix = nil)
        "#{symbol_to_c function_name, prefix}(#{args.join ','})"
      end

      def nodes_of_kind(node_class)
        @nodes.select { |node| node.kind_of? node_class}
      end

      def nodes_of_kind_to_c(node_class)
        nodes_to_c nodes_of_kind node_class
      end

      def nodes_to_c(nodes)
        io = StrIO.new
        nodes.each do |node|
          node.to_c io
        end
        io.string
      end

      def permutation_tables_to_c
        nodes_of_kind_to_c Nodes::PermutationTable
      end

      def unordered_writes_to_c
        nodes_of_kind_to_c Nodes::PermutationTable
      end

      def state_machines_to_c
        nodes_of_kind_to_c Nodes::StateMachine
      end

      def domains_to_c
        nodes_of_kind_to_c Nodes::Domain
      end

      def parameters_to_c
        @instructions.each do |instruction|
          instruction_parameters_to_c instruction
        end
      end

      def operands_to_c
        @instructions.each do |instruction|
          instruction_operands_to_c instruction
        end
      end

      def instruction_parameters_to_c(instruction)
        io = StrIO.new
        parameters = instruction.parameters

        return if parameters.empty?

        io.puts "static const #{parameters.first.c_type_name} params_#{instruction.name}[] = {"
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
        io.string
      end

      def instruction_operands_to_c(instruction)
        io = StrIO.new
        operands = instruction.operands

        return if operands.empty?

        # io.puts "static const #{operands.first.c_type_name} #{inst_operands_var_name translator.inst}[] = {"
        #   io.indent do
        #     translator.inst.operands.each do |op|
        #       inst_operand_to_c(translator, op, io, eol: ',')
        #     end
        #   end
        #   io.puts '};'
        #   io.puts
        # end

        io.string
      end

      def instructions_to_c
        nodes_to_c @instructions
      end

      def parameter_set_function(io = StrIO.new)
        io.puts 'void evoasm_x64_inst_params_set(evoasm_x64_inst_params_t *params, evoasm_x64_inst_param_id_t param, evoasm_inst_param_val_t param_val) {'
        io.indent do
          io.puts "switch(param) {"
          io.indent do
            @parameter_names.each do |param_name, _|
              next if @parameter_names.alias? param_name

              field_name = parameter_field_name param_name

              io.puts "case #{parameter_names.symbol_to_c param_name}:"
              io.puts "  params->#{field_name} = param_val;"
              io.puts "  params->#{field_name}_set = true;"
              io.puts "  break;"
            end
          end
          io.puts '}'
        end

        io.puts '}'
        io.string
      end

      def max_params_per_inst
        @instructions.map do |intruction|
          intruction.parameters.size
        end.max
      end

      def param_idx_bitsize
        Math.log2(max_params_per_inst + 1).ceil.to_i
      end

      def inst_params_type_decl_to_c(io = StrIO.new)
        io.puts 'typedef struct {'
        io.indent do
          params = parameter_names.symbols.select { |key| !parameter_names.alias? key }.flat_map do |param_name|
            field_name = parameter_field_name param_name
            [
              [field_name, param_c_bitsize(param_name)],
              ["#{field_name}_set", 1],
            ]
          end.sort_by { |n, s| [s, n] }

          params.each do |param, size|
            io.puts "uint64_t #{param} : #{size};"
          end

          p params.inject(0) { |acc, (n, s)| acc + s }./(64.0)
        end

        io.puts '} evoasm_x64_inst_params_t;'
        io.string
      end

      def bit_mask_to_c(mask)
        name =
          case mask
          when Range then
            "#{mask.min}_#{mask.max}"
          else
            mask.to_s
          end
        constant_to_c name, architecture_prefix(:bit_mask)
      end

      private
      def register_param_domain(domain)
        @registered_param_domains << domain
      end


      def render_templates(file_type, binding, &block)
        target_filenames = self.class.target_filenames(architecture, file_type)

        target_filenames.each do |target_filename|
          template_path = self.class.template_path(target_filename)
          renderer = Erubis::Eruby.new(File.read(template_path))
          block[target_filename, renderer.result(binding), file_type]
        end
      end

      def translate_x64_ruby_ffi(&block)
        render_templates(:ruby_ffi, binding, &block)
      end

      def translate_x64_h(&block)
        render_templates(:h, binding, &block)
      end

      def translate_x64_c(&block)
        # NOTE: keep in correct order
        inst_funcs = inst_funcs_to_c
        pref_funcs = pref_funcs_to_c
        permutation_tables = permutation_tables_to_c
        called_funcs = called_funcs_to_c
        insts_c = insts_to_c
        inst_operands = inst_operands_to_c
        inst_mnems = inst_mnems_to_c
        inst_params = inst_params_to_c
        inst_params_type_decl = inst_params_type_decl_to_c
        inst_params_set_func = parameter_set_function
        param_domains = param_domains_to_c

        render_templates(:c, binding, &block)
      end

      def translate_instructions
        insts
      end

      def inst_funcs_to_c(io = StrIO.new)
        @inst_translators = insts.map do |inst|
          inst_translator = StateMachineCTranslator.new architecture, self
          inst_translator.emit_inst_func io, inst

          inst_translator
        end
        io.string
      end

      def called_funcs_to_c(io = StrIO.new)
        @called_funcs.each do |func, (id, translators)|
          func_translator = StateMachineCTranslator.new architecture, self
          func_translator.emit_called_func io, func, id

          translators.each do |translator|
            translator.merge_params func_translator.parameters
          end
        end

        io.string
      end

      def inst_to_c(io, inst, params)
        io.puts '{'
        io.indent do
          io.puts inst.operands.size, eol: ','
          io.puts inst_name_to_c(inst), eol: ','
          io.puts params.size, eol: ','
          io.puts exceptions_bitmap(inst), eol: ','
          io.puts inst_flags_to_c(inst), eol: ','
          io.puts "#{features_bitmap(inst)}ull", eol: ','

          if params.empty?
            io.puts 'NULL,'
          else
            io.puts "(#{inst_param_c_type} *)" + inst_params_var_name(inst), eol: ','
          end
          io.puts '(evoasm_x64_inst_enc_func_t)' + inst_enc_func_name(inst), eol: ','

          if inst.operands.empty?
            io.puts 'NULL,'
          else
            io.puts "(#{operand_c_type} *)#{inst_operands_var_name inst}", eol: ','
          end

          io.puts "(char *) #{inst_mnem_var_name(inst)}"
        end
        io.puts '},'
      end

      def insts_to_c(io = StrIO.new)
        io.puts "static const evoasm_x64_inst_t #{static_insts_var_name}[] = {"
        @inst_translators.each do |translator|
          inst_to_c io, translator.inst, translator.parameters
        end
        io.puts '};'
        io.puts "const evoasm_x64_inst_t *#{insts_var_name} = #{static_insts_var_name};"

        io.string
      end

      def inst_param_to_c(io, inst, params, param_domains)
        return if params.empty?
        io.puts "static const #{inst_param_c_type} #{inst_params_var_name inst}[] = {"
        io.indent do
          params.each do |param|
            param_domain = param_domains[param] || inst.param_domain(param)
            register_param_domain param_domain

            io.puts '{'
            io.indent do
              io.puts inst_param_name_to_c(param), eol: ','
              io.puts '(evoasm_domain_t *) &' + param_domain_var_name(param_domain)
            end
            io.puts '},'
          end
        end
        io.puts '};'
        io.puts
      end

      def inst_params_to_c(io = StrIO.new)
        @inst_translators.each do |translator|
          inst_param_to_c io, translator.inst, translator.parameters, translator.param_domains
        end

        io.string
      end

      def parameter_field_name(param)
        param.to_s.sub(/\?$/, '')
      end

      def param_c_bitsize(param_name)
        case param_name
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
          64
        when :moffs, :rel
          64
        when :disp
          32
        when :legacy_prefix_order
          3
        else
          raise "missing C type for param #{param_name}"
        end
      end

      def inst_operand_to_c(translator, op, io = StrIO.new, eol:)
        io.puts '{'
        io.indent do
          io.puts op.access.include?(:r) ? '1' : '0', eol: ','
          io.puts op.access.include?(:w) ? '1' : '0', eol: ','
          io.puts op.access.include?(:u) ? '1' : '0', eol: ','
          io.puts op.access.include?(:c) ? '1' : '0', eol: ','
          io.puts op.implicit? ? '1' : '0', eol: ','
          io.puts op.mnem? ? '1' : '0', eol: ','

          params = translator.parameters.reject { |p| State.local_variable_name? p }
          if op.param
            param_idx = params.index(op.param) or \
              raise "param #{op.param} not found in #{params.inspect}" \
                      " (#{translator.inst.mnem}/#{translator.inst.index})"

            io.puts param_idx, eol: ','
          else
            io.puts params.size, eol: ','
          end

          io.puts operand_type_to_c(op.type), eol: ','

          if op.size1
            io.puts operand_size_to_c(op.size1), eol: ','
          else
            io.puts 'EVOASM_X64_N_OPERAND_SIZES', eol: ','
          end

          if op.size2
            io.puts operand_size_to_c(op.size2), eol: ','
          else
            io.puts 'EVOASM_X64_N_OPERAND_SIZES', eol: ','
          end

          if op.reg_type
            io.puts reg_type_to_c(op.reg_type), eol: ','
          else
            io.puts reg_types.n_symbol_to_c, eol: ','
          end

          if op.accessed_bits.key? :w
            io.puts bit_mask_to_c(op.accessed_bits[:w]), eol: ','
          else
            io.puts bit_masks.all_symbol_to_c, eol: ','
          end

          io.puts '{'
          io.indent do
            case op.type
            when :reg, :rm
              if op.reg
                io.puts register_name_to_c(op.reg), eol: ','
              else
                io.puts reg_names.n_symbol_to_c, eol: ','
              end
            when :imm
              if op.imm
                io.puts op.imm, eol: ','
              else
                io.puts 255, eol: ','
              end
            else
              io.puts '255'
            end
          end
          io.puts '}'
        end
        io.puts '}', eol: eol
      end

      def inst_operands_to_c(io = StrIO.new)
        @inst_translators.each do |translator|
          next if translator.inst.operands.empty?
          io.puts "static const #{operand_c_type} #{inst_operands_var_name translator.inst}[] = {"
          io.indent do
            translator.inst.operands.each do |op|
              inst_operand_to_c(translator, op, io, eol: ',')
            end
          end
          io.puts '};'
          io.puts
        end

        io.string
      end

      def inst_mnems_to_c(io = StrIO.new)
        @inst_translators.each do |translator|
          io.puts %Q{static const char #{inst_mnem_var_name translator.inst}[] = "#{translator.inst.mnem}";}
        end

        io.string
      end

      def param_domain_to_c(io, domain)
        domain_c =
          case domain
          when /int(\d+)/
            type = $1 == '64' ? 'EVOASM_DOMAIN_TYPE_INT64' : 'EVOASM_DOMAIN_TYPE_INTERVAL'
            "{#{type}, #{expr_to_c :"INT#{$1}_MIN"}, #{expr_to_c :"INT#{$1}_MAX"}}"
          when Range
            min_c = expr_to_c domain.begin
            max_c = expr_to_c domain.end
            "{EVOASM_DOMAIN_TYPE_INTERVAL, #{min_c}, #{max_c}}"
          when Array
            if domain.size > ENUM_MAX_LENGTH
              fail 'enum exceeds maximal enum length of'
            end
            values_c = "#{domain.map { |expr| expr_to_c expr }.join ', '}"
            "{EVOASM_DOMAIN_TYPE_ENUM, #{domain.length}, {#{values_c}}}"
          else
            raise
          end

        domain_c_type =
          case domain
          when Range, Symbol
            'evoasm_interval_t'
          when Array
            "evoasm_enum#{domain.size}_t"
          else
            raise
          end
        io.puts "static const #{domain_c_type} #{param_domain_var_name domain} = #{domain_c};"
      end

      def param_domains_to_c(io = StrIO.new)
        registered_param_domains.each do |domain|
          param_domain_to_c io, domain
        end

        io.puts "const uint16_t evoasm_n_domains = #{registered_param_domains.size};"

        io.string
      end

      def request(hash, key, translator)
        id, translators = hash[key]
        if id.nil?
          id = hash.size
          translators = []

          hash[key] = [id, translators]
        end

        translators << translator
        id
      end

      def pref_funcs_to_c(io = StrIO.new)
        @pref_funcs.each do |writes, (id, translators)|
          func_translator = StateMachineCTranslator.new architecture, self
          func_translator.emit_pref_func io, writes, id

          translators.each do |translator|
            translator.merge_params func_translator.parameters
          end
        end

        io.string
      end

      def inst_flags_to_c(inst)
        if inst.flags.empty?
          '0'
        else
          inst.flags.map { |flag| inst_flag_to_c flag }
            .join ' | '
        end
      end

      def features_bitmap(inst)
        bitmap(features) do |flag, _|
          inst.features.include?(flag)
        end
      end

      def exceptions_bitmap(inst)
        bitmap(exceptions) do |flag, _|
          inst.exceptions.include?(flag)
        end
      end

      def bitmap(enum, &block)
        enum.symbols.each_with_index.inject(0) do |acc, (flag, index)|
          if block[flag, index]
            acc | (1 << index)
          else
            acc
          end
        end
      end
    end
  end
end
