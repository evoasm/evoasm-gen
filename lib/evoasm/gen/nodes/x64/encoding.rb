require 'evoasm/gen/state_dsl'

module Evoasm
  module Gen
    module Nodes
      module X64
        module REXUtil
          include StateDSL

          PARAMETERS = %i(rex_r rex_x rex_b
                          force_rex? reg_index
                          reg_base rex_w reg0 reg1).freeze

          def rex_bit(reg)
            [:div, [:reg_code, reg], 8]
          end

          def rex_b_rm_reg
            set :_rex_b, rex_bit(rm_reg_param)
            to rex_locals_set
          end

          def rex_b_reg_reg
            set :_rex_b, rex_bit(reg_param)
            to rex_locals_set
          end

          def rex_b_base_reg
            log :trace, 'setting rex_b from base'
            set :_rex_b, rex_bit(:reg_base)
            to rex_locals_set
          end

          def rex_w_free_value
            if basic?
              0b0
            else
              :rex_w
            end
          end

          static_state def rex_b
            log :trace, 'setting rex_b... modrm_rm='

            # FIXME: can REX.b ever be ignored ?
            # set :_rex_b, :rex_b
            # to rex_locals_set

            if !encodes_modrm?
              if reg_param
                rex_b_reg_reg
              else
                # currently only taken for NP and VEX
                if basic?
                  # rex_b is not basic
                  set :_rex_b, 0b0
                else
                  set :_rex_b, :rex_b
                end
                to rex_locals_set
              end
            else
              case rm_reg_type
                # RM can only encode register
                # e.g. vmaskmovdqu_xmm_xmm"
              when :reg
                log :trace, 'setting rex_b from modrm_rm'
                rex_b_rm_reg
                # RM is allowed to encode both
              when :rm
                if basic?
                  rex_b_rm_reg
                else
                  to_if :set?, :reg_base, &method(:rex_b_base_reg)
                  else_to(&method(:rex_b_rm_reg))
                end
                # RM is allowed to only encode memory operand
              when :mem
                rex_b_base_reg
              when :vsib
                rex_b_base_reg
              else
                fail "unknown rm reg type '#{rm_reg_type}'"
              end
            end
          end

          def set_rex_r_free
            if basic?
              set :_rex_r, 0b0
            else
              set :_rex_r, :rex_r
            end
          end

          def rex_x_free
            if basic?
              set :_rex_x, 0b0
            else
              set :_rex_x, :rex_x
            end
            to rex_b
          end

          def rex_x_index
            set :_rex_x, rex_bit(:reg_index)
            log :trace, 'rex_b... A'
            to rex_b
          end

          static_state def rex_rx

                         # MI and other encodings
                         # do not use the MODRM.reg field
                         # so the corresponding REX bit
                         # is ignored

            if encodes_modrm?
              if reg_param
                set :_rex_r, rex_bit(reg_param)
              else
                set_rex_r_free
              end

              case rm_reg_type
              when :reg
                rex_x_free
              when :rm
                if basic?
                  rex_x_free
                else
                  to_if :set?, :reg_index, &method(:rex_x_index)
                  else_to(&method(:rex_x_free))
                end
              when :mem
                raise 'cannot encode mem operand in basic mode' if basic?
                rex_x_index
              when :vsib
                raise 'cannot encode vsib operand in basic mode' if basic?
                rex_x_index
              else
                raise "unknown reg type '#{rm_reg_type}'"
              end
            else
              set_rex_r_free
              rex_x_free
            end
          end
        end

        class REX < StateMachine
          node_attrs :rex_w, :reg_param, :rm_reg_param, :force,
                     :rm_reg_type, :encodes_modrm?, :byte_regs, :basic?

          include REXUtil
          include StateDSL

          params *REXUtil::PARAMETERS, :reg0

          # reg_param
          # and rm_reg_param
          # are REGISTERS
          # and NOT register ids
          # or bitfield values

          def base_or_index?
            raise 'cannot encode base/index in basic mode' if basic?
            encodes_modrm? && rm_reg_type != :reg
          end

          def rex_byte_reg?(reg_param)
            [:in?, reg_param, :SP, :BP, :SI, :DI]
          end

          def need_rex?
            cond = [:or]
            cond << [:neq, rex_bit(reg_param), 0] if reg_param

            unless basic?
              cond << [:and, [:set?, rm_reg_param], [:neq, rex_bit(rm_reg_param), 0]] if rm_reg_param
              cond << [:and, [:set?, :reg_base], [:neq, rex_bit(:reg_base), 0]] if base_or_index?
              cond << [:and, [:set?, :reg_index], [:neq, rex_bit(:reg_index), 0]] if base_or_index?
            end

            cond << rex_byte_reg?(reg_param) if reg_param && byte_regs
            cond << rex_byte_reg?(rm_reg_param) if rm_reg_param && byte_regs

            cond == [:or] ? false : cond
          end

          static_state def root_state
            if force
              set :@encode_rex, true
              to rex_rx
            else
              # rex?: output REX even if not force
              # need_rex?: REX is required (use of ext. reg.)

              encode_rex_cond =
                if basic?
                  need_rex?
                else
                  [:or, [:true?, :force_rex?], need_rex?]
                end

              to_if encode_rex_cond do
                set :@encode_rex, true
                to rex_rx
              end
              else_to do
                set :@encode_rex, false
                return!
              end
            end
          end

          def rex_locals_set
            write_rex
          end

          static_state def write_rex
            comment 'REX prefix'
            rex_w = self.rex_w

            # assume rex_w is set if the
            # attr rex_w is nil
            # unset default 0 is ok
            rex_w ||= rex_w_free_value

            write [0b0100, rex_w, :_rex_r, :_rex_x, :_rex_b], [4, 1, 1, 1, 1]
            log :trace, 'writing rex % % % %', rex_w, :_rex_r, :_rex_x, :_rex_b

            return!
          end
        end

        module EncodeUtil
          def reg_bits(reg_param)
            [:mod, [:reg_code, reg_param], 8]
          end

          def set_reg_bits(local_name, reg_param, byte_reg, &block)
            set local_name, reg_bits(reg_param)
            if byte_reg
              to_if :true?, :"#{reg_param}_high_byte?" do
                to_if :in?, reg_param, :A, :C, :D, :B do
                  to_if :true?, :@encode_rex do
                    error :not_encodable, 'cannot be encoded with REX', param: reg_param
                  end
                  else_to do
                    set local_name, [:add, local_name, 4]
                    to &block
                  end
                end
                else_to do
                  error :not_encodable, 'inexistent high-byte register', param: reg_param
                end
              end
              else_to do
                to &block
              end
            else
              block[]
            end
          end
        end

        class ModRMSIB < StateMachine
          node_attrs :reg_param, :rm_reg_param, :rm_type,
                     :modrm_reg_bits, :rm_reg_access,
                     :reg_access, :byte_regs, :basic?

          include StateDSL
          include EncodeUtil

          params :reg_base, :reg_index, :scale, :disp, :disp_size,
                 :force_disp32?, :force_sib?, :reg0, :reg1, :reg2,
                 :reg0_high_byte?, :reg1_high_byte?, :modrm_reg

          def write_modrm__(mod_bits, &block)
            write [mod_bits, :_reg_bits, :_rm_bits], [2, 3, 3]
            to &block
          end

          def write_modrm_(mod_bits, rm_bits, rm_reg_param, byte_regs, &block)
            if rm_bits
              set :_rm_bits, rm_bits
              write_modrm__(mod_bits, &block)
            else
              set_reg_bits :_rm_bits, rm_reg_param, byte_regs do
                write_modrm__(mod_bits, &block)
              end
            end
          end

          def write_modrm(mod_bits:, rm_bits: nil, rm_reg_param: nil, byte_regs: false, &block)
            raise ArgumentError, 'must provide either rm_bits or rm_reg_param' unless rm_bits || rm_reg_param

            if modrm_reg_bits
              set :_reg_bits, modrm_reg_bits
              write_modrm_(mod_bits, rm_bits, rm_reg_param, byte_regs, &block)
            elsif reg_param
              # register, use register parameter specified
              # in reg_param
              set_reg_bits :_reg_bits, reg_param, byte_regs do
                write_modrm_(mod_bits, rm_bits, rm_reg_param, byte_regs, &block)
              end
            else
              # ModRM.reg is free, use a parameter
              # or zero in basic mode
              if basic?
                set :_reg_bits, 0b00
              else
                set :_reg_bits, :modrm_reg
              end
              write_modrm_(mod_bits, rm_bits, rm_reg_param, byte_regs, &block)
            end
          end

          def write_sib(scale = nil, index = nil, base = nil)
            write [
                    scale || [:log2, :scale],
                    index || reg_bits(:_reg_index),
                    base || reg_bits(:reg_base)
                  ], [2, 3, 3]
          end

          def zero_disp?
            # NOTE: unset disp defaults to 0 as well
            [:eq, :disp, 0]
          end

          def matching_disp_size?
            [:or, [:unset?, :disp_size], [:eq, :disp_size, [:disp_size]]]
          end

          def disp_fits?(size)
            [:ltq, [:disp_size], size]
          end

          def disp?(size)
            [
              :and,
              disp_fits?(size),
              matching_disp_size?
            ]
          end

          def vsib?
            rm_type == :vsib
          end

          def direct_only?
            rm_type == :reg
          end

          def indirect_only?
            rm_type == :mem
          end

          def modrm_sib_disp(rm_bits: nil, sib:, rm_reg_param: nil)
            to_if :and, zero_disp?,
                  matching_disp_size?,
                  reg_code_not_in?(:reg_base, 5, 13) do
              write_modrm(mod_bits: 0b00, rm_bits: rm_bits, rm_reg_param: rm_reg_param) do
                write_sib if sib
                return!
              end
            end
            else_to do
              to_if :and, disp_fits?(8), [:false?, :force_disp32?] do
                write_modrm(mod_bits: 0b01, rm_bits: rm_bits, rm_reg_param: rm_reg_param) do
                  write_sib if sib
                  write :disp, 8
                  return!
                end
              end
              else_to do
                write_modrm mod_bits: 0b10, rm_bits: rm_bits, rm_reg_param: rm_reg_param do
                  write_sib if sib
                  write :disp, 32
                  return!
                end
              end
            end
          end

          static_state def scale_index_base_
            modrm_sib_disp rm_bits: 0b100, sib: true
          end

          def index_encodable?
            [:neq, [:reg_code, :reg_index], 0b0100]
          end

          static_state def scale_index_base
            log :trace, 'scale, index, base'
            set :_reg_index, :reg_index

            if vsib?
              to scale_index_base_
            else
              to_if index_encodable?, scale_index_base_
              else_to do
                # not encodable
                error :not_encodable, 'index not encodable', param: :reg_index
              end
            end
          end

          static_state def disp_only
            log :trace, 'disp only'
            set :_reg_index, :reg_index
            write_modrm mod_bits: 0b00, rm_bits: 0b100 do
              write_sib nil, nil, 0b101
              write :disp, 32
              return!
            end
          end

          static_state def index_only
            log :trace, 'index only'

            condition =
              if vsib?
                true
              else
                index_encodable?
              end

            to_if condition do
              set :_reg_index, :reg_index
              write_modrm mod_bits: 0b00, rm_bits: 0b100 do
                write_sib nil, nil, 0b101
                write :disp, 32
                return!
              end
            end
            # NOTE: keep comparison with true!
            if condition != true
              else_to do
                error :not_encodable, 'index not encodable (0b0100)', param: :reg_index
              end
            end
          end

          static_state def base_only_w_sib
                         # need index to encode as 0b100 (RSP, ESP, SP)
            set :_reg_index, :SP
            to scale_index_base_
          end

          def ip_base?
            [:eq, :reg_base, :IP]
          end

          def reg_code_not_in?(reg, *ids)
            [:not_in?, [:reg_code, reg], *ids]
          end

          static_state def base_only_wo_sib
            modrm_sib_disp rm_reg_param: :reg_base, sib: false
          end

          static_state def base_only
            log :trace, 'base only'
            to_if ip_base? do
              write_modrm mod_bits: 0b00, rm_bits: 0b101 do
                write :disp, 32
                return!
              end
            end
            else_to do
              to_if :and, [:false?, :force_sib?], reg_code_not_in?(:reg_base, 4, 12), base_only_wo_sib
              else_to base_only_w_sib
            end
          end

          def no_index?
            [:unset?, :reg_index]
          end

          def no_base?
            [:unset?, :reg_base]
          end

          static_state def indirect
            log :trace, 'indirect addressing'
            # VSIB does not allow to omit index
            if vsib?
              to_if no_base? do
                to_if :set?, :reg_index, index_only
                else_to do
                  error :missing_param, param: :reg_index
                end
              end
              else_to scale_index_base
            else
              to_if no_base? do
                to_if no_index? do
                  to_if :set?, :disp, disp_only
                  else_to do
                    error :missing_param, param: :disp
                  end
                end
                else_to index_only
              end
              else_to do
                to_if no_index?, base_only
                else_to scale_index_base
              end
            end
          end

          static_state def direct
            access rm_reg_param, rm_reg_access if rm_reg_param

            raise "mem operand for direct encoding" if rm_type == :mem

            write_modrm mod_bits: 0b11, rm_reg_param: rm_reg_param, byte_regs: byte_regs do
              return!
            end
          end

          def indirect?
            [
              :or,
              [:set?, :reg_base],
              [:set?, :reg_index],
              [:set?, :disp]
            ]
          end

          static_state def root_state
            comment 'ModRM'
            log :trace, 'ModRM'

            access reg_param, reg_access if reg_param

            if direct_only? || basic?
              to direct
            else
              to_if indirect?, indirect

              # VSIB does not allow this
              if vsib? || indirect_only?
                else_to do
                  error :not_encodable, (vsib? ? "VSIB does not allow direct addressing" : "direct addressing not allowed")
                end
              else
                else_to direct
              end
            end
          end
        end

        class VEX < StateMachine
          node_attrs :rex_w, :reg_param, :rm_reg_param, :vex_m,
                     :vex_v, :vex_l, :vex_p, :encodes_modrm?,
                     :rm_reg_type, :basic?

          include REXUtil
          include StateDSL

          params *REXUtil::PARAMETERS, :force_long_vex?, :reg2,
                 :vex_l, :vex_v

          static_state def two_byte_vex
            log :trace, 'writing vex'
            write 0b11000101, 8
            write [
                    [:neg, :_rex_r],
                    [:neg, vex_v || vex_v_free_value],
                    (vex_l || vex_l_free_value),
                    vex_p
                  ], [1, 4, 1, 2]
            return!
          end

          static_state def three_byte_vex
            log :trace, 'writing vex'
            write 0b11000100, 8
            write [[:neg, :_rex_r],
                   [:neg, :_rex_x],
                   [:neg, :_rex_b],
                   vex_m], [1, 1, 1, 5]
            write [rex_w || rex_w_free_value,
                   [:neg, vex_v || vex_v_free_value],
                   vex_l || vex_l_free_value,
                   vex_p], [1, 4, 1, 2]
            return!
          end

          def vex_v_free_value
            if basic?
              0b0000
            else
              :vex_v
            end
          end

          def vex_l_free_value
            if basic?
              0b0000
            else
              :vex_l
            end
          end

          def zero_rex?
            cond =
              [
                :and,
                [:eq, :_rex_x, 0b0],
                [:eq, :_rex_b, 0b0]
              ]

            if !basic? && rex_w.nil?
              cond << [:eq, :rex_w, 0b0]
            end

            cond
          end

          static_state def rex_locals_set
                         # assume rex_w and vex_l set
                         # default unset 0 is ok for both
            if vex_m == 0x01 && rex_w != 0x1
              two_byte_vex_cond =
                if basic?
                  zero_rex?
                else
                  [:and, zero_rex?, [:false?, :force_long_vex?]]
                end
              to_if two_byte_vex_cond, two_byte_vex
              else_to three_byte_vex
            else
              to three_byte_vex
            end
          end

          static_state def root_state
            comment 'VEX'

            to rex_rx
          end
        end

      end
    end
  end
end
