module Hocker::CLI::Commands::Run
  extend self
  
  def run(args)
    image = args[0]? || "alpine"
    cmd = args[1]? || "/bin/sh"
    cmd_args = args.size > 2 ? args[2..] : [] of String
    
    puts "[Run] Creating container with command: #{cmd}"
    
    rootfs_path = Hocker::Runtime::RootFS.create_test_rootfs
    
    begin
      Hocker::Runtime::Namespace.create_container(cmd, cmd_args, rootfs_path)
    ensure
      FileUtils.rm_rf(rootfs_path) if Dir.exists?(rootfs_path)
    end
  end
end
