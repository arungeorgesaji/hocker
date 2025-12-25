require "option_parser"

module Hocker::CLI::Commands::Exec
  extend self

  SETNS = 308

  def run(args : Array(String))
    command = "/bin/sh"
    cmd_args = [] of String

    parser = OptionParser.new do |p|
      p.banner = "Usage: hocker exec [OPTIONS] CONTAINER [COMMAND [ARG...]]"
      p.on("-h", "--help", "Show this help") do
        puts p
        exit
      end
      p.invalid_option do |flag|
        STDERR.puts "ERROR: #{flag} is not a valid option."
        STDERR.puts p
        exit(1)
      end
    end

    parser.parse(args)
    remaining = args

    if remaining.nil? || remaining.empty?
      STDERR.puts "ERROR: Container name or ID required"
      STDERR.puts parser
      exit(1)
    end

    identifier = remaining[0]
    if remaining.size > 1
      command = remaining[1]
      cmd_args = remaining[2..] if remaining.size > 2
    end

    container = find_container(identifier)
    unless container
      STDERR.puts "Error: No such container: #{identifier}"
      exit(1)
    end

    if container.status != "running"
      STDERR.puts "Error: Container #{container.id[0..11]} is not running (status: #{container.status})"
      exit(1)
    end
  end

  private def find_container(identifier : String) : Hocker::Runtime::Container?
    dir = Hocker::Runtime::Container::CONTAINER_DIR
    Dir.glob(File.join(dir, "*.json")).each do |file|
      begin
        c = Hocker::Runtime::Container.from_json(File.read(file))
        if c.id == identifier || c.id.starts_with?(identifier) || c.name == identifier
          return c
        end
      rescue
        next
      end
    end
    nil
  end
end
