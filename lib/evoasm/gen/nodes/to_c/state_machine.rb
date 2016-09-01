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
            @io = StringIO.new
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
              io.puts "#{unit.c_parameter_value_type_name} #{local_variables.map(&:name).join ', '};"
              local_variables.each do |variable|
                io.puts "(void) #{variable.name};"
              end
            end

            io.puts 'bool retval = true;'

            if translate_acc
              io.puts "#{unit.symbol_to_c :bitmap128, type: true} acc;"
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
            raise if state.nil?

            untranslated_states = []

            raise if state.returns? && !state.terminal?

            translate_body state, untranslated_states

            untranslated_states.each do |untranslated_state|
              translate_state untranslated_state
            end
          end

          def translate_body(state, untranslated_states, inlined: false)
            raise state.actions.inspect unless state.deterministic?
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

          def translate_ret(_state)
            io.puts 'goto exit;'
          end

          def state_label(state, id = nil)
            "L#{id || id_map[state]}"
          end

          def translate_goto_transition(transition)
            io.puts "goto #{state_label transition};"
          end

          def translate_transition(state, condition, untranslated_states, &block)
            condition.if_to_c io do
              if state.inlineable?
                block[] if block
                translate_body(state, untranslated_states, inlined: true)
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
            transitions = state.ordered_transitions

            transitions.each do |child, condition|
              translate_transition child, condition, untranslated_states, &block
            end

            raise 'missing else branch' if state.can_get_stuck?
          end

          def translate_actions(_state, actions, _untranslated_states)
            io.puts '/* actions */'
            until actions.empty?
              action = actions.pop
              action.to_c io
            end
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
          "#{c_return_type_name} #{c_function_name}(#{unit.c_context_type} *ctx)"
        end

        def c_return_type_name
          'evoasm_success_t'
        end

        def c_function_name
          attrs_str = self.class.attributes
                        .map { |k| [k.to_s.sub(/\?$/, '_p'), send(k)].join('_') }
                        .flatten.join('__')

          class_name = self.class.name.split('::').last
          unit.symbol_to_c "#{class_name}_#{attrs_str}", unit.architecture_prefix
        end
      end
    end
  end
end
