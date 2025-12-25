module Hocker::CLI::Commands::Create
  extend self

  def run(args : Array(String))
    name : String? = nil
    image : String? = nil

    OptionParser.parse(args) do |parser|
      parser.banner = "Usage: hocker create [OPTIONS] IMAGE"

      parser.on("--name NAME", "Assign a name to the container") { |n| name = n }
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit
      end

      parser.invalid_option do |flag|
        STDERR.puts "ERROR: #{flag} is not a valid option."
        STDERR.puts parser
        exit(1)
      end

      #parser.unknown_args do |unknown|
      #  if unknown.size != 1
      #    STDERR.puts "ERROR: Exactly one IMAGE is required"
      #    STDERR.puts parser
      #    exit(1)
      #  end
      #  image = unknown[0]
      #end
    end

    image ||= "alpine"

    unless image
      STDERR.puts "ERROR: IMAGE is required"
      exit(1)
    end

    if name && Hocker::Runtime::Container.name_taken?(name.not_nil!)
      STDERR.puts "Error: name '#{name}' is already taken"
      exit(1)
    end

    rootfs_path = Hocker::Runtime::RootFS.create_minimal_rootfs

    container = Hocker::Runtime::Container.new(
      image: image.not_nil!,
      cmd: "/bin/sh",
      args: [] of String,
      network_mode: "none"
    )

    container.rootfs = rootfs_path
    container.status = "created"
    container.name = name if name

    container.save

    puts "Container created: #{container.id[0..11]}"
    puts "Name: #{container.name || "-"}"
    puts "Default command: /bin/sh"

    identifier = container.name || container.id[0..11]
    puts "Use 'hocker start #{identifier}' to start it (will run /bin/sh)"
  end
end
