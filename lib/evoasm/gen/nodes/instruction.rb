require 'evoasm/gen/nodes/state_machine'

module Evoasm
  module Gen
    module Nodes
      class Instruction < Node
        def parameters
          @parameters ||= state_machine.parameter_variables.map do |parameter_variable|
            if parameter_variable.name
              Parameter.new unit, parameter_variable.name,
                            parameter_variable.domain || parameter_domain(parameter_variable.name)
            end
          end.compact
        end
      end
    end
  end
end

