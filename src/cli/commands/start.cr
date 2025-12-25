module Hocker::CLI::Commands::Start
  extend self

  def run(args : Array(String))
    detach = false
    identifier : String? = nil  

    parser = OptionParser.new do |p|
      p.banner = "Usage: hocker start [OPTIONS] CONTAINER"

      p.on("-d", "--detach", "Run in background") { detach = true }
      p.on("-h", "--help") do
        puts p
        exit
      end

      p.unknown_args do |unknown|
        if unknown.size == 1
          identifier = unknown[0]
        else
          STDERR.puts "ERROR: Exactly one container name or ID required"
          STDERR.puts p
          exit(1)
        end
      end

      p.invalid_option do |flag|
        STDERR.puts "ERROR: #{flag} is not a valid option."
        STDERR.puts p
        exit(1)
      end
    end

    parser.parse(args)

    unless identifier
      STDERR.puts "ERROR: Container name or ID required"
      STDERR.puts parser
      exit(1)
    end

    id = identifier.not_nil!
    container = find_container(id)
    unless container
      STDERR.puts "Error: No such container: #{identifier}"
      exit(1)
    end

    if container.status == "running"
      puts "Container #{container.id[0..11]} is already running"
      return
    end

    valid_states = ["created", "stopped", "exited"]
    unless valid_states.includes?(container.status)
      STDERR.puts "Container is in invalid state: #{container.status}"
      exit(1)
    end

    puts "Starting container #{container.id[0..11]}..."

    exit_code = Hocker::Runtime::Namespace.start_container(container, detach)

    if detach
      container.update_status("running")
      container.save
      puts "Container #{container.id[0..11]} running in background (PID: #{container.pid})"
    else
      container.update_status("exited")
      container.save
      puts "Container exited with code: #{exit_code}"
      exit(exit_code)
    end
  end

  private def find_container(identifier : String) : Hocker::Runtime::Container?
    dir = Hocker::Runtime::Container::CONTAINER_DIR
    Dir.glob(File.join(dir, "*.json")).each do |file|
      begin
        container = Hocker::Runtime::Container.from_json(File.read(file))
        return container if container.id.starts_with?(identifier)
        return container if container.name == identifier
      rescue
        next
      end
    end
    nil  
  end
end
