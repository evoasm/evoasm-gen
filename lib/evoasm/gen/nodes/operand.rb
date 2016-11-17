require 'evoasm/gen/nodes'

module Evoasm
  module Gen
    module Nodes
      class Operand < Node

        def instruction
          parent.instruction
        end
      end
    end
  end
end

