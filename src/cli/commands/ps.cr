module Hocker::CLI::Commands::PS
  extend self

  def run(args = [] of String)
    containers_dir = Hocker::Runtime::Container::CONTAINER_DIR

    unless Dir.exists?(containers_dir)
      puts "No containers found"
      return
    end

    files = Dir.glob(File.join(containers_dir, "*.json"))

    if files.empty?
      puts "No containers found"
      return
    end

    puts sprintf("%-24s %-15s %-20s %-20s %-19s %s",
      "CONTAINER ID", "NAME", "IMAGE", "COMMAND", "CREATED", "STATUS")
    puts "-" * 115

    files.each do |file|
      begin
        container = Hocker::Runtime::Container.from_json(File.read(file))

        name = container.name || "-"
        short_id = container.id[0..11]
        created = container.created_at.to_local.to_s("%Y-%m-%d %H:%M")
        cmd_display = container.cmd
        cmd_display += " #{container.args.join(' ')}" unless container.args.empty?
        cmd_display = cmd_display.strip
        cmd_display = cmd_display[0..17] + "..." if cmd_display.size > 20

        puts sprintf("%-24s %-15s %-20s %-20s %-19s %s",
          short_id,
          name,
          container.image,
          cmd_display,
          created,
          container.status
        )
      rescue ex
        STDERR.puts "Warning: Failed to read #{File.basename(file)}: #{ex.message}"
      end
    end
  end
end
