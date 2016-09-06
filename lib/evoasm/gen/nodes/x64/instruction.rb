require 'evoasm/gen/state_dsl'
require 'evoasm/gen/nodes/instruction'
require 'evoasm/gen/nodes/x64/encoding'
require 'evoasm/gen/core_ext/array'
require 'evoasm/gen/core_ext/integer'
require 'evoasm/gen/x64'
require 'evoasm/gen/nodes/x64/instruction_state_machine'
require 'evoasm/gen/nodes/x64/operand'

module Evoasm
  module Gen
    module Nodes
      module X64
        class Instruction < Nodes::Instruction

          node_attrs :mnemonic, :opcode,
                     :operands,
                     :encoding, :features,
                     :prefixes, :name, :index,
                     :flags, :exceptions, :state_machine,
                     :basic_state_machine

          COL_OPCODE = 0
          COL_MNEM = 1
          COL_OP_ENC = 2
          COL_OPS = 3
          COL_PREFS = 4
          COL_FEATURES = 5
          COL_EXCEPTIONS = 6

          OPERAND_TYPES = %i(reg rm vsib mem imm).freeze
          BASIC_OPERAND_TYPES = %i(reg rm imm)

          public_class_method :new

          def initialize(unit, index, row)
            super(unit)

            @index = index
            @mnemonic = row[COL_MNEM]
            @encoding = row[COL_OP_ENC]
            @opcode = row[COL_OPCODE].split(/\s+/)

            load_features row
            load_exceptions row
            load_operands row
            load_prefixes row

            load_flags

            @name = build_name

            @state_machine = InstructionStateMachine.new unit, false
            @state_machine.parent = self

            if basic?
              @basic_state_machine = InstructionStateMachine.new unit, true
              @basic_state_machine.parent = self
            end
          end

          def basic?
            return @basic unless @basic.nil?
            basic_types = operands.all? do |operand|
              BASIC_OPERAND_TYPES.include? operand.type
            end

            n_imm = operands.count do |operand|
              operand.type == :imm
            end

            imm64 = operands.any? do |operand|
              operand.type == :imm && operand.imm_size == 64
            end

            @basic = basic_types && n_imm <= 1 && !imm64
          end

          # NOTE: enum domains need to be sorted
          # (i.e. by their corresponding C enum numeric value)
          GP_REGISTERS = Gen::X64::REGISTERS.fetch(:gp)[0..-5] - [:SP]
          XMM_REGISTERS = Gen::X64::REGISTERS.fetch :xmm

          def parameter_domain(parameter_name)
            case parameter_name
            when :rex_b, :rex_r, :rex_x, :rex_w,
              :vex_l, :force_rex?, :lock?, :force_sib?,
              :force_disp32?, :force_long_vex?, :reg0_high_byte?,
              :reg1_high_byte?

              range_domain 0, 1
            when :addr_size
              range_domain 32, 64
            when :disp_size
              array_domain [16, 32]
            when :scale
              array_domain [1, 2, 4, 8]
            when :modrm_reg
              range_domain 0, 7
            when :vex_v
              range_domain 0, 15
            when :reg_base
              gp_registers_domain
            when :reg_index
              case register_operands[1].type
              when :vsib
                xmm_registers_domain
              when :mem, :rm
                gp_registers_domain
              else
                raise
              end
            when :imm0, :imm1, :imm, :moffs, :rel
              imm_op = encoded_operands.find { |operand| operand.parameter_name == parameter_name }
              case imm_op.size
              when 8
                type_domain :int8
              when 16
                type_domain :int16
              when 32
                type_domain :int32
              when 64
                type_domain :int64
              else
                raise "unexpected imm size '#{imm_op.size}'"
              end
            when :disp
              type_domain :int32
            when :reg0, :reg1, :reg2, :reg3
              reg_op = encoded_operands.find { |operand| operand.parameter_name == parameter_name }

              case reg_op.register_type
              when :xmm
                xmm_registers_domain
              when :zmm
                xmm_registers_domain zmm: true
              when :gp
                gp_registers_domain
              else
                values = register_constants Gen::X64::REGISTERS.fetch(reg_op.register_type)
                unit.node EnumerationDomain, values
              end
            else
              raise "missing domain for parameter '#{parameter_name}'"
            end
          end

          def build_name(index = nil)
            ops_str = operands.select(&:mnemonic?).map do |op|
              op.name.gsub('/m', 'm').downcase
            end.join('_')

            name = @mnemonic.split('/').first.downcase
            name << index.to_s if index
            name << "_#{ops_str}" unless ops_str.empty?
            name
          end

          def resolve_name_conflict!(index)
            @name = build_name(index)
          end

          def encodes_vex?
            @encodes_vex ||= opcode[0] =~ /^VEX/
          end

          def exceptions_bitmap
            unit.exceptions.bitmap do |flag, _|
              exceptions.include?(flag)
            end
          end

          def features_bitmap
            unit.features.bitmap do |flag, _|
              features.include?(flag)
            end
          end

          def rex_possible?
            return false if encodes_vex?
            # FIXME: is there a better way ?
            prefixes.key?(:rex_w) || encoding =~ /M|O|R|NP/
          end

          def encodes_modrm?
            encoding.include? 'M'
          end

          def encoded_operands
            @encoded_operands ||= operands.select(&:encoded?)
          end

          def register_operands
            return @regs if @regs

            r_idx = encoding.index(/R|O/)
            reg_reg = r_idx && encoded_operands[r_idx]

            m_idx = encoding.index 'M'
            reg_rm = m_idx && encoded_operands[m_idx]

            v_idx = encoding.index 'V'
            reg_vex = v_idx && encoded_operands[v_idx]

            @regs = [reg_reg, reg_rm, reg_vex]
          end

          private

          def xmm_regs(zmm: false)
            regs = Gen::X64::REGISTERS.fetch(:xmm).dup
            regs.concat Gen::X64::REGISTERS.fetch(:zmm) if zmm

            regs
          end

          def type_domain(type)
            unit.node TypeDomain, type
          end

          def range_domain(min, max)
            unit.node RangeDomain,
                      min,
                      max
          end

          def array_domain(values)
            values = values.map { |value| IntegerLiteral.new unit, value }
            unit.node EnumerationDomain, values
          end

          def gp_registers_domain
            unit.node EnumerationDomain, register_constants(GP_REGISTERS)
          end

          def xmm_registers_domain(zmm: false)
            unit.node EnumerationDomain, register_constants(xmm_regs(zmm: zmm))
          end

          def register_constants(register_names)
            register_names.map do |register_name|
              RegisterConstant.new unit, register_name
            end
          end

          def integer_literal(value)
            IntegerLiteral.new unit, value
          end

          def integer_literals(values)
            values.map { |value| integer_literal value }
          end

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

          def load_prefixes(row)
            self.prefixes =
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

            @operands = Operand.load unit, self, ops
          end

          def load_flags
            flags = []
            operands.each do |op|
              flags << op.register_type
              flags << :sp if op.register == :SP
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

              next unless reg_types.include? op.register_type

              params_or_regs.each do |param_or_reg|
                hash[param_or_reg] = op.access
              end
            end
          end
        end
      end
    end
  end
end
