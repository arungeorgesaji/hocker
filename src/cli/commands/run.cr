module Hocker::CLI::Commands::Run
  extend self
  
  def run(args)
    #image = "alpine"  
    cmd = "/bin/sh"   
    cmd_args = [] of String
    network_mode = "none"
    detach = false
    name : String? = nil
    remaining_args = [] of String
    
    OptionParser.parse(args) do |parser|
      parser.banner = "Usage: hocker run [OPTIONS] IMAGE COMMAND [ARGS...]"
      
      parser.on("-d", "--detach", "Run container in background") do
        detach = true
      end
      
      parser.on("--name NAME", "Container name") do |n|
        name = n
      end
      
      parser.on("--network NETWORK", "Network mode (none, host, bridge)") do |net|
        network_mode = net
      end
      
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
      end
      
      parser.invalid_option do |flag|
        STDERR.puts "ERROR: #{flag} is not a valid option."
        STDERR.puts parser
        exit(1)
      end
      
      parser.unknown_args do |args|
        remaining_args = args
      end
    end
    
    if remaining_args.size >= 2
      image = remaining_args[0]
      cmd = remaining_args[1]
      cmd_args = remaining_args[2..] if remaining_args.size > 2
    elsif remaining_args.size == 1
      image = remaining_args[0]
    end
    
    puts "[Run] Creating container with image: #{image}, command: #{cmd}"
    
    rootfs_path = Hocker::Runtime::RootFS.create_minimal_rootfs
    
    container = Hocker::Runtime::Container.new(
      image: image,
      cmd: cmd,
      args: cmd_args,
      network_mode: network_mode
    )
    container.rootfs = rootfs_path

    if name && Hocker::Runtime::Container.name_taken?(name.not_nil!)
      STDERR.puts "ERROR: A container with name '#{name}' already exists."
      exit(1)
    end
    
    if name
      container.name = name
      puts "[Run] Container name: #{name} (ID: #{container.id})"
    else
      puts "[Run] Container ID: #{container.id}"
    end
    
    container.save
    
    #if network_mode == "bridge"
    #  Hocker::Runtime::Network.create_bridge
    #end
    
    exit_code = Hocker::Runtime::Namespace.create_container(container)
    
    unless detach
      puts "\n[Run] Container #{container.id} exited with code: #{exit_code}"
    else
      puts "[Run] Container #{container.id} running in background"
      puts "[Run] Use 'hocker ps' to see running containers"
    end
    
    exit_code
  end
  
  def stop_container(container_id : String)
    puts "[Run] Stopping container #{container_id}"
    
    container = find_container(container_id)
    return unless container
    
    if container.pid > 0
      begin
        Process.kill(Signal::TERM, container.pid)
        puts "[Run] Sent SIGTERM to PID #{container.pid}"
        
        sleep 2
        if process_running?(container.pid)
          Process.kill(Signal::KILL, container.pid)
          puts "[Run] Sent SIGKILL to PID #{container.pid}"
        end
      rescue ex
        puts "[Run] Error stopping container: #{ex.message}"
      end
    end
    
    if host_if = container.host_if
      Hocker::Runtime::Network.cleanup_interface(host_if)
    end
    
    if Dir.exists?(container.rootfs)
      FileUtils.rm_rf(container.rootfs)
    end
    
    container.update_status("stopped")
    puts "[Run] Container #{container_id} stopped"
  end
   
  private def load_container(file : String) : Hocker::Runtime::Container?
    begin
      Hocker::Runtime::Container.from_json(File.read(file))
    rescue
      nil
    end
  end
end
