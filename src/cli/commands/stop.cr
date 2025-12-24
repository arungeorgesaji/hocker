module Hocker::CLI::Commands::Stop
  extend self

  def run(args : Array(String))
    identifier : String? = nil
    timeout = 10  

    parser = OptionParser.new do |p|
      p.banner = "Usage: hocker stop [OPTIONS] CONTAINER"

      p.on("-t SECONDS", "--timeout=SECONDS", "Timeout before forcing kill (default: 10)") do |t|
        timeout = t.to_i
      rescue
        STDERR.puts "ERROR: Invalid timeout value: #{t}"
        exit(1)
      end

      p.on("-h", "--help", "Show this help") do
        puts p
        exit
      end

      p.unknown_args do |unknown|
        if unknown.size != 1
          STDERR.puts "ERROR: Exactly one container name or ID required"
          STDERR.puts p
          exit(1)
        end
        identifier = unknown[0]
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

    container = find_container(identifier.not_nil!)
    unless container
      STDERR.puts "Error: No such container: #{identifier}"
      exit(1)
    end

    if container.status != "running"
      puts "Container #{container.id[0..11]} is not running (status: #{container.status})"
      return
    end

    puts "Stopping container #{container.id[0..11]}..."

    if container.pid <= 0
      puts "Warning: No valid PID found for container"
    else
      begin
        Process.signal(Signal::KILL, container.pid)
        puts "Sent SIGTERM to PID #{container.pid}"

        waited = 0
        while waited < timeout && process_running?(container.pid)
          ::sleep(0.5.seconds)
          waited += 0.5
        end

        if process_running?(container.pid)
          Process.signal(Signal::KILL, container.pid)
          puts "Sent SIGKILL to PID #{container.pid}"
          ::sleep(0.5.seconds)  
        end
      rescue ex : Exception 
        puts "Error sending signal: #{ex.message}"
      end
    end

    cleanup_container(container)

    container.update_status("stopped")
    container.save

    puts "Container #{container.id[0..11]} stopped"
  end

  private def find_container(identifier : String) : Hocker::Runtime::Container?
    dir = Hocker::Runtime::Container::CONTAINER_DIR
    Dir.glob(File.join(dir, "*.json")).each do |file|
      begin
        c = Hocker::Runtime::Container.from_json(File.read(file))
        if c.id.starts_with?(identifier) || c.id == identifier || c.name == identifier
          return c
        end
      rescue
        next
      end
    end
    nil
  end

  private def process_running?(pid : Int32) : Bool
    Process.exists?(pid)
  rescue
    false
  end

  private def cleanup_container(container : Hocker::Runtime::Container)
    if host_if = container.host_if
      #Hocker::Runtime::Network.cleanup_interface(host_if)
      container.host_if = nil
    end
  end
end
