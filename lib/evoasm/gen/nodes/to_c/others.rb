require 'evoasm/gen/core_ext/string_io'

module Evoasm
  module Gen
    module Nodes

      def_to_c IntegerLiteral do |hex = true|
        if hex
          '0x' + value.to_s(16)
        else
          value.to_s
        end
      end

      def_to_c StringLiteral do
        %Q{"#{value}"}
      end

      class TrueLiteral
        def to_c
          'true'
        end

        def if_to_c(_io)
          yield
        end
      end

      class FalseLiteral
        def to_c
          'false'
        end

        def if_to_c(_io)
        end
      end

      class Expression
        def if_to_c(io, &block)
          condition_c = to_c.gsub(/^\(|\)$/, '')
          io.block "if(#{condition_c})", &block
        end
      end

      class Else
        def if_to_c(io, &block)
          io.block "else", &block
        end
      end

      class Operation
        def to_c
          return send :"#{name.to_s.gsub /\?$/, '_p'}_to_c" if helper?

          c_op, arity = c_operator
          args_c = args.map(&:to_c)

          if arity == 1
            "(#{c_op}#{args_c.first})"
          else
            "(#{args_c.join " #{c_op} "})"
          end
        end

        private

        def check_arity!(arity)
          if arity && arity != args.size
            raise "wrong number of operands for"\
                  " '#{name}' (#{args.inspect} for #{arity})"
          end
        end

        def c_operator
          c_op, arity =
            case name
            when :and
              '&&'
            when :or
              '||'
            when :eq
              ['==', 2]
            when :shl
              ['<<', 2]
            when :ltq
              ['<=', 2]
            when :div
              ['/', 2]
            when :add
              '+'
            when :not
              ['!', 1]
            when :neg
              ['~', 1]
            when :mod
              '%'
            else
              raise "unknown operator '#{name}' (#{self.class})"
            end

          check_arity! arity

          [c_op, arity]
        end

        def reg_code_to_c
          unit.c_function_call 'reg_code', args.map(&:to_c), unit.architecture_prefix
        end

        def auto_disp_size_to_c
          unit.c_function_call 'auto_disp_size', ['&ctx->params'], unit.architecture_prefix
        end

        def set_p_to_c
          parameter = args.first

          parameter.undefined_check_to_c
        end

        def log2_to_c
          "evoasm_log2(#{args.first.to_c})"
        end
      end

      class ParameterVariable
        def c_parameter_variable(undefined_check = false)
          aliasee = unit.parameter_ids.aliasee(name) || name
          aliasee = aliasee.to_s.gsub('?', '')

          field_name =
            if basic?
              'basic_params'
            else
              'params'
            end

          "ctx->#{field_name}.#{aliasee}#{undefined_check ? '_set' : ''}"
        end

        def undefined_check_to_c
          c_parameter_variable true
        end

        def to_c
          c_parameter_variable
        end
      end

      class Parameter
        def to_c(io)
          io.puts '{'
          io.indent do
            io.puts constant.to_c, eol: ','
            io.puts '(evoasm_domain_t *) &' + domain.c_variable_name
          end
          io.puts '}'
        end

        def c_type_name
          unit.symbol_to_c :param, type: true
        end

        def c_constant_name
          unit.parameter_ids.symbol_to_c name
        end
      end

      class Domain
        def to_c(io)
          io.puts "static const #{c_type_name} #{c_variable_name} = #{body_to_c};"
        end
      end

      class EnumerationDomain
        MAX_LENGTH = 32

        def after_initialize
          @@index ||= 0
          @index = @@index
          @@index += 1
        end

        def body_to_c
          raise 'enum exceeds maximal enum length' if values.size > MAX_LENGTH

          values_c = values.map(&:to_c).join ', '
          "{EVOASM_DOMAIN_TYPE_ENUM, #{values.length}, {#{values_c}}}"
        end

        def c_type_name
          "evoasm_enum#{values.size}_domain_t"
        end

        def c_variable_name
          "enum_domain__#{@index}"
        end
      end

      class RangeDomain
        def body_to_c
          "{EVOASM_DOMAIN_TYPE_RANGE, #{min}, #{max}}"
        end

        def c_type_name
          'evoasm_range_domain_t'
        end

        def c_variable_name
          "range_domain__#{min.to_s.tr('-', 'm')}_#{max.to_s.tr('-', 'm')}"
        end
      end

      class TypeDomain
        def body_to_c
          type =~ /int(\d+)/ || raise
          "{EVOASM_DOMAIN_TYPE_INT#$1}"
        end

        def c_type_name
          "evoasm_#{type}_domain_t"
        end

        def c_variable_name
          "type_domain__#{type}"
        end
      end

      class UnorderedWrites
        def c_function_name
          "unordered_write_#{object_id}"
        end

        def call_to_c(io, parameter)
          if writes.size == 1
            condition, write_action = writes.first
            condition.if_to_c(io) do
              write_action.to_c(io)
            end
          else
            order_c =
              if parameter
                parameter.to_c
              else
                '0'
              end

            io.puts "#{c_function_name}(ctx, #{order_c});"
          end
        end

        def to_c(io)
          # inline singleton writes
          return if writes.size == 1

          io.puts 'static void'
          io.write c_function_name
          io.write '('
          io.write "#{unit.c_context_type} *ctx,"
          io.write 'unsigned order'
          io.write ')'
          io.block do
            io.puts 'int i;'
            c_loop io
          end
        end

        private

        def c_loop(io)
          io.block "for(i = 0; i < #{writes.size}; i++)" do
            io.block "switch(#{permutation_table.c_variable_name}[order][i])" do
              writes.each_with_index do |write, index|
                condition, write_action = write
                io.block "case #{index}:" do
                  condition.if_to_c(io) do
                    write_action.to_c io
                  end
                  io.puts 'break;'
                end
              end
              io.puts 'default: evoasm_assert_not_reached();'
            end
          end
        end
      end

      def_to_c LocalVariable do
        name
      end

      def_to_c Constant do
        unit.constant_name_to_c name, [unit.architecture]
      end

      def_to_c RegisterConstant do
        unit.constant_name_to_c name, [unit.architecture, 'reg']
      end

      def_to_c ErrorCode do
        unit.constant_name_to_c name, 'error_code'
      end

      def_to_c SharedVariable do
        "ctx->shared_vars.#{name}"
      end

      class PermutationTable
        def c_variable_name
          "permutations#{width}"
        end

        def to_c(io)
          io.puts "static int #{c_variable_name}"\
                    "[#{height}][#{width}] = {"

          table.each do |permutation|
            io.puts "  {#{permutation.join ', '}},"
          end
          io.puts '};'
          io.puts
        end
      end
    end
  end
end
