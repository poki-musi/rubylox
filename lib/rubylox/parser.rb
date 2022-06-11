require_relative './scanner.rb'

module RubyLox
  Binary = Struct.new(:left, :op, :right)
  Unary = Struct.new(:op, :val)
  Literal = Struct.new(:val)
  Grouping = Struct.new(:val)
  Stmt = Struct.new(:expr, :type)
  Variable = Struct.new(:name)
  Assignment = Struct.new(:name, :expr)
  Block = Struct.new(:stmts)
  If = Struct.new(:cond, :then, :else)
  And = Struct.new(:left, :right)
  Or = Struct.new(:left, :right)
  While = Struct.new(:cond, :body)
  For = Struct.new(:init, :cond, :inc, :body)
  Call = Struct.new(:callee, :paren, :args)
  FuncStmt = Struct.new(:name, :params, :body)
  Return = Struct.new(:expr)
  AnonymFunc = Struct.new(:name, :params, :body)

  class Parser
    attr_accessor :tokens

    def initialize cli
      @current = 0
      @cli = cli
      @tokens = nil
      @line = 1
    end

    def parse text
      @tokens = RubyLox.scan_tokens(@cli, text, @line)
      @current = 0
      @line = @tokens.last.line
      start_rule
    end

    def start_rule
      begin
        return program
      rescue ParseError
        return nil
      end
    end

    def program
      stmts = []

      while !at_end && current().type != :EOF
        res = decl()
        stmts << res if res
      end

      stmts
    end

    def decl
      begin
        return var_decl() if match(:var)

        if (fn = match(:fn))
          name = match(:id)
          params, body = fn_decl(name)
          if name
            return FuncStmt.new(name, params, body)
          else
            consume(:";", "expected ';' after anonymous function")
            fn.literal = "anonymous"
            return AnonymFunc.new(fn, params, body)
          end
        end

        return statement()
      rescue ParseError
        synchronize()
        return nil
      end
    end

    def var_decl
      name = consume(:id, "expected variable name")
      initializer = expression() if match :"="
      consume(:";", "expected ';' after variable declaration")
      Stmt.new([name, initializer], :var)
    end

    def fn_decl name
      consume(:"(", "expected '(' for function parameters")
      params = []

      if !check(:")")
        loop do
          if params.size >= 255
            @cli.err peek(), "can't have more than 255 parameters"
          end

          params << consume(:id, "expected parameter identifier")

          break if !match(:",")
        end
      end

      consume(:")", "expected '(' for function parameters")

      consume(:"{", "expected '{' before " + (name&.literal || "anonymous function") + "'s body")
      body = block()
      [params, body]
    end

    def statement
      case
      when match(:print)
        value = expression()
        consume(:";", "expected ';' after value")
        Stmt.new(value, :print)

      when match(:"{")
        Block.new block()

      when match(:if)
        consume(:"(", "expected '(' for if condition")
        cond = expression()
        consume(:")", "expected '(' after if condition")
        then_stmt = statement()

        else_stmt = nil
        if match(:else)
          else_stmt = statement()
        end

        If.new cond, then_stmt, else_stmt

      when match(:while)
        consume(:"(", "expected '(' before while condition")
        cond = expression()
        consume(:")", "expected ')' after while condition")
        body = statement()

        While.new(cond, body)

      when match(:for)
        consume(:"(", "expected '(' after for")

        if match(:";")
          init = nil
        else
          init = match(:var) ? var_decl() : expr_stmt()
        end

        cond = !check(:";") ? expression() : nil
        consume(:";", "expect ';' after loop condition")

        inc = !check(:")") ? expression() : nil
        consume(:")", "expect ')' after loop condition")
        body = statement()

        if inc
          case body
          when Block
            body.stmts << inc
          else
            body = Block.new([body, inc])
          end
        end

        cond = Literal.new true if !cond
        body = While.new cond, body

        body = Block.new([init, body]) if init

        return body

      when match(:return)
        keyword = prev()
        value = !check(:";") && expression() || nil
        consume(:";", "expected ';' after returning values")
        Return.new value

      else
        return expr_stmt()
      end
    end

    def expr_stmt
      value = expression()
      consume(:";", "expected ';' after value")
      Stmt.new(value, :expr)
    end

    def block
      stmts = []
      stmts << decl() while !check(:"}") && !at_end
      consume :"}", "expected '}' after block"
      stmts
    end

    def expression
      assignment()
    end

    def assignment
      expr = logic_or()

      if match(:"=")
        eq = prev()
        value = assignment()

        if expr.is_a? Variable
          name = expr.name
          return Assignment.new(name, value)
        end

        err eq, "invalid assignment target"
      end

      expr
    end

    def logic_or
      expr = logic_and()

      while match(:or)
        right = logic_or()
        expr = Or.new(expr, right)
      end

      expr
    end

    def logic_and
      expr = equality()

      while match(:and)
        right = equality()
        expr = And.new(expr, right)
      end

      expr
    end

    def equality
      expr = comparison()

      while match(:!=, :==)
        op = prev()
        right = comparison()
        expr = Binary.new(expr, op, right)
      end

      expr
    end

    def comparison
      expr = term()

      while match(:>, :>=, :<, :<=)
        op = prev()
        right = term()
        expr = Binary.new(expr, op, right)
      end

      expr
    end

    def term
      expr = factor()

      while match(:-, :+)
        op = prev()
        right = factor()
        expr = Binary.new(expr, op, right)
      end

      expr
    end

    def factor
      expr = unary()

      while match(:/, :*)
        op = prev()
        right = unary()
        expr = Binary.new(expr, op, right)
      end

      expr
    end

    def unary
      if match(:!, :-)
        op = prev()
        right = unary()
        return Unary.new(op, right)
      end

      call_item()
    end

    def call_item
      callee = primary()
      callee = finish_call(callee) while match(:"(")
      callee
    end

    def finish_call callee
      args = []

      if !check(:")")
        args << expression()
        while match(:",") && args.size < 255
          args << expression()
        end
      end

      paren = consume(:")", "expected ')' after arguments")

      Call.new(callee, paren, args)
    end

    def primary
      case
      when match(:"false") then Literal.new(false)
      when match(:"true") then Literal.new(true)
      when match(:nil) then Literal.new(nil)
      when match(:number, :string)
        Literal.new(prev().literal)
      when match(:"(")
        expr = expression()
        consume(:")", "expected '(' after expression.")
        Grouping.new(expr)
      when match(:id)
        Variable.new(prev())
      when match(:fn)
        tkn = prev()
        tkn.literal = "anonymous"
        params, body = fn_decl(tkn)
        AnonymFunc.new(tkn, params, body)
      else
        err current(), "expected expression"
      end
    end

    #
    # utils
    #

    def match *types
      if types.any? { check _1 }
        advance()
      end
    end

    def check(type) = !at_end && current().type == type

    def advance
      @current += 1 if !at_end()
      prev
    end

    def at_end() = @current >= @tokens.size - 1
    def current() = @tokens[@current]
    def prev() = @tokens[@current - 1]

    def consume type, msg
      if check type
        advance()
      else
        err current(), msg
      end
    end

    SYNC_TOKENS = [:class, :fn, :for, :if, :while, :print, :return]
    def synchronize
      advance()

      while !at_end()
        return if prev().type == :";" || SYNC_TOKENS.include?(current().type)

        advance()
      end

      advance()
    end

    class ParseError < RuntimeError; end

    def err tkn, msg
      @cli.err tkn.line, msg
      raise ParseError.new
    end
  end
end
