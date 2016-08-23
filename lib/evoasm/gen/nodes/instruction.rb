require 'evoasm/gen/nodes/state_machine'

module Evoasm
  module Gen
    module Nodes
      class Instruction < StateMachine
        def parameters
          @parameters ||= parameter_variables.map do |parameter_variable|
            if parameter_variable.name
              Parameter.new unit, parameter_variable.name,
                            parameter_variable.domain || parameter_domain(parameter_variable.name)
            end
          end.compact

          @parameters
        end
      end
    end
  end
end

