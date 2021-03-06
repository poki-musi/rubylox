require_relative './parser.rb'
require_relative './scope.rb'
require_relative './objects.rb'

module RubyLox
  class Interpreter
    attr_reader :cli
    attr_accessor :env, :globals

    def initialize cli, globals
      @cli = cli
      @globals = globals.tap { |g| g.enclosing = self }
      @env = @globals
      @locals = nil
    end

    def err tkn, msg
      cli.runtime_err tkn, msg
      raise InterpreterError
    end

    def push
      @env = @env.push
    end

    def pop
      @env = @env.pop
    end

    def resolve expr, depth
      @locals[expr] = depth
    end

    #
    # interpret
    #

    def interpret ast
      return :err if ast.nil?

      @locals = {}
      begin
        Resolver.new(self).resolve_statements ast

        return :err if @cli.had_error

        ast[...-1].each do |stmts|
          evaluate stmts
        end
        evaluate ast.last
      rescue InterpreterError
        :err
      end
    end

    def eval_block stmts, env
      prev = @env
      begin
        @env = env
        stmts.each do |stmt|
          evaluate stmt
        end
      ensure
        @env = prev
      end
    end

    def lookup_variable name, expr
      dist = @locals[expr]
      if !dist.nil?
        return @env.get_at(dist, name.literal)
      else
        return @globals[name]
      end
    end

    def evaluate ast
      case ast
      when Literal
        return ast.val

      when Variable
        return lookup_variable ast.name, ast

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

        dist = @locals[ast]
        if !distance.nil?
          @env.assign_at dist, ast.name.literal, value
        else
          @globals[ast.name] = value
        end

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
        eval_block ast.stmts, push
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

      when Get
        obj = evaluate ast.object
        err ast.name, "only instances have properties" if !obj.is_a?(LoxInstance)
        res = obj[ast.name.literal]
        err ast.name, "undefined property '#{ast.name.literal}'" if res.nil?
        return res == :nil ? nil : res

      when Set
        obj = evaluate ast.object
        err ast.name, "only instances have properties" if !obj.is_a?(LoxInstance)
        value = evaluate ast.value
        obj[ast.name] = value
        return value

      when This
        return lookup_variable ast.keyword, ast

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

      when Klass
        @env.make_var ast.name, nil

        methods = ast.lox_methods.map do |met|
          [met.name.literal, ObjFunction.new(met, @env, met.name.literal == "init")]
        end.to_h
        klass = LoxKlass.new(ast.name.literal, methods)

        @env[ast.name] = klass
        return nil
      end
    end

    def is_eql?(a, b) = !a && !b || a && b && a == b
  end
end
