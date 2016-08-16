require 'evoasm/gen/strio'
require 'evoasm/gen/translation/name_util'

module Evoasm
  module Gen
    module WriteActionToC
      def to_c(unit, io)
        if size.is_a?(Array) && value.is_a?(Array)
          value_c, size_c = value.reverse.zip(size.reverse).inject(['0', 0]) do |(v_, s_), (v, s)|
            [v_ + " | ((#{expr_to_c v} & ((1 << #{s}) - 1)) << #{s_})", s_ + s]
          end
        else
          value_c =
            case value
            when Integer
              '0x' + value.to_s(16)
            else
              expr_to_c value
            end

          size_c = expr_to_c size
        end

        call_to_c "write#{size_c}", [value_c], base_arch_ctx_prefix, eol: true
      end
    end
  end
end
