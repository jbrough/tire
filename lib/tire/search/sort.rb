module Tire
  module Search

    class Sort
      def initialize(&block)
        @value = []
        block.arity < 1 ? self.instance_eval(&block) : block.call(self) if block_given?
      end

      def by(name, direction=nil)
        @value << ( direction ? { name => direction } : name )
        self
      end

      def geo(location)
        @value <<  {
          '_geo_distance' => {
            'location' => location,
            'order'=> 'asc',
            'unit' => 'km'
          }
        }
      end

      def to_ary
        @value
      end

      def to_json
        @value.to_json
      end
    end

  end
end
