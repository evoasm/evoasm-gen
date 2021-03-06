require 'set'
require 'evoasm/gen/core_ext/string'
require 'evoasm/gen/nodes'

module Evoasm
  module Gen
    module Nodes
      Action = def_node Node
      WriteAction = def_node Action, :values, :sizes
      LogAction = def_node Action, :level, :msg, :args
      AccessAction = def_node Action, :operand
      CallAction = def_node Action, :state_machine
      SetAction = def_node Action, :variable, :value
      UnorderedWritesAction = def_node Action, :parameter, :unordered_writes
      ErrorAction = def_node Action, :code, :message, :register, :parameter
    end
  end
end
