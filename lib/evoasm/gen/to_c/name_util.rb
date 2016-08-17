module Evoasm
  module Gen
    module NameUtil
      def namespace
        'evoasm'
      end

      def const_name_to_c(name, prefix)
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
        ["#{arch}_ctx", name]
      end

      def arch_prefix(name = nil)
        ["#{arch}", name]
      end

      def error_code_to_c(name)
        prefix = name == :ok ? :error_code : base_arch_prefix(:error_code)
        const_name_to_c name, prefix
      end

      def register_name_to_c(name)
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

      def inst_param_name_to_c(name)
        const_name_to_c name, arch_prefix(:inst_param)
      end

      def inst_params_var_name(inst)
        "params_#{inst.name}"
      end

      def inst_mnem_var_name(inst)
        "name_#{inst.name}"
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
        when Symbol
          "param_domain_#{domain}"
        else
          raise "unexpected domain type #{domain.class} (#{domain.inspect})"
        end
      end

      def permutation_table_var_name(n)
        "permutations#{n}"
      end

      def inst_enc_func_name(inst)
        symbol_to_c inst.name, arch_prefix
      end

      def operand_c_type
        symbol_to_c :operand, arch_prefix, type: true
      end

      def inst_param_c_type
        symbol_to_c :inst_param, type: true
      end

      def acc_c_type
        symbol_to_c :bitmap128, type: true
      end

      def inst_enc_ctx_c_type
        symbol_to_c "#{unit.arch}_inst_enc_ctx", type: true
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
  end
end
