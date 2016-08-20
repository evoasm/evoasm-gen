require 'evoasm/gen/nodes/state_machine'
require 'evoasm/gen/nodes/to_c'

module Evoasm
  module Gen
    module Nodes
      class StateMachine
        class StateMachineCTranslator
          INST_STATE_ID_MIN = 32
          INST_STATE_ID_MAX = 2000

          def initialize(unit, state_machine)
            @unit = unit
            @id ||= INST_STATE_ID_MAX
            @id_map ||= Hash.new { |h, k| h[k] = (@id += 1) }
            @state_machine = state_machine
            @io = StrIO.new
            @io.indent = 2
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
            local_variables = state_machine.root_state.local_variables
            unless local_variables.empty?
              io.puts "#{unit.inst_param_val_c_type} #{local_variables.join ', '};"
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

          def translate_label(state)
            io.indent 0 do
              io.puts "#{state_label state}:;"
            end
          end

          def has_else?(state)
            state.children.any? { |_, condition| condition.is_a?(Else) }
          end

          def translate_ret(_state)
            io.puts 'goto exit;'
          end

          def state_label(state, id = nil)
            "L#{id || id_map[state]}"
          end

          def translate_goto_transition(child)
            io.puts "goto #{state_label child};"
          end

          def translate_transition(state, untranslated_states, condition, &block)
            condition.if_to_c io do
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

          def translate_actions(state, actions, _untranslated_states)
            io.puts '/* actions */'
            until actions.empty?
              action = actions.pop
              action.to_c io
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
        end

        def call_to_c
          "if(!#{c_function_name}(ctx)){goto error;}"
        end

        def to_c(io)
          translator = StateMachineCTranslator.new unit, self
          translator.translate!

          io.block c_prototype, 0 do
            io.puts translator.string
          end
        end

        def c_prototype
          "#{c_return_type} #{c_function_name}(#{unit.c_context_type} *ctx)"
        end

        def c_return_type
          'size_t'
        end

        def c_function_name
          name = self.class.attributes.map { |k, v| [k, v].join('_') }.flatten.join('__')
          unit.symbol_to_c name, unit.architecture_prefix
        end
      end
    end
  end
end
