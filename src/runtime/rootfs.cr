require "file_utils"

module Hocker::Runtime
  module RootFS
    extend self
    
    def create_test_rootfs(path : String = "/tmp/hocker-rootfs")
      puts "[RootFS] Creating test rootfs at: #{path}"
      
      if Dir.exists?(path)
        FileUtils.rm_rf(path)
      end
      
      dirs = [
        path,
        "#{path}/bin",
        "#{path}/lib",
        "#{path}/lib64",
        "#{path}/usr/lib",
        "#{path}/etc",
        "#{path}/proc",
        "#{path}/tmp",
        "#{path}/dev"
      ]
      
      dirs.each do |dir|
        Dir.mkdir_p(dir)
      end
      
      copy_with_deps("/bin/sh", path)
      
      File.write("#{path}/etc/passwd", "root:x:0:0:root:/root:/bin/sh\n")
      File.write("#{path}/etc/group", "root:x:0:\n")
      
      puts "[RootFS] Test rootfs created"
      return path
    end
    
    private def copy_with_deps(binary : String, rootfs : String)
      dst_binary = "#{rootfs}#{binary}"
      FileUtils.mkdir_p(File.dirname(dst_binary))
      FileUtils.cp(binary, dst_binary)
      puts "[RootFS] Copied #{binary} to #{dst_binary}"
      
      output = `ldd #{binary} 2>/dev/null`
      output.each_line do |line|
        if match = line.match(/=>\s+(\S+)/)
          lib_path = match[1]
          if File.exists?(lib_path)
            dst_lib = "#{rootfs}#{lib_path}"
            FileUtils.mkdir_p(File.dirname(dst_lib))
            FileUtils.cp(lib_path, dst_lib)
            puts "[RootFS] Copied library: #{lib_path}"
          end
        end
        
        if match = line.match(/^\s+(\/\S+)/)
          linker_path = match[1]
          if File.exists?(linker_path)
            dst_linker = "#{rootfs}#{linker_path}"
            FileUtils.mkdir_p(File.dirname(dst_linker))
            FileUtils.cp(linker_path, dst_linker)
            puts "[RootFS] Copied linker: #{linker_path}"
          end
        end
      end
    end
  end
end
