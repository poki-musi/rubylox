require_relative './parser.rb'
require_relative './scope.rb'

module RubyLox
  class InterpreterError < RuntimeError; end

  class ReturnValue < RuntimeError
    attr_accessor :val

    def initialize val
      super
      @val = val
    end
  end

  module Function
  end

  class NatFunction < Proc
    include Function

    def to_s = "<native fn>"
  end

  class ObjFunction
    include Function

    def initialize decl, closure = nil
      @decl = decl
      @closure = closure
    end

    def arity = @decl.params.size

    def call intr, args
      env = Enviroment.new @closure || intr.globals
      @decl.params.zip(args) do |param, arg|
        env.make_var param, arg
      end

      begin
        intr.eval_block @decl.body, env
        return nil
      rescue ReturnValue => e
        return e.val
      end
    end

    def to_s
      "<fn #{@decl.name.literal}>"
    end
  end

  class Interpreter
    attr_reader :cli
    attr_accessor :env, :globals

    def initialize cli
      @cli = cli
      @globals = cli.globals
      @env = @globals
    end

    def err tkn, msg
      cli.runtime_err tkn.line, msg
      raise InterpreterError
    end

    def push
      @env = @env.push
    end

    def pop
      @env = @env.pop
    end

    #
    # interpret
    #

    def interpret ast
      return :err if ast.nil?

      begin
        ast[...-1].each do |stmts|
          evaluate stmts
        end
        return evaluate ast.last
      rescue InterpreterError
        return :err
      end
    end

    def eval_block stmts, env
      prev = @env
      begin
        @env = env
        stmts.each do |stmts|
          evaluate stmts
        end
      ensure
        @env = prev
      end
    end

    def evaluate ast
      case ast
      when Literal
        return ast.val

      when Variable
        return @env[ast.name]

      when Grouping
        return evaluate ast.val

      when Unary
        val = evaluate ast.val

        case ast.op.type
        when :-
          err ast.op, "operand must be a number" if !val.is_a?(Float)

          return -val
        when :! then return !val
        end

      when Binary
        left = evaluate ast.left
        right = evaluate ast.right

        case ast.op.type
        when :!=
          return !is_eql?(left, right)
        when :==
          return is_eql?(left, right)
        when :-, :/
          err ast.op, "operands must be numbers" if !left.is_a?(Float) || !right.is_a?(Float)

          return left.method(ast.op.type).call(right)
        else
          err ast.op, "operands must be of the same type (String or Float)" if !left.class.eql?(right.class)
          err ast.op, "operands must be Strings or Integers" if !(left.is_a?(String) || left.is_a?(Float))

          return left.method(ast.op.type).call(right)
        end

      when Assignment
        value = evaluate ast.expr
        @env[ast.name] = value
        return value

      when Stmt
        type = ast.type

        case type
        when :print then puts evaluate ast.expr
        when :expr then evaluate ast.expr
        when :var
          name, expr = ast.expr
          @env.make_var name, (expr.nil? ? nil : evaluate(expr))
        end

      when Block
        eval_block ast.stmts, @env
        return

      when If
        evaluate(evaluate(ast.cond) ? ast.then : ast.else)
        return

      when And
        left = evaluate ast.left
        return left && evaluate(ast.right)

      when Or
        left = evaluate ast.left
        return left || evaluate(ast.right)

      when While
        while evaluate ast.cond
          evaluate ast.body
        end
        return

      when Call
        callee = evaluate ast.callee
        args = ast.args.map { evaluate _1 }

        if !callee.class.include? Function
          err ast.paren, "can only call functions and classes"
        end

        if args.size != callee.arity
          err ast.paren, "expected #{callee.arity} arguments but got #{args.size} instead"
        end

        return callee.call self, args

      when FuncStmt
        if @globals.eql? @env
          func = ObjFunction.new ast
        else
          func = ObjFunction.new ast, @env
        end
        @env.make_var ast.name, func
        return

      when AnonymFunc
        if @globals.eql? @env
          return ObjFunction.new ast
        else
          return ObjFunction.new ast, @env
        end

      when Return
        raise ReturnValue.new(evaluate ast.expr)
      end
    end

    def is_eql?(a, b) = !a && !b || a && b && a == b
  end
end
