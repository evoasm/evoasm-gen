module Evoasm
  module Gen
    class Unit
      def node(node_class, *array, **hash)
        @nodes ||= Hash.new { |h, k| h[k] = []}

        attrs = array.empty? ? hash : array

        node = @nodes[node_class].find do |node|
          node.match?(attrs)
        end

        return node if node

        if attrs.is_a? Hash
          add_node node_class, hash_to_attr_args(node_class, attrs)
        else
          add_node node_class, attrs
         end
      end

      def nodes_of_class(*node_classes)
        @nodes.values_at(*node_classes).flatten
      end

      private

      def hash_to_attr_args(node_class, hash)
        attrs = []
        node_class.attributes.each do |attr|
          attrs.push hash.delete attr
        end
        raise ArgumentError, "invalid attributes #{hash.keys}" unless hash.empty?
        attrs
      end

      def add_node(node_class, attrs)
        node = node_class.new self, *attrs
        @nodes[node_class] << node
        node
      end
    end
  end
end
