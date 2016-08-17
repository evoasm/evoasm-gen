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
        def if_to_c(_unit, _io)
          io.puts "if(#{to_c}) {"
          yield
          io.puts '}'
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
          if writes.size > 1
            id, table_size = unit.find_or_create_prefix_function writes, self
            func_name = unit.pref_func_name(id)

            call_c = call_to_c(func_name,
                               [*params_args, inst_param_name_to_c(param_name)],
                               arch_ctx_prefix)

            io.puts call_c, eol: ';'

            register_param param_name
            @param_domains[param_name] = (0..table_size - 1)
          elsif !writes.empty?
            condition, write_action = writes.first
            condition.if_to_c(unit, io) do
              write_action.to_c(unit, io)
            end
          end
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
