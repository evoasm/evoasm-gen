require 'evoasm/gen/nodes'

module Evoasm
  module Gen
    module Nodes
      class Operand < Node

        # NOTE: cannot use node attribute here, because
        # this is a cyclic references
        attr_reader :instruction

        def initialize(unit, instruction)
          super(unit)
          @instruction = instruction
        end
      end
    end
  end
end

