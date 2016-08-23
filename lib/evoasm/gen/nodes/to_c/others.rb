require 'evoasm/gen/strio'

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
          condition_c = to_c.sub(/^\(|\)$/, '')
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

        def reg_code_to_c
          unit.c_function_call 'reg_code', args.map(&:to_c), unit.architecture_prefix
        end

        def disp_size_to_c
          unit.c_function_call 'disp_size', ['ctx->params.disp'], unit.architecture_prefix
        end

        def set_p_to_c
          parameter = args.first

          raise unless parameter.is_a?(ParameterVariable)
          "ctx->params.#{parameter.name}_set"
        end

        def log2_to_c
          "evoasm_log2(#{args.first})"
        end
      end

      def_to_c ParameterVariable do
        "ctx->params.#{name.to_s.gsub '?', ''}"
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
          unit.symbol_to_c :inst_param, type: true
        end

        def c_constant_name
          unit.parameter_names.symbol_to_c name
        end
      end

      class Domain

        ENUM_MAX_LENGTH = 32

        def to_c(io)
          domain_c =
            case values
            when /int(\d+)/
              type = $1 == '64' ? 'EVOASM_DOMAIN_TYPE_INT64' : 'EVOASM_DOMAIN_TYPE_INTERVAL'
              "{#{type}, INT#{$1}_MIN, INT#{$1}_MAX}"
            when Range
              "{EVOASM_DOMAIN_TYPE_INTERVAL, #{values.begin}, #{values.end}}"
            when Array
              if values.size > ENUM_MAX_LENGTH
                raise 'enum exceeds maximal enum length'
              end
              values_c = values.map(&:to_c).join ', '
              "{EVOASM_DOMAIN_TYPE_ENUM, #{values.length}, {#{values_c}}}"
            else
              raise
            end
          io.puts "static const #{c_type} #{c_variable_name} = #{domain_c};"
        end

        def c_type
          case values
          when Range, ::Symbol
            'evoasm_interval_t'
          when Array
            "evoasm_enum#{values.size}_t"
          else
            raise
          end
        end

        def c_variable_name
          case values
          when Range
            "param_values__#{values.begin.to_s.tr('-', 'm')}_#{values.end}"
          when Array
            "param_values_enum__#{values.join '_'}"
          when ::Symbol
            "param_values_#{values}"
          else
            raise "unexpected values type #{values.class} (#{values.inspect})"
          end
        end
      end

      class UnorderedWrites
        def c_function_name
          "unordered_write_#{object_id}"
        end

        def call_to_c(io, param)
          if writes.size == 1
            condition, write_action = writes.first
            condition.if_to_c(io) do
              write_action.to_c(io)
            end
          else
            "if(!#{c_function_name}(ctx, ctx->params.#{param.name})){goto error;}"
          end
        end

        def to_c(io)
          # inline singleton writes
          return if writes.size == 1

          io.puts 'static void'
          io.write c_function_name
          io.write '('
          io.write "#{StateMachineCTranslator.c_context_type unit} *ctx,"
          io.write "unsigned order"
          io.write ')'
          io.block do
            io.puts 'int i;'
            io.block "for(i = 0; i < #{writes.size}; i++)" do
              io.block "switch(#{permutation_table.c_variable_name}[order][i])" do
                writes.each_with_index do |write, index|
                  condition, write_action = write
                  io.block "case #{index}:" do
                    condition.if_to_c(unit, io) do
                      write_action.to_c unit, io
                    end
                    io.puts 'break;'
                  end
                end
                io.puts 'default: evoasm_assert_not_reached();'
              end
            end
          end
        end
      end

      def_to_c LocalVariable do
        name
      end

      def_to_c Constant do
        unit.constant_to_c name, [unit.architecture]
      end

      def_to_c SharedVariable do
        "ctx->shared.#{name}"
      end

      def_to_c RegisterConstant do
        unit.symbol_to_c name, [unit.architecture], const: true
      end

      def_to_c ErrorCode do
        unit.symbol_to_c name, const: true
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
