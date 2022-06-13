require 'optparse'
require_relative 'interpreter.rb'
require_relative 'parser.rb'

module RubyLox
  class CLI
    attr_reader :had_error, :had_runtime_err, :globals

    def initialize &block
      @had_error = false
      @had_runtime_err = false
      @globals = {}
      instance_eval(&block)
    end

    def nat name, &block
      @globals[name] = block
    end

    def make_env
      Enviroment.new.tap do |env|
        @globals.each_pair do |name, func|
          env.make_fn name, &func
        end
      end
    end

    def report line, on, msg
      STDERR.puts "[@#{line} on '#{on}'] error: #{msg}"
    end

    def err tkn, msg
      report tkn.line, (tkn.literal || tkn.type.to_s), msg
      @had_error = true
    end

    def runtime_err tkn, msg
      report tkn.line, (tkn.literal || tkn.type.to_s), msg
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
      intr = Interpreter.new(self, make_env)
      parser = Parser.new(self)
      loop do
        print ">> "
        line = gets
        break if line.empty?

        ast = parser.parse(line)
        if !@had_error
          pprint_res intr.interpret(ast)
          @had_runtime_err = false
        else
          @had_error = false
        end
      end
    end

    def run_file filename
      text = IO.read(filename)
      intr = Interpreter.new(self, make_env)
      ast = Parser.new(self).parse(text)
      if !@had_error
        intr.interpret(ast)
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
