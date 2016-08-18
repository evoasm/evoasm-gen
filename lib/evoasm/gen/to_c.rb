require 'evoasm/gen/nodes'
require 'evoasm/gen/to_c/nodes'
require 'evoasm/gen/to_c/state_machine'
require 'evoasm/gen/to_c/instruction'

require 'evoasm/gen/x64/instruction'

module Evoasm
  module Gen
    module ToC
      CLASSES = %i(
        LogAction AccessAction
        WriteAction UnorderedWritesAction
        StringLiteral IntegerLiteral
        TrueLiteral FalseLiteral
        Parameter CallAction
        UnorderedWrites Expression
        Operation SetAction
        ErrorAction Register
        ErrorCode
        LocalVariable SharedVariable
        Else
      ).freeze

      CLASSES.each do |cls|
        Gen.const_get(cls).send :include, const_get(:"#{cls}ToC")
      end

      StateMachine.send :include, StateMachineToC
      X64::Instruction.send :include, InstructionToC

    end
  end
end