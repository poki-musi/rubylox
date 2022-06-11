require 'optparse'
require_relative 'interpreter.rb'
require_relative 'parser.rb'

module RubyLox
  class CLI
    attr_reader :had_error, :had_runtime_err, :globals

    def initialize &block
      @had_error = false
      @had_runtime_err = false
      @globals = Enviroment.new self
      instance_eval(&block)
    end

    def nat name, &block
      @globals.make_fn name, &block
    end

    def err line, msg
      STDERR.puts "[@#{line}] Error: #{msg}"
      @had_error = true
    end

    def runtime_err line, msg
      STDERR.puts "[@#{line}] Error: #{msg}"
      @had_runtime_err = true
    end

    def usage
      STDERR.puts "Usage: rblox [script]"
    end

    def help
      STDERR.puts
    end

    def main argv
      if argv.size > 1
        usage
      elsif argv.size == 1
        run_file argv.first
      else
        prompt
      end

      exit!(64) if @had_error
      exit!(70) if @had_runtime_err
    end

    def prompt
      intr = Interpreter.new self
      parser = Parser.new(self)
      loop do
        print ">> "
        line = gets
        break if line.empty?

        ast = parser.parse(line)
        if !@had_error
          pprint_res intr.interpret(ast)
        else
          @had_error = false
          @had_runtime_err = false
        end
      end
    end

    def run_file filename
      text = IO.read(filename)
      ast = Parser.new(self).parse(text)
      if !@had_error
        Interpreter.new(self).interpret(ast)
      end
    end

    def pprint_res res
      return if res == :err
      if res.nil?
        puts "=> nil"
      else
        puts "=> #{res}"
      end
    end
  end
end
