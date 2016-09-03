require 'stringio'

class StringIO
  attr_writer :indent

  def indent(absolute: nil, relative: nil)
    @indent ||= 0

    prev_indent = @indent
    @indent =
      if relative
        @indent + relative.to_i
      else
        absolute || @indent + 1
      end
    yield
    @indent = prev_indent
  end

  def block(head = '', absolute_indent: nil, begin_delimiter: '{', end_delimiter: '}', &block)
    puts "#{head} #{begin_delimiter}"
    indent absolute: absolute_indent, &block
    puts end_delimiter
  end

  def indent_str
    '  ' * @indent
  end

  def puts(line = nil, eol: '')
    if line
      write indent_str if @indent
      super("#{line}#{eol}")
    else
      super()
    end
  end
end
