module Evoasm
  module Gen
    module NameUtil
      def namespace
        'evoasm'
      end

      def const_name_to_c(name, prefix)
        name_to_c name, prefix, const: true
      end

      def const_name_to_ruby_ffi(name, prefix)
        name_to_ruby_ffi name, prefix, const: true
      end

      def name_to_ruby_ffi(name, prefix = nil, const: false, type: false)
        ruby_ffi_name = name.to_s.downcase
        ruby_ffi_name =
          if ruby_ffi_name =~ /^\d+$/
            if prefix && prefix.last =~ /reg/
              'r' + ruby_ffi_name
            else
              raise
            end
          else
            ruby_ffi_name
          end

        ruby_ffi_name
      end

      def name_to_c(name, prefix = nil, const: false, type: false)
        c_name = [namespace, *prefix, name.to_s.sub(/\?$/, '')].compact.join '_'
        if const
          c_name.upcase
        elsif type
          c_name + '_t'
        else
          c_name
        end
      end

      def indep_arch_prefix(name = nil)
        ['arch', name]
      end

      def arch_prefix(name = nil)
        [arch, name]
      end

      def error_code_to_c(name)
        prefix = name == :ok ? :error_code : indep_arch_prefix(:error_code)
        const_name_to_c name, prefix
      end

      def reg_name_to_c(name)
        const_name_to_c name, arch_prefix(:reg)
      end

      def exception_to_c(name)
        const_name_to_c name, arch_prefix(:exception)
      end

      def reg_type_to_c(name)
        const_name_to_c name, arch_prefix(:reg_type)
      end

      def operand_type_to_c(name)
        const_name_to_c name, arch_prefix(:operand_type)
      end

      def inst_name_to_c(inst)
        const_name_to_c inst.name, arch_prefix(:inst)
      end

      def inst_name_to_ruby_ffi(inst)
        const_name_to_ruby_ffi inst.name, arch_prefix(:inst)
      end

      def operand_size_to_c(size)
        const_name_to_c size, arch_prefix(:operand_size)
      end

      def feature_name_to_c(name)
        const_name_to_c name, arch_prefix(:feature)
      end

      def inst_flag_to_c(flag)
        const_name_to_c flag, arch_prefix(:inst_flag)
      end

      def param_name_to_c(name)
        const_name_to_c name, arch_prefix(:param)
      end

      def inst_params_var_name(inst)
        "params_#{inst.name}"
      end

      def insts_var_name
        "_evoasm_#{arch}_insts"
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
        else
          fail "unexpected domain type #{domain.class} (#{domain.inspect})"
        end
      end

      def permutation_table_var_name(n)
        "permutations#{n}"
      end

      def inst_enc_func_name(inst)
        name_to_c inst.name, arch_prefix
      end

      def operand_c_type
        name_to_c :operand, arch_prefix, type: true
      end

      def param_c_type
        name_to_c :arch_param, type: true
      end

      def acc_c_type
        name_to_c :bitmap128, type: true
      end

      def arch_c_type
        name_to_c arch, type: true
      end

      def param_val_c_type
        name_to_c 'arch_param_val', type: true
      end

      def bitmap_c_type
        name_to_c 'bitmap', type: true
      end

      def inst_id_c_type
        name_to_c :inst_id, type: true
      end

      def pref_func_name(id)
        "prefs_#{id}"
      end

      def called_func_name(func, id)
        attrs = func.each_pair.map { |k, v| [k, v].join('_') }.flatten.join('__')
        "#{func.class.name.split('::').last.downcase}_#{attrs}_#{id}"
      end

      def arch_var_name(indep_arch = false)
        "#{indep_arch ? '((evoasm_arch_t *)' : ''}#{arch}#{indep_arch ? ')' : ''}"
      end
    end
  end
end
