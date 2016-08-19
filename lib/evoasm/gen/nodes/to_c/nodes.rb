require 'evoasm/gen/strio'
require 'evoasm/gen/to_c/name_util'

module Evoasm
  module Gen
    module ToC
      module IntegerLiteralToC
        def to_c(_unit)
          '0x' + value.to_s(16)
        end
      end

      module StringLiteralToC
        def to_c(_unit)
          %Q{"#{value}"}
        end
      end

      module TrueLiteralToC
        def to_c(_unit)
          'true'
        end

        def if_to_c(_unit, _io)
          yield
        end
      end

      module FalseLiteralToC
        def to_c(_unit)
          'false'
        end

        def if_to_c(_unit, _io)
        end
      end

      module ExpressionToC
        def if_to_c(unit, io, &block)
          io.block "if(#{to_c unit})", &block
        end
      end

      module ElseToC
        def if_to_c(_unit, io, &block)
          io.block "else", &block
        end
      end

      module OperationToC
        def c_operation
        end

        def to_c(_unit)
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
            when :add
              '+'
            when :not
              ['!', 1]
            when :mod
              '%'
            else
              raise "unknown operator '#{name}'"
            end

          check_arity! arity

          if arity == 1
            "(#{c_op}#{args})"
          else
            "(#{args.join " #{c_op} "})"
          end
        end

        private

        def check_arity!(arity)
          if arity && arity != args.size
            raise "wrong number of operands for"\
                  " '#{name}' (#{args.inspect} for #{arity})"
          end
        end
      end

      module ParameterConstantToC
        def to_c(unit)
          "EVOASM_#{unit.arch}_PARAM_#{name.upcase}"
        end
      end

      module ParameterToC
        def to_c(unit, io)
          unit.register_domain domain

          io.puts '{'
          io.indent do
            io.puts constant.to_c, eol: ','
            io.puts '(evoasm_domain_t *) &' + domain.c_variable_name
          end
          io.puts '}'
        end
      end


      module UnorderedWritesToC
        def c_function_name(_unit)
          "unordered_write_#{object_id}"
        end

        def call_to_c(unit, io, param)
          if writes.size == 1
            condition, write_action = writes.first
            condition.if_to_c(unit, io) do
              write_action.to_c(unit, io)
            end
          else
            "if(!#{c_function_name unit}(ctx, ctx->params.#{param.name})){goto error;}"
          end
        end

        def to_c(unit, io)
          # inline singleton writes
          return if writes.size == 1

          io.puts 'static void'
          io.write c_function_name
          io.write '('
          io.write "#{StateMachineToC.c_context_type unit} *ctx,"
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

      def_to_c SharedVariable do
        "ctx->shared.#{name}"
      end

      module RegisterToC
        def to_c(unit)
          unit.symbol_to_c name, [unit.arch], const: true
        end
      end

      module ErrorCodeToC
        def to_c(unit)
          unit.symbol_to_c name, const: true
        end
      end

      module PermutationTableToC
        def to_c(unit, io)
          io.puts "static int #{permutation_table_var_name n}"\
                    "[#{perms.size}][#{perms.first.size}] = {"

          perms.each do |perm|
            io.puts "  {#{perm.join ', '}},"
          end
          io.puts '};'
          io.puts
        end
      end
    end
  end
end
