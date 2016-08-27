require 'evoasm/gen/nodes'

module Evoasm
  module Gen
    module Nodes
      class Operand < Node

        def instruction
          parent
        end
      end
    end
  end
end

