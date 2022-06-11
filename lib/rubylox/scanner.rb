module RubyLox
  Token = Struct.new(:type, :literal, :line)

  # @param text [String]
  def self.count_newlines text
    text.count("\n")
  end

  KEYWORDS = [
    'and', 'class', 'else', 'false', 'for', 'fn', 'if', 'nil',
    'or', 'print', 'return', 'super', 'this', 'true', 'var', 'while',
  ].map { [_1, _1.to_sym] }.to_h

  # @param text [String]
  def self.scan_tokens cli, text, line = 1
    Enumerator.new do |g|
      while !text.empty?
        case
        when text.slice!(/\A\/\//)
          text.slice!(/\A[^\n\r]*/)

        when text.slice!(/\A\/\*/)
          layers = 1
          n_line = line
          while layers > 0
            if text.slice!(/\A[\s\S]*\/\*/)
              layers += 1
              n_line += count_newlines $~[0]
            elsif text.slice!(/\A[\s\S]*\*\//)
              layers -= 1
              n_line += count_newlines $~[0]
            else
              break
            end
          end

          cli.err line, "unmatched comments" if layers != 0
          line = n_line

        when m = text.slice!(/\A([!=<>]=|[-\(\)\{\},\.\+;\*!=<>])/)
          g.yield Token.new(m.to_sym, nil, line)

        when m = text.slice!(/\A("([^"]|\\")*")/)
          g.yield Token.new(:string, m[1...-1], line)
          line += m.count("\n")

        when m = text.slice!(/\A\d+(\.\d+)?/)
          g.yield Token.new(:number, m.to_f, line)

        when str = text.slice!(/\A([_a-zA-Z][a-zA-Z0-9_]*)/)
          tkn = RubyLox::KEYWORDS[str] || :id
          str = nil if tkn != :id
          g.yield Token.new(tkn, str, line)

        when m = text.slice!(/\A[\n\r\s]+/)
          line += count_newlines m

        else
          r = text.slice!(0)
          cli.err line, "unknown character '#{r}'"
        end
      end
      g.yield Token.new(:EOF, nil, line)
    end.to_a
  end
end
