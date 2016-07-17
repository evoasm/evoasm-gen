require 'erubis'
require 'evoasm/gen/strio'
require 'evoasm/gen/enum'
require 'evoasm/gen/translator_util'
require 'evoasm/gen/func_translator'
require 'evoasm/gen/x64'

module Evoasm
  module Gen
    class Translator
      include TranslatorUtil

      attr_reader :param_names
      attr_reader :bit_masks
      attr_reader :registered_param_domains
      attr_reader :reg_names
      attr_reader :exceptions
      attr_reader :reg_types
      attr_reader :operand_types
      attr_reader :arch
      attr_reader :features
      attr_reader :inst_flags
      attr_reader :insts
      attr_reader :options

      STATIC_PARAMS = %i(reg0 reg1 reg2 reg3 reg4 imm operand_size address_size)
      PARAM_ALIASES = {imm0: :imm}
      OUTPUT_FORMATS = %i(c h ruby_ffi)

      def initialize(arch, insts, options = {})
        @arch = arch
        @insts = insts
        @options = options
        @pref_funcs = {}
        @called_funcs = {}
        @registered_param_domains = Set.new

        @param_names = Enum.new :param_id, STATIC_PARAMS, prefix: arch

        send :"initialize_#{arch}"
      end

      def initialize_x64
        @features = Enum.new :feature, prefix: arch, flags: true
        @inst_flags = Enum.new :inst_flag, prefix: arch, flags: true
        @exceptions = Enum.new :exception, prefix: arch
        @reg_types = Enum.new :reg_type, Evoasm::Gen::X64::REGISTERS.keys, prefix: arch
        @operand_types = Enum.new :operand_type, Evoasm::Gen::X64::Inst::OPERAND_TYPES, prefix: arch
        @reg_names = Enum.new :reg_id, Evoasm::Gen::X64::REGISTER_NAMES, prefix: arch
        @bit_masks = Enum.new :bit_mask, %i(rest 64_127 32_63 0_31), prefix: arch, flags: true

        insts.each do |inst|
          @features.add_all inst.features
          @inst_flags.add_all inst.flags
          @exceptions.add_all inst.exceptions
        end
      end

      def self.target_filename(arch, output_type)
        case output_type
        when :c, :h
          "evoasm-#{arch}.#{output_type == :h ? 'h' : 'c'}"
        when :ruby_ffi
          "#{arch}_enums.rb"
        else
          raise "invalid output type #{output_type}"
        end
      end

      def self.template_path(arch, output_type)
        File.join Evoasm::Gen.data_dir, 'templates', "#{target_filename(arch, output_type)}.erb"
      end

      def main_translator
        self
      end

      def register_param(name)
        param_names.add name, PARAM_ALIASES[name]
      end

      def request_pref_func(writes, translator)
        _, table_size = request_permutation_table(writes.size)
        [request(@pref_funcs, writes, translator), table_size]
      end

      def request_func_call(func, translator)
        request @called_funcs, func, translator
      end

      def request_permutation_table(n)
        @permutation_tables ||= Hash.new { |h, k| h[k] = (0...k).to_a.permutation }
        [permutation_table_var_name(n), @permutation_tables[n].size]
      end

      def translate!(&block)
        send :"translate_#{arch}", &block
      end

      private
      def register_param_domain(domain)
        @registered_param_domains << domain
      end

      def translate_x64(&block)
        translate_x64_c(&block)

        # NOTE: must be done after
        # translating C file
        # as we are collecting information
        # in the translation process
        translate_x64_h(&block)

        translate_x64_ruby_ffi(&block)
      end

      def render_template(format, binding, &block)
        target_filename = self.class.target_filename(arch, format)
        template_path = self.class.template_path(arch, format)

        renderer = Erubis::Eruby.new(File.read(template_path))
        block[target_filename, renderer.result(binding), format]
      end

      def translate_x64_ruby_ffi(&block)
        render_template(:ruby_ffi, binding, &block)
      end

      def translate_x64_h(&block)
        render_template(:h, binding, &block)
      end

      def translate_x64_c(&block)
        # NOTE: keep in correct order
        inst_funcs = inst_funcs_to_c
        pref_funcs = pref_funcs_to_c
        permutation_tables = permutation_tables_to_c
        called_funcs = called_funcs_to_c
        insts_c = insts_to_c
        inst_operands = inst_operands_to_c
        inst_params = inst_params_to_c
        param_domains = param_domains_to_c

        render_template(:c, binding, &block)
      end

      def inst_funcs_to_c(io = StrIO.new)
        @inst_translators = insts.map do |inst|
          inst_translator = FuncTranslator.new arch, self
          inst_translator.emit_inst_func io, inst

          inst_translator
        end
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
        const_name_to_c name, arch_prefix(:bit_mask)
      end

      def permutation_tables_to_c(io = StrIO.new)
        Hash(@permutation_tables).each do |n, perms|
          io.puts "static int #{permutation_table_var_name n}"\
                    "[#{perms.size}][#{perms.first.size}] = {"

          perms.each do |perm|
            io.puts "  {#{perm.join ', '}},"
          end
          io.puts '};'
          io.puts
        end

        io.string
      end

      def called_funcs_to_c(io = StrIO.new)
        @called_funcs.each do |func, (id, translators)|
          func_translator = FuncTranslator.new arch, self
          func_translator.emit_called_func io, func, id

          translators.each do |translator|
            translator.merge_params func_translator.registered_params
          end
        end

        io.string
      end

      def inst_to_c(io, inst, params)
        io.puts '{'
        io.indent do
          io.puts inst_name_to_c(inst), eol: ','
          io.puts params.size, eol: ','
          if params.empty?
            io.puts 'NULL,'
          else
            io.puts "(#{param_c_type} *)" + inst_params_var_name(inst), eol: ','
          end
          io.puts '(evoasm_x64_inst_enc_func_t)' + inst_enc_func_name(inst), eol: ','

          io.puts "#{features_bitmap(inst)}ull", eol: ','
          if inst.operands.empty?
            io.puts 'NULL,'
          else
            io.puts "(#{operand_c_type} *)#{inst_operands_var_name inst}", eol: ','
          end
          io.puts inst.operands.size, eol: ','
          io.puts exceptions_bitmap(inst), eol: ','
          io.puts inst_flags_to_c(inst)
        end
        io.puts '},'
      end

      def insts_to_c(io = StrIO.new)
        io.puts "static const evoasm_x64_inst_t #{static_insts_var_name}[] = {"
        @inst_translators.each do |translator|
          inst_to_c io, translator.inst, translator.registered_params
        end
        io.puts '};'
        io.puts "const evoasm_x64_inst_t *#{insts_var_name} = #{static_insts_var_name};"

        io.string
      end

      def inst_param_to_c(io, inst, params, param_domains)
        return if params.empty?
        io.puts "static const #{param_c_type} #{inst_params_var_name inst}[] = {"
        io.indent do
          params.each do |param|
            next if local_param? param

            param_domain = param_domains[param] || inst.param_domain(param)
            register_param_domain param_domain

            io.puts '{'
            io.indent do
              io.puts param_name_to_c(param), eol: ','
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
          inst_param_to_c io, translator.inst, translator.registered_params, translator.param_domains
        end

        io.string
      end

      def inst_operand_to_c(translator, op, io = StrIO.new, eol:)
        io.puts '{'
        io.indent do
          io.puts op.access.include?(:r) ? '1' : '0', eol: ','
          io.puts op.access.include?(:w) ? '1' : '0', eol: ','
          io.puts op.access.include?(:u) ? '1' : '0', eol: ','
          io.puts op.access.include?(:c) ? '1' : '0', eol: ','
          io.puts op.implicit? ? '1' : '0', eol: ','

          params = translator.registered_params.reject { |p| local_param? p }
          if op.param
            param_idx = params.index(op.param) or \
              raise "param #{op.param} not found in #{translator.params.inspect}" \
                      " (#{translator.inst.mnem}/#{translator.inst.index})"

            io.puts param_idx, eol: ','
          else
            io.puts params.size, eol: ','
          end

          io.puts operand_type_to_c(op.type), eol: ','

          if op.size
            io.puts operand_size_to_c(op.size), eol: ','
          else
            io.puts 'EVOASM_N_OPERAND_SIZES', eol: ','
          end

          if op.reg
            io.puts reg_name_to_c(op.reg), eol: ','
          else
            io.puts reg_names.n_elem_const_name_to_c, eol: ','
          end

          if op.reg_type
            io.puts reg_type_to_c(op.reg_type), eol: ','
          else
            io.puts reg_types.n_elem_const_name_to_c, eol: ','
          end

          if op.accessed_bits.key? :w
            io.puts bit_mask_to_c(op.accessed_bits[:w])
          else
            io.puts bit_masks.all_to_c
          end
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

      ENUM_MAX_LENGTH = 32

      def param_domain_to_c(io, domain)
        domain_c =
          case domain
          when (:INT64_MIN..:INT64_MAX)
            "{EVOASM_DOMAIN_TYPE_INTERVAL64, #{0}, #{0}}"
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
          when Range
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
          func_translator = FuncTranslator.new arch, self
          func_translator.emit_pref_func io, writes, id

          translators.each do |translator|
            translator.merge_params func_translator.registered_params
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
        enum.keys.each_with_index.inject(0) do |acc, (flag, index)|
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
