require 'evoasm/gen/name_util'

module Evoasm
  module Gen
    module TranslatorUtil
      include NameUtil

      PARAMS_ARG_HELPERS = %i(address_size operand_size disp_size)
      NO_ARCH_HELPERS = %i(log2)

      def call_to_c(func, args, prefix = nil, eol: false)
        func_name = func.to_s.gsub('?', '_p')

        if prefix
          args.unshift arch_var_name(Array(prefix).first != arch)
        end

        "#{name_to_c func_name, prefix}(#{args.join ','})" + (eol ? ';' : '')
      end

      def params_c_args
        "#{inst_param_val_c_type} *param_vals, "\
          "#{bitmap_c_type} *set_params"
      end

      def params_args
        %w(param_vals set_params)
      end

      def param_to_c(name)
        register_param name.to_sym
        inst_param_name_to_c name
      end

      def register_param(name)
        return if State.local_variable_name? name
        main_translator.register_param name
        registered_params << name
      end

      def helper_to_c(expr)
        if expr.first.is_a?(Array)
          fail expr.inspect unless expr.size == 1
          expr = expr.first
        end

        name, *args = simplify_helper expr
        case name
        when :eq, :gt, :lt, :gtq, :ltq
          "(#{expr_to_c args[0]} #{cmp_helper_to_c name} #{expr_to_c args[1]})"
        when :if
          "(#{expr_to_c args[0]} ? (#{expr_to_c args[1]}) : #{expr_to_c args[2]})"
        when :neg
          "~(#{expr_to_c args[0]})"
        when :shl
          infix_op_to_c '<<', args
        when :mod
          infix_op_to_c '%', args
        when :div
          infix_op_to_c '/', args
        when :add
          infix_op_to_c '+', args
        when :sub
          infix_op_to_c '-', args
        when :set?
          set_p_to_c(*args)
        when :not
          "!(#{expr_to_c args[0]})"
        when :max, :min
          "#{name.to_s.upcase}(#{args.map { |a| expr_to_c a }.join(', ')})"
        when :and
          infix_op_to_c '&&', args
        when :or
          infix_op_to_c '||', args
        when :in?
          args[1..-1].map { |a| "#{expr_to_c args[0]} == #{expr_to_c a}" }
            .join(" ||\n#{io.indent_str + '   '}")
        else
          if !name.is_a?(Symbol)
            fail unless args.empty?
            expr_to_c name
          else
            call_args = args.map { |a| expr_to_c(a) }
            call_args.concat params_args if PARAMS_ARG_HELPERS.include? name
            if name == :reg_code
              call_args[0] = "(evoasm_#{arch}_reg_id_t) #{call_args[0]}"
            end
            helper_call_to_c name, call_args
          end
        end
      end

      def expr_to_c(expr, const_prefix: nil)
        case expr
        when Array
          helper_to_c expr
        when TrueClass
          'true'
        when FalseClass
          'false'
        when Numeric
          expr
        when Symbol, String
          s = expr.to_s
          if s != s.upcase
            get_to_c s
          else
            if X64::REGISTER_NAMES.include?(s.to_sym)
              const_prefix = [arch, 'reg']
            elsif s =~ /^INT\d+_(MAX|MIN)$/
              const_prefix = nil
            end

            name_to_c s, const_prefix, const: true
          end
        else
          fail "invalid expression #{expr.inspect}"
        end
      end

      def func_prototype_to_c(name, func_params = [], static: true)
        func_name = name_to_c name, arch

        func_params_c =
          if func_params.empty?
            ''
          else
            func_params.map do |param_name, type|
              "#{type} #{param_name}"
            end.join(', ').prepend ', '
          end
        "#{static ? 'static ' : ''}evoasm_success_t\n#{func_name}(#{arch_c_type} *#{arch_var_name},"\
        " #{params_c_args}#{func_params_c})"
      end
    end
  end
end