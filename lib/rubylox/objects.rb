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

    def initialize decl, closure = nil, is_init = false
      @decl = decl
      @closure = closure
      @is_init = is_init
    end

    def arity = @decl.params.size

    def call intr, args
      env = Enviroment.new @closure || intr.globals
      @decl.params.zip(args) do |param, arg|
        env.make_var param, arg
      end

      ret = nil
      begin
        intr.eval_block @decl.body, env
      rescue ReturnValue => e
        ret = @is_init ? @closure.get_at(0, "this") : e.val
      end

      return ret
    end

    def bind instance
      env = Enviroment.new @closure
      env.make_var Token.new(nil, "this", nil), instance
      return ObjFunction.new @decl, env, @is_init
    end

    def to_s
      "<fn #{@decl.name.literal}>"
    end
  end

  class LoxKlass
    include Function

    attr_accessor :name

    def initialize name, methods
      @name = name
      @methods = methods
    end

    def to_s = "<class #{name}>"

    def call intr, args
      ins = LoxInstance.new(self)

      find_method("init")&.tap do |met|
        met.bind(ins).call(intr, args)
      end

      ins
    end

    def find_method name
      @methods[name]
    end

    def arity
      find_method("init")&.arity || 0
    end
  end

  class LoxInstance
    attr_reader :cls

    def initialize cls
      @cls = cls
      @fields = {}
    end

    def [](name)
      method = @cls.find_method name
      return method.bind(self) if method

      @fields[name]
    end

    def []=(name, v)
      @fields[name.literal] = v.nil? ? :nil : v
    end

    def to_s = "<instance of #{@cls.name}>"
  end
end
