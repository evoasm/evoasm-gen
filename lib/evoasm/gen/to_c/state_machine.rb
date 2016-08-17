require 'evoasm/gen/to_c/state_machine_translator'

module Evoasm
  module Gen
    module StateMachineToC

      def call_to_c(unit)
        "#{c_function_name unit}(ctx)"
      end

      def to_c(unit, io)
        translator = StateMachineTranslator.new unit, self
        translator.translate!

        io.block "size_t #{c_function_name(unit)}(#{c_context_type(unit)})" do
          translator.string
        end
      end

      private

      def c_function_name(unit)
        name = self.class.attrs.map { |k, v| [k, v].join('_') }.flatten.join('__')
        unit.symbol_to_c name, unit.arch_prefix
      end

      def c_context_type(unit)
        "evoasm_#{unit.arch}_inst_enc_ctx"
      end
    end
  end
end