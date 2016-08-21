module Evoasm
  module Gen
    module Nodes
      def_to_c WriteAction do |io|
        if sizes.size > 1
          value_c, size_c = values.zip(sizes).reverse.inject(['0', 0]) do |(v_acc, s_acc), (v, s)|
            [v_acc + " | ((#{v.to_c} & ((1 << #{s.to_c}) - 1)) << #{s_acc})", s_acc + s.value]
          end
        else
          value_c = values.first.to_c
          size_c = sizes.first.to_c false
        end
        io.puts "evoasm_inst_enc_ctx_write#{size_c}(ctx, #{value_c});"
      end

      def_to_c SetAction do |io|
        io.puts "#{variable.to_c} = #{value.to_c};"
      end

      def error_data_field_to_c(field_name)
        "#{state_machine_ctx_var_name arch_indep: true}->error_data.#{field_name}"
      end

      def translate_comment(state)
        io.puts "/* #{state.comment} (#{state.object_id}) */" if state.comment
      end

      def_to_c ErrorAction do |io|
        reg_c_val =
          if reg
            reg.to_c
          else
            '(uint8_t) -1'
          end
        param_c_val =
          if param
            param.to_c
          else
            '(uint8_t) -1'
          end

        io.puts 'evoasm_arch_error_data_t error_data = {'
        io.puts "  .reg = #{reg_c_val},"
        io.puts "  .param = #{param_c_val},"
        #io.puts "  .arch = #{state_machine_ctx_var_name arch_indep: true}"
        io.puts '};'

        io.puts %Q{evoasm_set_error(EVOASM_ERROR_TYPE_ARCH, #{code.to_c}, &error_data, #{msg.to_c});}
        #io.puts call_to_c 'arch_ctx_reset', [state_machine_ctx_var_name(true)], eol: ';'
        io.puts 'retval = false;'
      end

      def_to_c LogAction do |io|
        args_c =
          if args.empty?
            ''
          else
            args_c = args.map do |arg|
              "(#{unit.inst_param_val_c_type}) #{arg.to_c}"
            end.join(', ').prepend(', ')
          end

        msg_c = msg.gsub('%', '%" EVOASM_INST_PARAM_VAL_FORMAT "')
        io.puts %[evoasm_#{level}("#{msg_c}" #{args_c});]
      end

      class AccessAction
        def access_call_to_c(name, op, acc = 'acc', params = [], eol: false)
          unit.c_function_call("#{name}_access",
                               [
                           "(#{bitmap_c_type} *) &#{acc}",
                           "(#{regs.c_type_name}) #{expr_to_c(op)}",
                           *params
                         ],
                               base_arch_ctx_prefix,
                               eol: eol)
        end

        def translate_write_access(io)
          io.puts access_call_to_c('write', :w, eol: true)
        end

        def undefined_access_to_c(io)
          io.puts access_call_to_c('undefined', :u, eol: true)
        end

        def to_c(io)
          #modes.each do |mode|
          #  case mode
          #  when :r
          #    translate_read_access io
          #  when :w
          #    translate_write_access io
          #  when :u
          #    translate_undefined_access io
          #  else
          #    fail "unexpected access mode '#{mode.inspect}'"
          #  end
          #end
        end
      end

      def_to_c UnorderedWritesAction do |io|
        unordered_writes.call_to_c io, parameter
      end

      def_to_c CallAction do |io|
        io.puts state_machine.call_to_c
      end
    end
  end
end
