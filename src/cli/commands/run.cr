module Hocker::CLI::Commands::Run
  extend self
  
  def run(args)
    image = args[0]? || "alpine:latest"
    cmd = args[1]? || "/bin/sh"
    cmd_args = args.size > 2 ? args[2..] : [] of String
    
    puts "Running #{cmd} from #{image} in container..."
    
    Hocker::Runtime::Namespace.create_pid_namespace(cmd, cmd_args)
  end
end
