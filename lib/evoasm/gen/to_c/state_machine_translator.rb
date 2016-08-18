require 'evoasm/gen/to_c/translator_util'

module Evoasm
  module Gen
    class StateMachineTranslator
      include TranslatorUtil

      INST_STATE_ID_MIN = 32
      INST_STATE_ID_MAX = 2000

      def initialize(unit, state_machine)
        @unit = unit
        @id ||= INST_STATE_ID_MAX
        @id_map ||= Hash.new { |h, k| h[k] = (@id += 1) }
        @state_machine = state_machine
        @io = StrIO.new
      end

      def string
        io.string
      end

      def translate!(translate_acc = false)
        write_function_prolog translate_acc
        translate_state state_machine.root_state
        write_function_epilog translate_acc
      end

      private

      attr_reader :io
      attr_reader :unit, :id_map
      attr_reader :state_machine

      def translate_acc_ary_copy(back_copy = false)
        var_name = 'acc'
        src = "#{state_machine_ctx_var_name}->#{var_name}"
        dst = var_name

        dst, src = src, dst if back_copy
        io.puts "#{dst} = #{src};"
      end

      def write_function_prolog(translate_acc)
        local_variables = state_machine.root_state.transitive_local_variables
        unless local_variables.empty?
          io.puts "#{inst_param_val_c_type} #{local_variables.join ', '};"
          local_variables.each do |param|
            io.puts "(void) #{param};"
          end
        end

        io.puts 'bool retval = true;'

        if translate_acc
          io.puts "#{acc_c_type} acc;"
          translate_acc_ary_copy
        end
      end

      def error_data_field_to_c(field_name)
        "#{state_machine_ctx_var_name arch_indep: true}->error_data.#{field_name}"
      end

      def translate_error(_state, code, msg, reg = nil, param = nil)
      end

      def write_function_epilog(acc)
        io.indent 0 do
          io.puts "exit:"
        end
        translate_acc_ary_copy true if acc
        io.puts "return retval;"

        io.indent 0 do
          io.puts "error:"
        end

        io.puts 'retval = false;'
        io.puts 'goto exit;'
      end

      def translate_state(state)
        fail if state.nil?

        untranslated_states = []

        fail if state.returns? && !state.terminal?

        translate_body state, untranslated_states

        untranslated_states.each do |untranslated_state|
          translate_state untranslated_state
        end
      end

      def translate_body(state, untranslated_states, inlined = false)
        raise state.actions.inspect unless deterministic?(state)
        io.puts '/* begin inlined */' if inlined

        translate_label state unless inlined

        actions = state.actions.dup.reverse
        translate_actions state, actions, untranslated_states

        translate_ret state if state.returns?

        translate_transitions(state, untranslated_states)

        io.puts '/* end inlined */' if inlined
      end

      def translate_comment(state)
        io.puts "/* #{state.comment} (#{state.object_id}) */" if state.comment
      end

      def translate_label(state)
        io.indent 0 do
          io.puts "#{state_label state}:;"
        end
      end

      def has_else?(state)
        state.children.any? { |_, condition| condition.is_a?(Else)}
      end

      def translate_ret(_state)
        io.puts 'goto exit;'
      end

      def state_label(state, id = nil)
        "L#{id || id_map[state]}"
      end

      def translate_call(_state, state_machine)
        unit.translate_call
        function = unit.find_state_machine_function state_machine

        func_call = function.call_to_c called_func_name(state_machine, id),
                              [*params_args, inst_name_to_c(inst), '&acc'],
                              arch_prefix

        io.puts "if(!#{func_call}){goto error;}"
      end

      def translate_goto_transition(child)
        io.puts "goto #{state_label child};"
      end

      def translate_transition(state, untranslated_states, condition, &block)
        condition.if_to_c unit, io do
          if inlineable?(state)
            block[] if block
            translate_body(state, untranslated_states, true)
            true
          else
            untranslated_states << state unless id_map.key?(state)
            block[] if block
            translate_goto_transition(state)
            false
          end
        end
      end

      def translate_transitions(state, untranslated_states, &block)
        state.children
             .sort_by { |_, _, attrs| attrs[:priority] }
             .each do |child, condition|
               translate_transition child, untranslated_states, condition, &block
             end

        raise 'missing else branch' if can_get_stuck?(state)
      end

      def can_get_stuck?(state)
        return false if state.returns?
        return false if has_else? state

        raise state.actions.inspect if state.children.empty?

        return false if state.children.any? do |_child, condition|
          condition.is_a?(TrueLiteral)
        end

        true
      end

      def helper_call_to_c(name, args)
        prefix =
          if UTIL_HELPERS.include? name
            nil
          elsif NO_ARCH_CTX_ARG_HELPERS.include? name
            arch_prefix
          else
            arch_ctx_prefix
          end

        call_to_c name, args, prefix
      end


      def translate_condition(condition, else_if: false, &block)
        cond_str =
          if condition.nil? || condition == true
            ''
          elsif condition[0] == :else
            'else '
          else
            "#{else_if ? 'else ' : ''}if(#{expr_to_c condition})"
          end

        io.block cond_str, &block
      end

      def translate_log(_state, level, msg, *exprs)
      end

      def translate_assert(_state, *expr)
        io.puts "assert(#{expr_to_c expr});"
      end

      def set_p_to_c(key, eol: false)
        call_to_c 'bitmap_get',
                  ["(#{bitmap_c_type} *) set_params", param_to_c(key)],
                  eol: eol
      end

      def shared_variable_to_c(name)
        "#{state_machine_ctx_var_name(false)}->shared_vars.#{name.to_s[1..-1]}"
      end

      def get_to_c(name, eol: false)
        if State.local_variable_name? name
          name.to_s
        elsif State.shared_variable_name? name
          shared_variable_to_c(name)
        else
          "param_vals[#{param_to_c(name)}]" + (eol ? ';' : '')
        end
      end

      def translate_set(_state, name, value)
        unless State.local_variable_name?(name) || State.shared_variable_name?(name)
          raise "setting non-local param '#{name}' is not allowed"
        end

        c_value = expr_to_c value

        if State.local_variable_name? name
          io.puts "#{name} = #{c_value};"
        elsif State.shared_variable_name? name
          io.puts "#{shared_variable_to_c name} = #{c_value};"
        else
          raise
        end
      end

      def merge_params(params)
        params.each do |param|
          register_param param
        end
      end

      def cmp_helper_to_c(name)
        case name
        when :eq then
          '=='
        when :gt then
          '>'
        when :lt then
          '<'
        when :gtq then
          '>='
        when :ltq then
          '<='
        else
          fail
        end
      end

      def infix_op_to_c(op, args)
        "(#{args.map { |a| expr_to_c a }.join(" #{op} ")})"
      end

      def translate_actions(state, actions, _untranslated_states)
        io.puts '/* actions */'
        until actions.empty?
          action = actions.pop
          action.to_c unit, io
        end
      end

      def deterministic?(state)
        n_children = state.children.size

        n_children <= 1 ||
          (n_children == 2 && has_else?(state))
      end

      def inlineable?(state)
        state.parents.size == 1 &&
          deterministic?(state.parents.first)
      end

      def translate_c_block(code = nil, &block)
        io.puts "#{code}{"
        io.indent do
          block[]
        end
        io.puts '}'
      end

      def translate_unordered_writes(state, param_name, writes)
      end

      def translate_read_access(_state, op)
        call = access_call_to_c 'read', op, "#{state_machine_ctx_var_name(true)}->acc",
                                [inst && inst_name_to_c(inst) || 'inst']

        #translate_c_block "if(!#{call})" do
        #  translate_exit error: true
        #end
        io.puts call, eol: ';'
      end


      def write_to_c(value, size)
      end

      def translate_write(_state, value, size)
        io.puts write_to_c(value, size)
        
      end


      def translate_called_func(io, func, id)
        with_io io do
          translate_func(called_func_name(func, id),
                    func.root_state,
                    {'inst' => inst_id_c_type, 'acc' => "#{acc_c_type} *"},
                    local_acc: false)
        end
      end

      def translate_pref_func(io, writes, id)
        with_io io do
          table_var_name, _table_size = unit.request_permutation_table writes.size
          func_name = symbol_to_c pref_func_name(id), arch_ctx_prefix

          io.block "static void\n#{func_name}(#{inst_enc_ctx_c_type} *#{state_machine_ctx_var_name},"\
            " #{params_c_args}, #{unit.param_names.c_type} order)" do
            io.puts 'int i;'
            io.block "for(i = 0; i < #{writes.size}; i++)" do
              io.block "switch(#{table_var_name}[param_vals[order]][i])" do
                writes.each_with_index do |write, index|
                  cond, write_args = write
                  io.block "case #{index}:" do
                    translate_condition cond do
                      io.puts write_to_c(*write_args)
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
    end
  end
end