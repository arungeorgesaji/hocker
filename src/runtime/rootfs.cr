require "file_utils"

module Hocker::Runtime::RootFS
  extend self
  
  private def elf_interpreter(binary : String) : String?
    output = `readelf -l #{binary} 2>/dev/null`
    output.each_line do |line|
      if line =~ /interpreter:\s*(\/[^\]\s]+)/
        return $1
      end
    end
    nil
  end
  
  def copy_binary(binary_path : String, rootfs : String)
    if rootfs.empty? || rootfs == "/" || !rootfs.starts_with?("/tmp/")
      raise "SAFETY: rootfs must be a safe path in /tmp/, got: #{rootfs}"
    end
  
    actual_path = binary_path.starts_with?("/") ? binary_path : find_binary(binary_path)
    return if actual_path.nil?
    
    dest_path = File.join(rootfs, actual_path)
    FileUtils.mkdir_p(File.dirname(dest_path))
    FileUtils.cp(actual_path, dest_path)
    File.chmod(dest_path, 0o755)
    puts "[RootFS] Copied #{actual_path} to #{dest_path}"
    
    if interp = elf_interpreter(actual_path)
      interp_dest = File.join(rootfs, interp)
      FileUtils.mkdir_p(File.dirname(interp_dest))
      FileUtils.cp(interp, interp_dest) unless File.exists?(interp_dest)
      puts "[RootFS] Copied ELF interpreter: #{interp}"
    end
    
    copy_dependencies(actual_path, rootfs)
  end
  
  private def find_binary(name : String) : String?
    ENV["PATH"].split(":").each do |dir|
      path = File.join(dir, name)
      return path if File.exists?(path) && File::Info.executable?(path)
    end
    nil
  end
  
  private def copy_dependencies(binary : String, rootfs : String)
    output = `ldd #{binary} 2>/dev/null`
    
    output.each_line do |line|
      if line =~ /=>\s+(\S+)/
        lib_path = $1
        next if lib_path == "not" 
        
        dest_path = File.join(rootfs, lib_path)
        dest_dir = File.dirname(dest_path)
        FileUtils.mkdir_p(dest_dir)
        
        FileUtils.cp(lib_path, dest_path) unless File.exists?(dest_path)
        puts "[RootFS] Copied library: #{lib_path}"
        
      elsif line =~ /^\s+(\/\S+)/
        lib_path = $1
        dest_path = File.join(rootfs, lib_path)
        dest_dir = File.dirname(dest_path)
        FileUtils.mkdir_p(dest_dir)
        
        FileUtils.cp(lib_path, dest_path) unless File.exists?(dest_path)
        puts "[RootFS] Copied linker: #{lib_path}"
      end
    end
  end
  
  def create_minimal_rootfs(path : String = "/tmp/hocker-rootfs")
    FileUtils.rm_rf(path) if File.exists?(path)
    FileUtils.mkdir_p(path)
    
    puts "[RootFS] Creating minimal rootfs at: #{path}"
    
    essential_bins = ["sh", "bash", "ls", "cat", "echo", "pwd", "ps", "mkdir", "rm", "cp", "mv", "touch", "grep", "which", "clear", "ping"]
    essential_bins.each do |bin|
      bin_path = ["/bin/#{bin}", "/usr/bin/#{bin}", "/sbin/#{bin}"].find { |p| File.file?(p) && File::Info.executable?(p) }
      if bin_path
        copy_binary(bin_path, path)
      else
        puts "[RootFS] Warning: Could not find binary: #{bin}"
      end
    end

    
    ["dev", "proc", "sys", "tmp", "etc", "var", "run"].each do |dir|
      FileUtils.mkdir_p(File.join(path, dir))
    end

    create_device_files(path)
    
    puts "[RootFS] Minimal rootfs created"
    
    path
  end
  
  def create_test_rootfs(command : String, path : String = "/tmp/hocker-rootfs")
    FileUtils.rm_rf(path) if File.exists?(path)
    FileUtils.mkdir_p(path)
    
    puts "[RootFS] Creating test rootfs at: #{path}"
    
    copy_binary(command, path)
    copy_binary("/bin/sh", path) unless command == "/bin/sh"
    
    ["dev", "proc", "sys", "tmp", "etc"].each do |dir|
      FileUtils.mkdir_p(File.join(path, dir))
    end
    
    create_device_files(path)
    
    puts "[RootFS] Test rootfs created"
    
    path
  end
  
  private def create_device_files(rootfs : String)
    dev_path = File.join(rootfs, "dev")
    
    system("mknod -m 666 #{dev_path}/null c 1 3")
    system("mknod -m 666 #{dev_path}/zero c 1 5")
    system("mknod -m 666 #{dev_path}/random c 1 8")
    system("mknod -m 666 #{dev_path}/urandom c 1 9")
    
    puts "[RootFS] Created device files"
  rescue ex
    puts "[RootFS] Warning: Could not create device files: #{ex.message}"
  end
end
