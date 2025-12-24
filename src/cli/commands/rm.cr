module Hocker::CLI::Commands::RM
  extend self

  def run(args : Array(String))
    force = args.includes?("-f") || args.includes?("--force")

    remaining_args = args.reject { |a| a == "-f" || a == "--force" }

    if remaining_args.empty?
      puts "Usage: hocker rm [OPTIONS] CONTAINER [CONTAINER...]"
      puts ""
      puts "Remove one or more stopped containers."
      puts ""
      puts "Options:"
      puts "  -f, --force    Force removal of a running container"
      return
    end

    removed = 0
    failed = 0

    remaining_args.each do |identifier|
      container = find_container(identifier.strip)

      if container.nil?
        puts "Error: No such container: #{identifier}"
        failed += 1
        next
      end

      if container.status == "running" && !force
        puts "Error: Cannot remove running container #{identifier} (use -f to force)"
        failed += 1
        next
      end

      if container.status == "running" && force
        puts "[#{container.id}] Stopping container before removal..."
        stop_container(container)
      end

      if Dir.exists?(container.rootfs)
        FileUtils.rm_rf(container.rootfs)
        puts "[#{container.id}] Removed rootfs: #{container.rootfs}"
      end

      container.delete

      name_part = container.name ? " (#{container.name})" : ""
      puts "Removed container: #{container.id[0..11]}#{name_part}"
      removed += 1
    end

    if removed > 0 && failed == 0
      puts "Successfully removed #{removed} container#{"s" if removed > 1}."
    elsif failed > 0
      puts "Removed #{removed}, failed #{failed}."
    end
  end

  private def find_container(identifier : String) : Hocker::Runtime::Container?
    dir = Hocker::Runtime::Container::CONTAINER_DIR

    Dir.glob(File.join(dir, "*.json")).each do |file|
      begin
        container = Hocker::Runtime::Container.from_json(File.read(file))

        if container.id == identifier ||
           container.id.starts_with?(identifier) ||
           container.name == identifier
          return container
        end
      rescue
        next
      end
    end

    nil
  end

  private def stop_container(container : Hocker::Runtime::Container)
    if container.pid > 0
      begin
        Process.signal(Signal::TERM, container.pid)
        puts "[#{container.id}] Sent SIGTERM"

        ::sleep(3.seconds)

        if Process.exists?(container.pid)
          Process.signal(Signal::KILL, container.pid)
          puts "[#{container.id}] Sent SIGKILL"
        end
      rescue ex
      end
    end

    container.update_status("stopped")
  end
end
