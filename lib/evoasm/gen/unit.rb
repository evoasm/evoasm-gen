module Evoasm
  module Gen
    class Unit
      def find_or_create_node(class_, attrs)
        @nodes ||= []

        node = @nodes.find do |node|
          node.is_a?(class_) && node.match?(attrs)
        end

        return node if node

        attr_args = []
        class_.attributes.each do |attr|
          attr_args.push attrs[attr]
        end

        node = class_.new self, *attr_args

        @nodes << node

        node
      end
    end
  end
end
