require_relative './parser.rb'

module RubyLox
  class Enviroment
    attr_accessor :enclosing, :env

    def initialize enclosing = nil
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

    def ancestor distance
      env_ = self
      distance.times do
        env_ = env_.enclosing
      end
      env_
    end

    def get_at(distance, name)
      ancestor(distance).env[name]
    end

    def assign_at distance, name, value
      ancestor(distance).env[name] = value
    end
  end

  class Resolver
    attr_accessor :interpreter

    def initialize interpreter
      @interpreter = interpreter
      @scopes = []
      @cur_function = nil
      @cur_klass = nil
    end

    def err tkn, msg
      @interpreter.cli.err tkn, msg
    end

    def resolve_statements stmts
      stmts.each do
        resolve _1
      end
    end

    def resolve ast
      case ast
      when This
        err ast.keyword, "can't use 'this' outside of a class" if !@cur_klass

        resolve_local ast, ast.keyword

      when Get
        resolve ast.object

      when Block
        begin_scope
        ast.stmts.each do resolve _1 end
        end_scope

      when Stmt
        case ast.type
        when :var
          name, expr = ast.expr
          declare name
          resolve expr
          define name

        when :expr, :print
          resolve ast.expr
        end

      when FuncStmt
        declare ast.name
        define ast.name

        resolve_function ast, :function

      when Set
        resolve ast.value
        resolve ast.object

      when AnonymFunc
        resolve_function ast, :function

      when Assignment
        resolve ast.expr
        resolve_local ast, ast.name

      when Variable
        if !@scopes.empty? && @scopes.last[ast.name.literal] == false
          err expr.name, "can't read local variable in its own initializer"
        end

        resolve_local ast, ast.name

      when Grouping
        resolve ast.val

      when Binary
        resolve ast.left
        resolve ast.right

      when If
        resolve ast.condition
        resolve ast.then
        resolve ast.else

      when Literal
        return

      when Return
        if @cur_function.nil?
          err ast.keyword, "can't return from top-level code"
        end

        if @cur_function == :init && ast.expr
          err ast.keyword, "can't return from an initializer"
        end

        resolve ast.expr

      when While
        resolve ast.cond
        resolve ast.body

      when For
        resolve ast.init
        resolve ast.cond
        resolve ast.inc
        resolve ast.body

      when Call
        resolve ast.callee

        ast.args.each do |arg|
          resolve arg
        end

      when And
        resolve ast.left
        resolve ast.right

      when Or
        resolve ast.left
        resolve ast.right

      when Unary
        resolve ast.val

      when Klass
        enclosing = @cur_klass
        @cur_klass = :class

        declare ast.name
        define ast.name

        begin_scope
        @scopes.last["this"] = true

        ast.lox_methods.each do |met|
          resolve_function met, met.name.literal == "init" ? :init : :method
        end

        end_scope
        @cur_klass = enclosing
      else
      end
      return
    end

    def begin_scope
      @scopes << {}
    end

    def end_scope
      @scopes.pop
      return
    end

    def declare name
      return if @scopes.empty?

      scope = @scopes.last
      if scope.include? name.literal
        err name, "already a variable with this name in this scope"
      end

      scope[name.literal] = false
    end

    def define name
      return if @scopes.empty?

      @scopes.last[name.literal] = true
    end

    def resolve_local expr, name
      @scopes.reverse_each.with_index do |x, i|
        if x.include? name.literal
          @interpreter.resolve expr, i
          break
        end
      end
    end

    def resolve_function ast, type
      enclosing_func = @cur_function
      @cur_function = type
      begin_scope

      ast.params.each do |tkn|
        declare tkn
        define tkn
      end
      resolve_statements ast.body

      end_scope
      @cur_function = enclosing_func
    end
  end
end
