require 'evoasm/gen/state_dsl'
require 'evoasm/gen/nodes/state_machine'
require 'evoasm/gen/nodes/x64/encoding'
require 'evoasm/gen/core_ext/array'
require 'evoasm/gen/core_ext/integer'
require 'evoasm/gen/x64'

module Evoasm
  module Gen
    module Nodes
      module X64
        class Instruction < Nodes::Instruction
          include StateDSL
          include EncodeUtil # for set_reg_code

          require 'evoasm/gen/nodes/x64/operand'

          attrs :mnem, :opcode,
                :operands,
                :encoding, :features,
                :prefs, :name, :index,
                :flags, :exceptions

          params :imm0, :lock?, :legacy_prefix_order, :rel,
                 :imm1, :moffs, :addr_size, :reg0, :reg1, :reg2, :reg3,
                 :reg0_high_byte?

          local_vars :reg_code

          COL_OPCODE = 0
          COL_MNEM = 1
          COL_OP_ENC = 2
          COL_OPS = 3
          COL_PREFS = 4
          COL_FEATURES = 5
          COL_EXCEPTIONS = 6

          HEX_BYTE_REGEXP = /^[A-F0-9]{2}$/

          LEGACY_PREFIX_BYTES = {
            cs_bt: 0x2E,
            ss: 0x36,
            ds_bnt: 0x3E,
            es: 0x26,
            fs: 0x64,
            gs: 0x65,
            lock: 0xF0,
            pref66: 0x66,
            pref67: 0x67
          }.freeze

          LEGACY_PREFIX_CONDITIONS = {
            pref67: [:eq, :addr_size, :ADDR_SIZE32]
          }.freeze

          MAND_PREF_BYTES = %w(66 F2 F3 F0)

          OPERAND_TYPES = %i(reg rm vsib mem imm)

          def initialize(unit, index, row)
            super(unit, {})

            self.index = index
            self.mnem = row[COL_MNEM]
            self.encoding = row[COL_OP_ENC]
            self.opcode = row[COL_OPCODE].split(/\s+/)

            load_features row
            load_exceptions row
            load_operands row
            load_prefs row

            load_flags

            self.name = name
          end

          # NOTE: enum domains need to be sorted
          # (i.e. by their corresponding C enum numeric value)
          GP_REGISTERS = Gen::X64::REGISTERS.fetch(:gp)[0..-5] - [:SP]

          def param_domain(param_name)
            case param_name
            when :rex_b, :rex_r, :rex_x, :rex_w,
              :vex_l, :force_rex?, :lock?, :force_sib?,
              :force_disp32?, :force_long_vex?, :reg0_high_byte?,
              :reg1_high_byte?
              (0..1)
            when :addr_size
              [32, 64]
            when :disp_size
              [16, 32]
            when :scale
              [1, 2, 4, 8]
            when :modrm_reg
              (0..7)
            when :vex_v
              (0..15)
            when :reg_base
              GP_REGISTERS
            when :reg_index
              case reg_operands[1].type
              when :vsib
                X64::REGISTERS.fetch :xmm
              when :mem, :rm
                GP_REGISTERS
              else
                raise
              end
            when :imm0, :imm1, :imm, :moffs, :rel
              imm_op = encoded_operands.find { |op| op.param == param_name }
              case imm_op.size
              when 8
                :int8
              when 16
                :int16
              when 32
                :int32
              when 64
                :int64
              else
                raise "unexpected imm size '#{imm_op.size}'"
              end
            when :disp
              :int32
            when :reg0, :reg1, :reg2, :reg3
              reg_op = encoded_operands.find { |op| op.param == param_name }

              case reg_op.reg_type
              when :xmm
                xmm_regs zmm: false
              when :zmm
                xmm_regs zmm: true
              when :gp
                GP_REGISTERS
              else
                X64::REGISTERS.fetch reg_op.reg_type
              end
            else
              raise "missing domain for param #{param_name}"
            end
          end

          def name
            ops_str = operands.select(&:mnem?).map do |op|
              op.name.gsub('/m', 'm').downcase
            end.join('_')

            name = mnem.downcase.tr('/', '_')
            name << "_#{ops_str}" unless ops_str.empty?
            name
          end

          private

          def load_features(row)
            self.features = row[COL_FEATURES].strip
                              .tr('/', '_')
                              .split('+')
                              .delete_if(&:empty?)
                              .map { |f| "#{f.downcase}".to_sym }
                              .uniq
          end

          def load_exceptions(row)
            exceptions = row[COL_EXCEPTIONS]

            self.exceptions =
              if exceptions.nil?
                []
              else
                exceptions.strip
                  .split('; ')
                  .map { |f| "#{f.downcase}".to_sym }
              end
          end

          def load_prefs(row)
            self.prefs =
              row[COL_PREFS].split('; ').map do |op|
                op =~ %r{(.+?):(.+?)/(.+)} or fail("invalid prefix op '#{op}'")
                value =
                  begin
                    Integer($3)
                  rescue
                    $3.to_sym
                  end

                [$1.to_sym, [$2.to_sym, value]]
              end.to_h
          end

          def load_operands(row)
            ops = row[COL_OPS].split('; ').map do |op|
              op =~ /(.*?):([a-z]+(?:\[\d+\.\.\d+\])?)/ || raise
              [$1, $2]
            end

            self.operands = Operand.load ops
          end

          def load_flags
            flags = []
            operands.each do |op|
              flags << op.reg_type
              flags << :sp if op.reg == :SP
              flags << :mem if op.type == :mem
            end
            flags.uniq!
            flags.compact!

            self.flags = flags
          end

          def accessable(type, reg_types = [])
            operands.each_with_object({}) do |op, hash|
              params_or_regs = Array(op.send(type))

              next unless (op.type == :reg || op.type == :rm) &&
                !params_or_regs.empty?

              next unless reg_types.include? op.reg_type

              params_or_regs.each do |param_or_reg|
                hash[param_or_reg] = op.access
              end
            end
          end

          def xmm_regs(zmm: false)
            regs = X64::REGISTERS.fetch(:xmm).dup
            regs.concat X64::REGISTERS.fetch(:zmm) if zmm

            regs
          end

          def vex?
            opcode[0] =~ /^VEX/
          end

          def write_byte_str(byte_str)
            write Integer(byte_str, 16), 8
          end

          def mand_pref_byte?(byte)
            MAND_PREF_BYTES.include? byte
          end

          def encode_mand_pref(opcode_index, &block)
            while mand_pref_byte? opcode[opcode_index]
              write_byte_str opcode[opcode_index]
              opcode_index += 1
            end

            block[opcode_index]
          end

          def encode_legacy_prefs(&block)
            writes = []

            LEGACY_PREFIX_BYTES.each do |prefix, byte|
              next unless prefs.key? prefix
              needed, = prefs.fetch prefix

              condition =
                case needed
                when :required
                  true
                when :optional
                  :"#{prefix}?"
                when :operand
                  LEGACY_PREFIX_CONDITIONS.fetch prefix
                else
                  raise
                end

              writes << [condition, [byte, 8]]
            end

            unordered_writes(:legacy_prefix_order, writes) if writes.any?

            block[]
          end

          def encode_opcode(opcode_index, &block)
            while opcode[opcode_index] =~ HEX_BYTE_REGEXP
              write_byte_str opcode[opcode_index]
              opcode_index += 1
            end

            if encoding.include? 'O'
              encode_o_opcode opcode_index, &block
            else
              block[opcode_index]
            end
          end

          def encode_o_opcode(opcode_index, &block)
            opcode[opcode_index] =~ /^([[:xdigit:]]{2})\+r(?:b|w|d|q)$/ || raise
            opcode_index += 1

            byte = Integer($1, 16)
            reg_op, = reg_operands
            reg_op.param == :reg0 or fail "expected reg_op to have param reg0 not #{reg_op.param}"

            set_reg_bits(:_reg_code, :reg0, reg_op.size == 8) do
              write [:add, byte, [:mod, :_reg_code, 8]], 8
              access :reg0, reg_op.access
              block[opcode_index]
            end
          end

          def encodes_modrm?
            encoding.include? 'M'
          end

          def encode_modrm_sib(opcode_index, &block)
            return block[opcode_index] unless encodes_modrm?

            # modrm_reg_bits is the bitstring
            # that is used directly to set the ModRM.reg bits
            # and can be an opcode extension
            # reg_reg is a *register*.
            # if given instead, it is properly handled and encoded
            reg_op, rm_op, = reg_operands

            byte = opcode[opcode_index]
            opcode_index += 1
            byte =~ %r{/(r|\d|\?)} or raise "unexpected opcode byte #{byte} in #{mnem}"

            reg_param, rm_reg_param, modrm_reg_bits =
              case $1
              when 'r'
                [reg_op.param, rm_op.param, nil]
              when /^(\d)$/
                [nil, rm_op.param, Integer($1)]
              when '?'
                [nil, rm_op.param, nil]
              else
                fail "unexpected modrm reg specifier '#{$1}'"
              end

            rm_reg_access = rm_op&.access
            reg_access = reg_op&.access

            rm_type = rm_op.type
            byte_regs = reg_op&.size == 8 || rm_op&.size == 8

            modrm_sib = ModRMSIB.cached unit,
                                        reg_param: reg_param,
                                        rm_reg_param: rm_reg_param,
                                        rm_type: rm_type,
                                        modrm_reg_bits: modrm_reg_bits,
                                        rm_reg_access: rm_reg_access,
                                        reg_access: reg_access,
                                        byte_regs: byte_regs

            call modrm_sib
            block[opcode_index]
          end

          def rex_possible?
            prefs.key? :rex_w
          end

          def encode_rex_or_vex(opcode_index, &block)
            if vex?
              encode_vex(opcode_index, &block)
            elsif rex_possible?
              encode_rex(opcode_index, &block)
            else
              block[opcode_index]
            end
          end

          def encode_vex(opcode_index, &block)
            vex = opcode[opcode_index].split '.'
            opcode_index += 1

            raise "invalid VEX start '#{vex.first}'" unless vex.first == 'VEX'

            vex_m =
              if vex.include? '0F38'
                0b10
              elsif vex.include? '0F3A'
                0b11
              else
                0b01
              end

            vex_p =
              if vex.include? '66'
                0b01
              elsif vex.include? 'F3'
                0b10
              elsif vex.include? 'F2'
                0b11
              else
                0b00
              end

            # vex_type = vex.&(%w(NDS NDD DDS)).first

            rex_w =
              if vex.include? 'W1'
                0b01
              elsif vex.include? 'W0'
                0b00
              end

            reg_op, rm_op, vex_op = reg_operands

            access(vex_op.param, vex_op.access) if vex_op

            vex_v =
              case encoding
              when 'RVM', 'RVMI', 'RVMR', 'MVR', 'RMV', 'RMVI', 'VM', 'VMI'
                [:reg_code, vex_op.param]
              when 'RM', 'RMI', 'XM', 'MR', 'MRI', 'M'
                0b0000
              when 'NP'
                nil
              else
                raise "unknown VEX encoding #{encoding} in #{mnem}"
              end

            vex_l =
              if vex.include? 'LIG'
                nil
              elsif vex.include? '128'
                0b0
              elsif vex.include? '256'
                0b1
              elsif vex.include? 'LZ'
                0b0
                # [:if, [:eq, [:operand_size], 128], 0b0, 0b1]
              end

            vex = VEX.cached unit,
                             rex_w: rex_w,
                             reg_param: reg_op&.param,
                             rm_reg_param: rm_op&.param,
                             rm_reg_type: rm_op&.type,
                             vex_m: vex_m,
                             vex_v: vex_v,
                             vex_l: vex_l,
                             vex_p: vex_p,
                             encodes_modrm: encodes_modrm?

            call vex
            block[opcode_index]
          end

          def encoded_operands
            @encoded_operands ||= operands.select(&:encoded?)
          end

          def reg_operands
            return @regs if @regs

            r_idx = encoding.index(/R|O/)
            reg_reg = r_idx && encoded_operands[r_idx]

            m_idx = encoding.index 'M'
            reg_rm = m_idx && encoded_operands[m_idx]

            v_idx = encoding.index 'V'
            reg_vex = v_idx && encoded_operands[v_idx]

            @regs = [reg_reg, reg_rm, reg_vex]
          end

          def encode_rex(opcode_index, &block)
            rex_w_required, rex_w_value = prefs[:rex_w]

            case rex_w_required
              # 64-bit operand size
            when :required
              force_rex = true
              rex_w = rex_w_value
              # non 64-bit operand size
              # only to access extended regs
            when :optional
              force_rex = false

              rex_w = case rex_w_value
                      when :any then
                        nil
                      when 0x0 then
                        0x0
                      else
                        fail "unexpected REX pref value #{rex_w_value}"
                      end
            else
              force_rex = false
              rex_w = nil
            end

            reg_op, rm_op, _ = reg_operands
            byte_regs = reg_op&.size == 8 || rm_op&.size == 8

            rex = REX.cached unit,
                             force: force_rex,
                             rex_w: rex_w,
                             reg_param: reg_op&.param,
                             rm_reg_param: rm_op&.param,
                             rm_reg_type: rm_op&.type,
                             encodes_modrm: encodes_modrm?,
                             byte_regs: byte_regs

            call rex
            block[opcode_index]
          end

          def imm_param_name(index)
            case encoding
            when 'FD', 'TD'
              :moffs
            when 'D'
              :rel
            else
              :"imm#{index}"
            end
          end

          def encode_imm_or_imm_reg(opcode_index, &block)
            imm_counter = 0

            loop do
              byte = opcode[opcode_index]
              opcode_index += 1

              break if byte.nil?

              case byte
              when /^(?:i|c)(?:b|w|d|o|q)$/
                write imm_param_name(imm_counter), imm_code_size(byte)
                imm_counter += 1
              when '/is4'
                write [:shl, [:reg_code, :reg3], 4], 8
              else
                fail "invalid immediate specifier '#{byte}'"\
                  " found in immediate encoding #{mnem}" if encoding =~ /I$/
              end
            end

            block[opcode_index] if block
          end

          def access_implicit_ops
            operands.each do |op|
              if op.implicit? && op.type == :reg
                access op.reg, op.access
              end
            end
          end

          static_state def root_state
            comment mnem
            log :debug, name

            access_implicit_ops

            encode_legacy_prefs do
              encode_mand_pref(0) do |opcode_index|
                encode_rex_or_vex(opcode_index) do |opcode_index|
                  encode_opcode(opcode_index) do |opcode_index|
                    encode_modrm_sib(opcode_index) do |opcode_index|
                      encode_imm_or_imm_reg(opcode_index) do |opcode_index|
                        done
                      end
                    end
                  end
                end
              end
            end
          end

          def imm_code_size(code)
            case code
            when 'ib', 'cb' then
              8
            when 'iw', 'cw' then
              16
            when 'id', 'cd' then
              32
            when 'io', 'cq' then
              64
            else
              raise "invalid imm code #{code}"
            end
          end

          def done
            return!
          end
        end
      end
    end
  end
end
