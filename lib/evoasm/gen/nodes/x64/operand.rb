module Evoasm
  module Gen
    module X64
      class Operand
        attr_reader :name, :param, :type, :size1, :size2, :access,
                    :reg, :imm, :reg_type, :accessed_bits, :reg_size,
                    :mem_size, :imm_size

        IMM_OP_REGEXP = /^(imm|rel)(\d+)?$/
        MEM_OP_REGEXP = /^m(\d*)$/
        MOFFS_OP_REGEXP = /^moffs(\d+)$/
        VSIB_OP_REGEXP = /^vm(\d+)(?:x|y)$/
        REG_OP_REGEXP = /^(?<reg>xmm|ymm|zmm|mm)$|^(?<reg>r)(?<reg_size>8|16|32|64)$/
        RM_OP_REGEXP = %r{^(?:(?<reg>xmm|ymm|zmm|mm)|(?<reg>r)(?<reg_size>8|16|32|64)?)/m(?<mem_size>\d+)$}

        RFLAGS = REGISTERS.fetch :rflags
        MXCSR = REGISTERS.fetch :mxcsr

        class Counters
          attr_accessor :imm_counter, :reg_counter

          def initialize
            @imm_counter = 0
            @reg_counter = 0
          end
        end

        def self.load(ops)
          operands = []
          counters = Counters.new

          ops.each do |op_name, flags|
            next if IGNORED_MXCSR.include? op_name.to_sym
            next if IGNORED_RFLAGS.include? op_name.to_sym

            if op_name == 'FLAGS' || op_name == 'RFLAGS'
              # NOTE: currently all used flags
              # fall within the bits of 32-bit FLAGS
              # i.e. all upper bits of RFLAGS are unused
              RFLAGS.each do |reg_name|
                next if IGNORED_RFLAGS.include? reg_name.to_sym
                operands << new(reg_name.to_s, flags, counters)
              end
            else
              operands << new(op_name, flags, counters)
            end
          end

          operands
        end

        def initialize(name, flags, counters)
          @name = name
          @access = flags.gsub(/[^crwu]/, '').each_char.map(&:to_sym)
          @accessed_bits = {}

          flags.scan(/([crwu])\[(\d+)\.\.(\d+)\]/) do |acc, from, to|
            accessed_bits[acc.to_sym] = (from.to_i..to.to_i)
          end

          @encoded = flags.include? 'e'

          # mnem operand
          @mnem = flags.include? 'm'

          if name == name.upcase
            initialize_implicit
          else
            initialize_explicit counters
          end
        end

        def encoded?
          @encoded
        end

        def implicit?
          @implicit
        end

        def mnem?
          @mnem
        end

        def size
          @reg_size || @imm_size || @mem_size
        end

        def size1
          @reg_size || @imm_size
        end

        def size2
          @imm_size
        end

        private

        def reg_size=(size)
          @size1 = size
        end

        def initialize_explicit(counters)
          case name
          when IMM_OP_REGEXP
            @type = :imm
            @imm_size = $2 && $2.to_i

            if $1 == 'imm'
              @param = :"imm#{counters.imm_counter}"
              counters.imm_counter += 1
            else
              @param = $1.to_sym
            end
          when RM_OP_REGEXP
            @type = :rm
            mem_size = Integer($~[:mem_size])
            reg_size =
              if $~[:reg_size].nil? || $~[:reg_size].empty?
                mem_size
              else
                Integer($~[:reg_size])
              end
            initialize_reg $~[:reg], reg_size, mem_size
          when REG_OP_REGEXP
            @type = :reg
            initialize_reg $~[:reg], $~[:reg_size].to_i
          when MEM_OP_REGEXP
            @type = :mem
            @mem_size = $1.empty? ? nil : $1.to_i
          when MOFFS_OP_REGEXP
            @type = :mem
            @mem_size = Integer($1)
            @param = :moffs
          when VSIB_OP_REGEXP
            @type = :vsib
            @mem_size = $1.to_i
          else
            raise "unexpected operand '#{name}'"
          end

          if type == :rm || type == :reg
            @param = :"reg#{counters.reg_counter}"
            counters.reg_counter += 1
          end
        end

        ALLOWED_REG_SIZES = [8, 16, 32, 64].freeze

        def initialize_reg(reg, reg_size, mem_size = nil)
          @reg_type, @reg_size, @mem_size =
            case reg
            when 'r'
              raise "invalid reg size #{reg_size}" unless ALLOWED_REG_SIZES.include?(reg_size)
              [:gp, reg_size, mem_size]
            when 'xmm'
              [:xmm, 128, mem_size]
            when 'ymm'
              [:xmm, 256, mem_size]
            when 'zmm'
              [:zmm, 512, mem_size]
            when 'mm'
              [:mm, 64, mem_size]
            else
              raise "unexpected reg type '#{reg}/#{reg_size}'"
            end
        end

        def initialize_implicit
          if name =~ /^(\d)$/
            @type = :imm
            @imm = $1
          else
            reg_name = name.gsub(/\[|\]/, '')
            @type = name =~ /^\[/ ? :mem : :reg

            #FIXME: find a way to handle
            # this: memory expressions involving
            # multiple registers e.g. [RBX + AL] in XLAT
            if reg_name =~ /\+/
              reg_name = reg_name.split(/\s*\+\s*/).first
            end

            sym_reg = reg_name.to_sym

            if RFLAGS.include?(sym_reg)
              @reg = sym_reg
              @reg_type = :rflags
              @reg_size = 1
            elsif MXCSR.include?(sym_reg)
              @reg = sym_reg
              @reg_type = :mxcsr
              @reg_size = 32
            else
              @reg_type = :gp
              @reg =
                case reg_name
                when 'RAX', 'EAX', 'AX', 'AL'
                  :A
                when 'RCX', 'ECX', 'CX', 'CL'
                  :C
                when 'RDX', 'EDX', 'DX'
                  :D
                when 'RBX', 'EBX'
                  :B
                when 'RSP', 'SP'
                  :SP
                when 'RBP', 'BP'
                  :BP
                when 'RSI', 'ESI', 'SI', 'SIL'
                  :SI
                when 'RDI', 'EDI', 'DI', 'DIL'
                  :DI
                when 'RIP'
                  @reg_type = :ip
                  :IP
                when 'XMM0'
                  @reg_type = :xmm
                  :XMM0
                else
                  raise ArgumentError, "unexpected register '#{reg_name}'"
                end

              @reg_size =
                case reg_name
                when 'RAX', 'RCX', 'RDX', 'RBX', 'RSP', 'RBP', 'RSI', 'RDI', 'RIP'
                  64
                when 'EAX', 'ECX', 'EDX', 'EBX', 'ESI', 'EDI'
                  32
                when 'AX', 'CX', 'DX', 'SP', 'BP', 'SI', 'DI'
                  16
                when 'AL', 'CL', 'SIL', 'DIL'
                  8
                when 'XMM0'
                  128
                else
                  raise ArgumentError, "unexpected register '#{reg_name}'"
                end
            end
          end

          @implicit = true
        end
      end
    end
  end
end
