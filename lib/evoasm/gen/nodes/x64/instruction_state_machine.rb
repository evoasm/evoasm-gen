require 'evoasm/gen/nodes/instruction_state_machine'

module Evoasm
  module Gen
    module Nodes
      module X64
        class InstructionStateMachine < Nodes::InstructionStateMachine

          node_attrs :direct_only?

          params :imm0, :lock?, :legacy_prefix_order, :rel,
                 :imm1, :moffs, :addr_size, :reg0, :reg1, :reg2, :reg3,
                 :reg0_high_byte?

          local_vars :reg_code

          include StateDSL
          include EncodeUtil # for set_reg_code

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

          MANDATORY_PREF_BYTES = %w(66 F2 F3 F0).freeze

          def instruction
            parent
          end

          def write_byte_str(byte_str)
            write Integer(byte_str, 16), 8
          end

          def mandatory_prefix_byte?(byte)
            MANDATORY_PREF_BYTES.include? byte
          end

          def encode_mandatory_prefix(opcode_index, &block)
            opcode = instruction.opcode

            while mandatory_prefix_byte? opcode[opcode_index]
              write_byte_str opcode[opcode_index]
              opcode_index += 1
            end

            block[opcode_index]
          end

          def encode_legacy_prefixes(&block)
            writes = []
            prefixes = instruction.prefixes

            LEGACY_PREFIX_BYTES.each do |prefix, byte|
              next unless prefixes.key? prefix
              needed, = prefixes.fetch prefix

              condition =
                case needed
                when :required
                  [true]
                when :optional
                  [:"#{prefix}?"]
                when :operand
                  LEGACY_PREFIX_CONDITIONS.fetch prefix
                else
                  raise
                end

              writes << [condition, [byte, 8]]
            end

            if writes.size > 1
              unordered_writes(:legacy_prefix_order, writes)
              block[]
            elsif writes.empty?
              block[]
            else
              condition, write = writes.first
              to_if(*condition) do
                write(*write)
                block[]
              end
              else_to &block
            end
          end

          def encode_opcode(opcode_index, &block)
            opcode = instruction.opcode

            while opcode[opcode_index] =~ HEX_BYTE_REGEXP
              write_byte_str opcode[opcode_index]
              opcode_index += 1
            end

            if instruction.encoding.include? 'O'
              encode_o_opcode opcode_index, &block
            else
              block[opcode_index]
            end
          end

          def encode_o_opcode(opcode_index, &block)
            instruction.opcode[opcode_index] =~ /^([[:xdigit:]]{2})\+r(?:b|w|d|q)$/ || raise
            opcode_index += 1

            byte = Integer($1, 16)
            reg_op, = instruction.register_operands
            reg_op.parameter_name == :reg0 or raise "expected reg_op to have param reg0 not #{reg_op.parameter_name}"

            set_reg_bits(:_reg_code, :reg0, reg_op.size == 8) do
              write [:add, byte, [:mod, :_reg_code, 8]], 8
              access :reg0, reg_op.access
              block[opcode_index]
            end
          end

          def encode_modrm_sib(opcode_index, &block)
            return block[opcode_index] unless instruction.encodes_modrm?

            # modrm_reg_bits is the bitstring
            # that is used directly to set the ModRM.reg bits
            # and can be an opcode extension.
            # reg is a *register*;
            # if given instead, it is properly handled and encoded
            reg_op, rm_op, = instruction.register_operands

            byte = instruction.opcode[opcode_index]
            opcode_index += 1
            byte =~ %r{/(r|\d|\?)} or raise "unexpected opcode byte #{byte} in #{instruction.mnemonic}"

            reg_param, rm_reg_param, modrm_reg_bits =
              case $1
              when 'r'
                [reg_op.parameter_name, rm_op.parameter_name, nil]
              when /^(\d)$/
                [nil, rm_op.parameter_name, Integer($1)]
              when '?'
                [nil, rm_op.parameter_name, nil]
              else
                raise "unexpected modrm reg specifier '#{$1}'"
              end

            rm_reg_access = rm_op&.access
            reg_access = reg_op&.access

            rm_type = rm_op.type
            byte_regs = reg_op&.size == 8 || rm_op&.size == 8

            modrm_sib = unit.node ModRMSIB,
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

          def encode_rex_or_vex(opcode_index, &block)
            if instruction.encodes_vex?
              encode_vex(opcode_index, &block)
            elsif instruction.rex_possible?
              encode_rex(opcode_index, &block)
            else
              block[opcode_index]
            end
          end

          def encode_vex(opcode_index, &block)
            vex = instruction.opcode[opcode_index].split '.'
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

            reg_op, rm_op, vex_op = instruction.register_operands

            access(vex_op.parameter_name, vex_op.access) if vex_op

            vex_v =
              case instruction.encoding
              when 'RVM', 'RVMI', 'RVMR', 'MVR', 'RMV', 'RMVI', 'VM', 'VMI'
                [:reg_code, vex_op.parameter_name]
              when 'RM', 'RMI', 'XM', 'MR', 'MRI', 'M'
                0b0000
              when 'NP'
                nil
              else
                raise "unknown VEX encoding #{encoding} in #{mnemonic}"
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

            vex = unit.node VEX,
                            rex_w: rex_w,
                            reg_param: reg_op&.parameter_name,
                            rm_reg_param: rm_op&.parameter_name,
                            rm_reg_type: rm_op&.type,
                            vex_m: vex_m,
                            vex_v: vex_v,
                            vex_l: vex_l,
                            vex_p: vex_p,
                            encodes_modrm: instruction.encodes_modrm?

            call vex
            block[opcode_index]
          end

          def encode_rex(opcode_index, &block)
            rex_w_required, rex_w_value = instruction.prefixes[:rex_w]

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

            reg_op, rm_op, _ = instruction.register_operands
            byte_regs = reg_op&.size == 8 || rm_op&.size == 8

            rex = unit.node REX,
                            force: force_rex,
                            rex_w: rex_w,
                            reg_param: reg_op&.parameter_name,
                            rm_reg_param: rm_op&.parameter_name,
                            rm_reg_type: rm_op&.type,
                            encodes_modrm: instruction.encodes_modrm?,
                            byte_regs: byte_regs

            call rex
            block[opcode_index]
          end

          def imm_parameter_name(index)
            case instruction.encoding
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
            opcode = instruction.opcode

            loop do
              byte = opcode[opcode_index]
              opcode_index += 1

              break if byte.nil?

              case byte
              when /^(?:i|c)(?:b|w|d|o|q)$/
                write imm_parameter_name(imm_counter), imm_code_size(byte)
                imm_counter += 1
              when '/is4'
                write [:shl, [:reg_code, :reg3], 4], 8
              else
                raise "invalid immediate specifier '#{byte}'"\
                      " found in immediate encoding #{mnemonic}" if encoding =~ /I$/
              end
            end

            block[opcode_index] if block
          end

          def access_implicit_operands
            instruction.operands.each do |operand|
              if operand.implicit? && operand.type == :register
                access operand.register, operand.access
              end
            end
          end

          static_state def root_state
            comment instruction.mnemonic
            log :debug, instruction.name

            access_implicit_operands

            encode_legacy_prefixes do
              encode_mandatory_prefix(0) do |opcode_index|
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