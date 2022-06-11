require_relative './parser.rb'

module RubyLox
  class Resolver
    attr_reader :intr

    def initialize intr
      @intr = intr
      @scopes = []
    end

    def visit ast
      case ast
      when Block
        begin_scope()
        resolve(ast.stmts)
        end_scope()
        return nil

      when Stmt
        if ast.type == :var
          declare(ast.expr[0])

          if ast.expr[1]
            visit(ast.expr[1])
          end

          define(ast.expr[0])
        else
        end

      when Variable
        if !@scopes.empty? && @scopes.last[ast.name.literal] == false
          @intr.cli.err ast.name, "can't read local variable in its own initializer"
        end

        resolve_local(ast, ast.name)
        return

      when Assignment
        resolve(ast.expr)
        resolve_local(ast, ast.name)
        return

      when FuncStmt
        declare(ast.name)
        define(ast.name)

        resolve_function(ast)
        return

      when AnonymFunc
        resolve_function(ast)
        return
      end
    end

    def begin_scope
      @scopes << {}
    end

    def end_scope
      @scopes.pop
    end

    def resolve stmts
      stmts.each do |stmt|
        self.visit stmt
      end
    end

    def declare tkn
      return if @scopes.empty?
      @scopes.last[tkn.literal] = false
    end

    def define tkn
      return if @scopes.empty?
      @scopes.last[tkn.literal] = true
    end

    def resolve_local expr, tkn
      @scopes.reverse_each.each_with_index do |scope, i|
        if scope.include? tkn.literal
          @intr.resolve expr, @scopes.size - 1 - i
          break
        end
      end
    end

    def resolve_function(func)
      begin_scope()
      func.params.each do |param|
        declare(param)
        define(param)
      end
      resolve(func.body)
      end_scope()
    end
  end

  class Enviroment
    def initialize enclosing
      @env = {}
      @enclosing = enclosing
    end

    def [](k)
      res = @env[k.literal]
      return (res == :nil ? nil : res) if !res.nil?

      if @enclosing.is_a? Enviroment
        return @enclosing[k]
      else
        @enclosing.err k, "undefined variable '#{k.literal}'."
      end
    end

    def []=(k, v)
      res = @env[k.literal]
      if !res.nil?
        @env[k.literal] = v
      elsif @enclosing.is_a? Enviroment
        @enclosing[k] = v
      else
        @enclosing.err k, "undefined variable '#{k.literal}'"
      end
    end

    def make_var k, v
      @env[k.literal] = v.nil? ? :nil : v
    end

    def make_fn name, &func
      @env[name] = NatFunction.new(&func)
    end

    def push
      Enviroment.new self
    end

    def pop
      @enclosing
    end
  end
end
