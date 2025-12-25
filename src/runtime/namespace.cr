lib LibC
  SYS_unshare = 272
  SYS_chroot  = 161
  SYS_mount   = 165
  
  CLONE_NEWNS  = 0x00020000   
  CLONE_NEWPID = 0x20000000   
  
  MS_REC     = 0x4000
  MS_PRIVATE = 1 << 18
  MS_SLAVE   = 1 << 19
  
  fun fork : Int32
  fun execvp(file : UInt8*, argv : UInt8**) : Int32
  fun execve(path : UInt8*, argv : UInt8**, envp : UInt8**) : Int32
  fun waitpid(pid : Int32, status : Int32*, options : Int32) : Int32
  fun _exit(status : Int32) : NoReturn
  fun chdir(path : UInt8*) : Int32
end

module Hocker::Runtime::Namespace
  extend self
  
  def start_container(container : Hocker::Runtime::Container, detach : Bool = false)
    pid = LibC.fork

    if pid == 0
      setup_namespaces()

      inner_pid = LibC.fork

      if inner_pid == 0
        setup_rootfs(container.rootfs)
        exec_command(container.cmd, container.args)

      elsif inner_pid > 0
        if detach
          LibC._exit(0)
        else
          status = 0
          LibC.waitpid(inner_pid, pointerof(status), 0)
          LibC._exit((status >> 8) & 0xff)
        end

      else
        STDERR.puts "Inner fork failed: #{Errno.value}"
        LibC._exit(1)
      end

    elsif pid > 0
      puts "[Host] Container PID: #{pid}"
      container.update_pid(pid)
      container.update_status("running")

      if detach
        puts "[Host] Container running in background"
        return 0
      else
        status = 0
        LibC.waitpid(pid, pointerof(status), 0)

        exit_code = (status >> 8) & 0xff
        container.update_status("stopped")
        puts "[Host] Container exited with code: #{exit_code}"

        return exit_code
      end

    else
      raise "Fork failed: #{Errno.value}"
    end
  end
  
  private def setup_namespaces
    ret = LibC.syscall(LibC::SYS_unshare, LibC::CLONE_NEWPID | LibC::CLONE_NEWNS)
    if ret != 0
      raise "Failed to create namespaces: #{Errno.value}"
    end
    puts "[Container] Created PID and mount namespaces"
  end
  
  private def setup_rootfs(rootfs_path : String)
    LibC.syscall(LibC::SYS_mount, "none", "/", 0, LibC::MS_REC | LibC::MS_PRIVATE, Pointer(UInt8).null)
    
    ret = LibC.syscall(LibC::SYS_chroot, rootfs_path.to_unsafe)
    if ret != 0
      raise "chroot failed: #{Errno.value}"
    end
    
    LibC.chdir("/".to_unsafe)
    
    LibC.syscall(LibC::SYS_mount, "proc".to_unsafe, "/proc".to_unsafe, "proc".to_unsafe, 0, Pointer(UInt8).null)
    
    puts "[Container] Rootfs setup complete at: #{rootfs_path}"
  end
  
  private def exec_command(cmd : String, args : Array(String))
    argv = Array(Pointer(UInt8)).new(args.size + 2)
    argv << cmd.to_unsafe            
    args.each { |arg| argv << arg.to_unsafe }
    argv << Pointer(UInt8).null

    envp = [
      "PATH=/bin:/usr/bin".to_unsafe,
      Pointer(UInt8).null
    ]

    puts "[Container] Executing: #{cmd}"

    LibC.execve(cmd.to_unsafe, argv.to_unsafe, envp.to_unsafe)

    STDERR.puts "execve failed: #{Errno.value}"
    LibC._exit(1)
  end
end
