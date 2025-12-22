require "option_parser"

require "../runtime/runtime"
require "./commands/run"
require "./commands/ps"

module Hocker::CLI
  extend self
  
  def run(args = ARGV)
    command = args.first?
    
    case command
    when "run"
      Commands::Run.run(args[1..])
    when "ps"
      Commands::PS.run
    when "version", "-v", "--version"
      puts "Hocker v#{Hocker::VERSION}"
    when "help", "-h", "--help", nil
      print_help
    else
      puts "Unknown command: #{command}"
      print_help
      exit 1
    end
  end
  
  def print_help
    puts <<-HELP
    Hocker - Container runtime in Crystal
    
    Commands:
      run       Run a container
      ps        List containers
      version   Show version
      help      Show this help
    
    Examples:
      hocker run alpine:latest /bin/sh
      hocker ps
    HELP
  end
end
