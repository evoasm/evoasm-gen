require 'evoasm/gen/translation/state_machine_translator'

module Evoasm
  module Gen
    class InstructionTranslator < StateMachineTranslator

      def initialize(unit, instruction)
        super(unit, instruction)
      end

      def instruction
        state_machine
      end

      def translate!
        io.block "size_t #{inst_enc_func_name instruction}(#{inst_enc_ctx_c_type})" do
          # body
          super(true)
        end
      end

      def string
        @io.string
      end
    end
  end
end