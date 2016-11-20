module Evoasm
  module Gen
    module Nodes
      def self.def_to_c(node_class, &block)
        node_class.send :define_method, :to_c, &block
      end

      module ToC
        class StructInitializer
          def initialize
            @fields = []
          end

          def to_s
            io = StringIO.new
            io.block do
              @fields.each do |field_name, field_value|
                io.write ".#{field_name} = #{field_value},"
              end
            end
            io.string
          end

          def []=(field_name, value)
            @fields << [field_name, value]
          end
        end
      end
    end
  end
end

require 'evoasm/gen/nodes/to_c/others'
require 'evoasm/gen/nodes/to_c/actions'
require 'evoasm/gen/nodes/to_c/state_machine'
require 'evoasm/gen/nodes/to_c/instruction'
require 'evoasm/gen/nodes/to_c/instruction_state_machine'
require 'evoasm/gen/nodes/to_c/operand'
require 'evoasm/gen/nodes/to_c/x64/operand'
require 'evoasm/gen/nodes/to_c/x64/instruction'
require 'evoasm/gen/nodes/to_c/enumeration'
require 'evoasm/gen/nodes/to_c/parameters_type'
