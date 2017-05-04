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
          size_c = sizes.first.value.to_s
        end
        io.puts "evoasm_buf_ref_write#{size_c}(&ctx->buf_ref, (int#{size_c}_t) #{value_c});"
      end

      def_to_c SetAction do |io|
        io.puts "#{variable.to_c} = #{value.to_c};"
      end

      def error_data_field_to_c(field_name)
        "ctx->error_data.#{field_name}"
      end

      def translate_comment(state)
        io.puts "/* #{state.comment} (#{state.object_id}) */" if state.comment
      end

      def_to_c ErrorAction do |io|
        register_c =
          if register
            register.to_c
          else
            '(uint8_t) -1'
          end

        parameter_c =
          if parameter
            unit.parameter_ids.symbol_to_c parameter.name
          else
            '(uint8_t) -1'
          end

        io.puts 'evoasm_enc_error_data_t error_data = {'
        io.puts "  .reg = #{register_c},"
        io.puts "  .param = #{parameter_c},"
        io.puts '};'

        io.puts %Q{evoasm_error2(EVOASM_ERROR_TYPE_ARCH, #{code.to_c}, &error_data, #{message.to_c});}
        io.puts 'retval = false;'
      end

      def_to_c LogAction do |io|
        args_c =
          if args.empty?
            ''
          else
            args_c = args.map do |arg|
              "(int64_t) #{arg.to_c}"
            end.join(', ').prepend(', ')
          end

        msg_c = msg.gsub('%', '%" PRId64 "')
        io.puts %[evoasm_log_#{level}("#{msg_c}" #{args_c});]
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
