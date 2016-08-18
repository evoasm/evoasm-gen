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

      module ParameterToC
        def to_c(unit)
          "EVOASM_#{unit.arch}_PARAM_#{name.upcase}"
        end
      end

      module WriteActionToC
        def to_c(unit, io)
          if size.is_a?(Array) && value.is_a?(Array)
            value_c, size_c = value.reverse.zip(size.reverse).inject(['0', 0]) do |(v_acc, s_acc), (v, s)|
              [v_acc + " | ((#{v.to_c} & ((1 << #{s}) - 1)) << #{s_acc})", s_acc + s]
            end
          else
            value_c = value.to_c(unit)
            size_c = size.to_c(unit)
          end
          io.puts "evoasm_inst_enc_ctx_write#{size_c}(ctx, #{value_c});"
        end
      end

      module SetActionToC
        def to_c(unit, io)
          io.puts "#{variable.to_c unit} = #{value.to_c unit};"
        end
      end

      module LocalVariableToC
        def to_c(_unit)
          name
        end
      end

      module SharedVariableToC
        def to_c(_unit)
          "ctx->shared.#{name}"
        end
      end

      module ErrorActionToC
        def to_c(unit, io)
          reg_c_val =
            if reg
              reg.to_c unit
            else
              '(uint8_t) -1'
            end
          param_c_val =
            if param
              param.to_c unit
            else
              '(uint8_t) -1'
            end

          io.puts 'evoasm_arch_error_data_t error_data = {'
          io.puts "  .reg = #{reg_c_val},"
          io.puts "  .param = #{param_c_val},"
          #io.puts "  .arch = #{state_machine_ctx_var_name arch_indep: true}"
          io.puts '};'

          io.puts %Q{evoasm_set_error(EVOASM_ERROR_TYPE_ARCH, #{code.to_c unit}, &error_data, #{msg.to_c unit});}
          #io.puts call_to_c 'arch_ctx_reset', [state_machine_ctx_var_name(true)], eol: ';'
          io.puts 'retval = false;'
        end
      end

      module LogActionToC
        def to_c(_unit, io)
          args_c =
            if args.empty?
              ''
            else
              args_c = args.map do |expr|
                "(#{inst_param_val_c_type}) #{expr_to_c expr}"
              end.join(', ').prepend(', ')
            end

          msg_c = msg.gsub('%', '%" EVOASM_INST_PARAM_VAL_FORMAT "')
          io.puts %[evoasm_#{level}("#{msg_c}" #{args_c});]
        end
      end

      module AccessActionToC

        def access_call_to_c(name, op, acc = 'acc', params = [], eol: false)
          unit.call_to_c("#{name}_access",
                         [
                           "(#{bitmap_c_type} *) &#{acc}",
                           "(#{regs.c_type}) #{expr_to_c(op)}",
                           *params
                         ],
                         base_arch_ctx_prefix,
                         eol: eol)
        end

        def translate_write_access(unit, io)
          io.puts access_call_to_c('write', :w, eol: true)
        end

        def undefined_access_to_c(unit, io)
          io.puts access_call_to_c('undefined', :u, eol: true)
        end

        def to_c(unit, io)
          #modes.each do |mode|
          #  case mode
          #  when :r
          #    translate_read_access unit, io
          #  when :w
          #    translate_write_access unit, io
          #  when :u
          #    translate_undefined_access unit, io
          #  else
          #    fail "unexpected access mode '#{mode.inspect}'"
          #  end
          #end
        end
      end

      module UnorderedWritesActionToC
        def to_c(unit, io)
          unordered_writes.call_to_c unit, io, param
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

      module CallActionToC
        def to_c(unit, io)
          call_c = state_machine.call_to_c unit
          io.puts "if(!#{call_c}){goto error;}"
        end
      end
    end
  end
end
