

module Evoasm
  module Gen
    class FuncTranslator
      include TranslatorUtil

      INST_STATE_ID_MIN = 32
      INST_STATE_ID_MAX = 2000

      attr_reader :inst, :registered_params, :root_state
      attr_reader :main_translator, :id_map
      attr_reader :arch, :io, :param_domains

      def initialize(arch, main_translator)
        @arch = arch
        @main_translator = main_translator
        @id = INST_STATE_ID_MAX
        @id_map = Hash.new { |h, k| h[k] = (@id += 1) }
        @registered_params = Set.new
        @param_domains = {}
      end

      def with_io(io)
        @io = io
        yield
        @io = nil
      end

      def emit_func(name, root_state, func_params = [], local_acc: true, static: true)
        io.puts func_prototype_to_c(name, func_params, static: static), eol: ' {'

        io.indent do
          emit_func_prolog root_state, local_acc
          emit_state root_state
          emit_func_epilog local_acc
        end


        io.puts '}'
        io.puts
      end

      def emit_acc_ary_copy(back_copy = false)
        var_name = 'acc'
        src = "#{arch_var_name arch_indep: true}->#{var_name}"
        dst = var_name

        dst, src = src, dst if back_copy
        io.puts "#{dst} = #{src};"
      end

      def emit_func_prolog(root_state, acc)
        local_params = root_state.local_params
        unless local_params.empty?
          io.puts "#{param_val_c_type} #{local_params.join ', '};"
          local_params.each do |param|
            io.puts "(void) #{param};"
          end
        end

        io.puts 'bool retval = true;'

        if acc
          io.puts "#{acc_c_type} acc;"
          emit_acc_ary_copy
        end
      end

      def error_data_field_to_c(field_name)
        "#{arch_var_name arch_indep: true}->error_data.#{field_name}"
      end

      def emit_error(state, code, msg, reg = nil, param = nil)
        reg_c_val =
          if reg
            reg_name_to_c reg
          else
            "(uint8_t) -1"
          end
        param_c_val =
          if param
            param_to_c param
          else
            "(uint8_t) -1"
          end

        io.write <<-EOL
        evoasm_arch_error_data_t error_data = {
          .reg = #{reg_c_val},
          .param = #{param_c_val},
          .arch = #{arch_var_name arch_indep: true},
        };
        EOL

        io.puts %Q{evoasm_set_error(EVOASM_ERROR_TYPE_ARCH, #{error_code_to_c code}, &error_data, "#{msg}");}
        io.puts 'retval = false;'
      end

      def emit_func_epilog(acc)
        io.indent 0 do
          io.puts "exit:"
        end
        emit_acc_ary_copy true if acc
        io.puts "return retval;"

        io.indent 0 do
          io.puts "error:"
        end

        io.puts 'retval = false;'
        io.puts 'goto exit;'
      end

      def emit_state(state)
        fail if state.nil?

        unemitted_states = []

        fail if state.ret? && !state.terminal?

        emit_body state, unemitted_states

        unemitted_states.each do |unemitted_state|
          emit_state unemitted_state
        end
      end

      def emit_body(state, unemitted_states, inlined = false)
        fail state.actions.inspect unless deterministic?(state)
        io.puts '/* begin inlined */' if inlined

        emit_label state unless inlined

        actions = state.actions.dup.reverse
        emit_actions state, actions, unemitted_states

        emit_ret state if state.ret?

        emit_transitions(state, unemitted_states)

        io.puts '/* end inlined */' if inlined
      end

      def emit_comment(state)
        io.puts "/* #{state.comment} (#{state.object_id}) */" if state.comment
      end

      def emit_label(state)
        io.indent 0 do
          io.puts "#{state_label state}:;"
        end
      end

      def has_else?(state)
        state.children.any? { |_, cond| cond == [:else] }
      end

      def emit_ret(state)
        io.puts "goto exit;"
      end

      def state_label(state, id = nil)
        "L#{id || id_map[state]}"
      end

      def emit_call(state, func)
        id = main_translator.request_func_call func, self

        func_call = call_to_c called_func_name(func, id),
                              [*params_args, inst_name_to_c(inst), '&acc'],
                              arch_prefix

        io.puts "if(!#{func_call}){goto error;}"
      end

      def emit_goto_transition(child)
        io.puts "goto #{state_label child};"
      end

      def emit_transitions(state, unemitted_states, &block)
        state
          .children
          .sort_by { |_, _, attrs| attrs[:priority] }
          .each do |child, expr|
          emit_cond expr do
            if inlineable?(child)
              block[] if block
              emit_body(child, unemitted_states, true)
              true
            else
              unemitted_states << child unless id_map.key?(child)
              block[] if block
              emit_goto_transition(child)
              false
            end
          end
        end

        fail 'missing else branch' if can_get_stuck?(state)
      end

      def can_get_stuck?(state)
        return false if state.ret?
        return false if has_else? state

        fail state.actions.inspect if state.children.empty?

        return false if state.children.any? do |_child, cond|
          cond.nil? || cond == [true]
        end

        true
      end

      def helper_call_to_c(name, args)
        prefix =
          if NO_ARCH_HELPERS.include?(name)
            nil
          else
            arch_prefix
          end

        call_to_c name, args, prefix
      end

      def simplify_helper(helper)
        simplified_helper = simplify_helper_ helper
        return simplified_helper if simplified_helper == helper
        simplify_helper simplified_helper
      end

      def simplify_helper_(helper)
        name, *args = helper
        case name
        when :neq
          [:not, [:eq, *args]]
        when :false?
          [:eq, *args, 0]
        when :true?
          [:not, [:false?, *args]]
        when :unset?
          [:not, [:set?, args[0]]]
        when :in?
          [:or, *args[1..-1].map { |arg| [:eq, args.first, arg] }]
        when :not_in?
          [:not, [:in?, *args]]
        else
          helper
        end
      end

      def emit_cond(cond, else_if: false, &block)
        cond_str =
          if cond.nil? || cond == true
            ''
          elsif cond[0] == :else
            'else '
          else
            "#{else_if ? 'else ' : ''}if(#{expr_to_c cond})"
          end

        emit_c_block cond_str, &block
      end

      def emit_log(_state, level, msg, *exprs)
        expr_part =
          if !exprs.empty?
            ", #{exprs.map { |expr| "(#{param_val_c_type}) #{expr_to_c expr}" }.join(', ')}"
          else
            ''
          end
        msg = msg.gsub('%', '%" EVOASM_PARAM_VAL_FORMAT "')
        io.puts %[evoasm_#{level}("#{msg}" #{expr_part});]
      end

      def emit_assert(_state, *expr)
        io.puts "assert(#{expr_to_c expr});"
      end

      def set_p_to_c(key, eol: false)
        call_to_c 'bitmap_get',
                  ["(#{bitmap_c_type} *) set_params", param_to_c(key)],
                  eol: eol
      end

      def get_to_c(key, eol: false)
        if local_param? key
          key.to_s
        else
          "param_vals[#{param_to_c(key)}]" + (eol ? ';' : '')
        end
      end

      def emit_set(_state, key, value, c_value: false)
        fail "setting non-local param '#{key}' is not allowed" unless local_param? key

        c_value =
          if c_value
            value
          else
            expr_to_c value
          end

        io.puts "#{key} = #{c_value};"
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

      def emit_actions(state, actions, _unemitted_states)
        io.puts '/* actions */'
        until actions.empty?
          name, args = actions.last
          actions.pop
          send :"emit_#{name}", state, *args
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

      def emit_c_block(code = nil, &block)
        io.puts "#{code}{"
        io.indent do
          block[]
        end
        io.puts '}'
      end

      def emit_unordered_writes(state, param_name, writes)
        if writes.size > 1
          id, table_size = main_translator.request_pref_func writes, self
          func_name = pref_func_name(id)

          call_c = call_to_c(func_name,
                             [*params_args, param_name_to_c(param_name)],
                             arch_prefix)

          io.puts call_c, eol: ';'

          register_param param_name
          @param_domains[param_name] = (0..table_size - 1)
        elsif writes.size > 0
          cond, write_args = writes.first
          emit_cond cond do
            emit_write(state, *write_args)
          end
        end
      end

      def emit_read_access(state, op)
        call = access_call_to_c 'read', op, "#{arch_var_name(true)}->acc",
                                [inst && inst_name_to_c(inst) || 'inst']

        #emit_c_block "if(!#{call})" do
        #  emit_exit error: true
        #end
        io.puts call, eol: ';'
      end

      def access_call_to_c(name, op, acc = 'acc', params = [], eol: false)
        call_to_c("#{name}_access",
                  [
                    "(#{bitmap_c_type} *) &#{acc}",
                    "(#{regs.c_type}) #{expr_to_c(op)}",
                    *params
                  ],
                  indep_arch_prefix,
                  eol: eol)
      end

      def emit_write_access(_state, op)
        io.puts access_call_to_c('write', op, eol: true)
      end

      def emit_undefined_access(_state, op)
        io.puts access_call_to_c('undefined', op, eol: true)
      end

      def write_to_c(value, size)
        if size.is_a?(Array) && value.is_a?(Array)
          value_c, size_c = value.reverse.zip(size.reverse).inject(['0', 0]) do |(v_, s_), (v, s)|
            [v_ + " | ((#{expr_to_c v} & ((1 << #{s}) - 1)) << #{s_})", s_ + s]
          end
        else
          value_c =
            case value
            when Integer
              '0x' + value.to_s(16)
            else
              expr_to_c value
            end

          size_c = expr_to_c size
        end

        call_to_c "write#{size_c}", [value_c], indep_arch_prefix, eol: true
      end

      def emit_write(_state, value, size)
        io.puts write_to_c(value, size)
      end

      def emit_access(state, op, access)
        #access.each do |mode|
        #  case mode
        #  when :r
        #    emit_read_access state, op
        #  when :w
        #    emit_write_access state, op
        #  when :u
        #    emit_undefined_access state, op
        #  else
        #    fail "unexpected access mode '#{rw.inspect}'"
        #  end
        #end
      end

      def emit_inst_func(io, inst)
        @inst = inst
        with_io io do
          emit_func inst.name, inst.root_state, static: false
        end
      end

      def emit_called_func(io, func, id)
        with_io io do
          emit_func(called_func_name(func, id),
                    func.root_state,
                    {'inst' => inst_id_c_type, 'acc' => "#{acc_c_type} *"},
                    local_acc: false)
        end
      end

      def emit_pref_func(io, writes, id)
        with_io io do
          table_var_name, _table_size = main_translator.request_permutation_table writes.size
          func_name = name_to_c pref_func_name(id), arch_prefix

          emit_c_block "static void\n#{func_name}(#{arch_c_type} *#{arch_var_name},"\
            " #{params_c_args}, #{main_translator.param_names.c_type} order)" do
            io.puts 'int i;'
            emit_c_block "for(i = 0; i < #{writes.size}; i++)" do
              emit_c_block "switch(#{table_var_name}[param_vals[order]][i])" do
                writes.each_with_index do |write, index|
                  cond, write_args = write
                  emit_c_block "case #{index}:" do
                    emit_cond cond do
                      io.puts write_to_c(*write_args)
                    end
                    io.puts 'break;'
                  end
                end
                io.puts "default: evoasm_assert_not_reached();"
              end
            end
          end
        end
      end
    end
  end
end