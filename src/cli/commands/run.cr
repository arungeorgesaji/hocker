module Hocker::CLI::Commands
  module Run
    extend self
    
    def run(args)
      puts "Run command called with args: #{args}"
    end
  end
end
