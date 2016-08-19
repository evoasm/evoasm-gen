require 'evoasm/gen/nodes'
require 'evoasm/gen/nodes/actions'

require 'evoasm/gen/nodes/x64/instruction'

require 'evoasm/gen/to_c/nodes'
require 'evoasm/gen/to_c/actions'
require 'evoasm/gen/to_c/state_machine'
require 'evoasm/gen/to_c/instruction'
require 'evoasm/gen/to_c/enum'


module Evoasm
  module Gen
    module Nodes
      module ToC
        def self.def_to_c(node_class, &block)
          node_class.define_method :to_c, &block
        end
      end
    end
  end
end