require "option_parser"

require "../runtime/runtime"
require "../runtime/container"
require "./commands/create"
require "./commands/start"
require "./commands/exec"
require "./commands/stop"
require "./commands/ps"
require "./commands/rm"

module Hocker::CLI
  extend self
  
  def run(args = ARGV)
    command = args.first?
    
    case command
    when "create"
      Commands::Create.run(args[1..])
    when "start"
      Commands::Start.run(args[1..])
    when "exec"
      Commands::Exec.run(args[1..])
    when "ps"
      Commands::PS.run
    when "stop"
      Commands::Stop.run(args[1..])
    when "rm"
      Commands::RM.run(args[1..])
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
      create    Create a new container
      start     Start a container
      exec      Execute a command in a running container
      stop      Stop a running container
      ps        List containers
      rm        Remove a container
      version   Show version
      help      Show this help
    HELP
  end
end
