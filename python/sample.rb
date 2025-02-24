# Super module comment
module MyModule
  # Super class comment
  class MyClass < Test::SuperClass

    # This is a comment
    def self.self_method
      # asfasdfasdf puts 'Hello, world!'
    end

    def instance_method
      # asfasdfasdf
      puts 'Hello, world!'
    end

    class << self
      def another_self_method
        puts 'Hello, world!'
      end
    end
  end

  class MyAnotherClass
    include Enumerable
    def myanotherclass_instance_method
      # asfasdfasdf
      puts 'Hello, world!'
    end
  end
end

def top_level_method
  puts 'Hello, world!'
end