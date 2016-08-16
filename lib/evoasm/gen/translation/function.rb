module Evoasm
  module Gen
    class Function
      attr_reader :unit

      def initialize(unit)
        @unit = unit
      end

      def new_for_state_machine(unit, state_machine)
        attrs = state_machine.attrs.map { |k, v| [k, v].join('_') }.flatten.join('__')
        name = "#{state_machine.class.name.split('::').last.downcase}_#{attrs}_#{id}"

        new unit, :state_machine, name
      end

      def definition_to_c(io)
        prototype_to_c(io)

        io.indent do
          io.puts body.to_s
        end

        io.puts '}'
        io.puts
      end

      def call_to_c(args)
        "#{name}(#{args.join ','})"
      end

      private

      def prototype_to_c(io)
        func_name = symbol_to_c name, arch

        io.write 'static ' if static?
        io.puts return_type
        io.write func_name
        io.write '('
        io.write
        params.each_with_index do |(param, type), index|
          io.write "#{type} #{param}"
          io.write ',' unless index == params.size - 1
        end
        io.write ')'
      end
    end

    class StateMachineFunction < Function
      attr_reader :state_machine

      def initialize(unit, state_machine)
        super(unit)
        @state_machine = state_machine
      end

      def name
        attrs = state_machine.attrs.map { |k, v| [k, v].join('_') }.flatten.join('__')
        symbol_to_c "#{state_machine.class.name.split('::').last.downcase}_#{attrs}_#{id}"
      end

      def call_to_c(args)
        super(args.dup.shift state_machine_ctx_var_name)
      end

      def parameters
        [
          [arch_ct]
        ]
      end

      def return_type
        'size_t'
      end

      def static?
        true
      end
    end

    class InstructionFunction < StateMachineFunction
      alias_method :instruction, :state_machine

      def initialize(unit, instruction)
        super(unit, instruction)
      end

      def to_c
        translator = StateMachineTranslator.new unit

      end

      def static?
        false
      end

      def name
        inst_enc_func_name instruction
      end
    end
  end
end
