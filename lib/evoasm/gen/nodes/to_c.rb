module Evoasm
  module Gen
    module Nodes
      def self.def_to_c(node_class, &block)
        node_class.send :define_method, :to_c, &block
      end
    end
  end
end

require 'evoasm/gen/nodes/to_c/others'
require 'evoasm/gen/nodes/to_c/actions'
require 'evoasm/gen/nodes/to_c/state_machine'
require 'evoasm/gen/nodes/to_c/instruction'
require 'evoasm/gen/nodes/to_c/enum'
