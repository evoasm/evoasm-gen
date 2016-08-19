module Evoasm
  module Gen
    module Nodes
      module ToC
        def_to_c WriteAction do |io|
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

        def_to_c SetAction do |io|
          io.puts "#{variable.to_c unit} = #{value.to_c unit};"
        end

        def_to_c ErrorAction do |io|
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

        def_to_c LogActionToC do |io|
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

        class AccessAction
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

        def_to_c UnorderedWritesAction do |io|
          unordered_writes.call_to_c unit, io, param
        end

        def_to_c CallAction do |io|
          call_c = state_machine.call_to_c unit
          io.puts "if(!#{call_c}){goto error;}"
        end

      end
    end
  end
end
