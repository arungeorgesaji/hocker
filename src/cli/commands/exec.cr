require "option_parser"
require "file_utils"

module Hocker::CLI::Commands::Exec
  extend self

  SYS_SETNS = 308

  CLONE_NEWPID = 0x20000000
  CLONE_NEWNS  = 0x00020000

  def run(args : Array(String))
    STDERR.puts "hocker exec: this feature is not implemented yet"
    exit(1)

    command = "/bin/sh"
    cmd_args = [] of String

    parser = OptionParser.new do |p|
      p.banner = "Usage: hocker exec [OPTIONS] CONTAINER [COMMAND [ARG...]]"
      p.on("-h", "--help", "Show this help") { puts p; exit }
    end

    parser.parse(args)
    remaining = args.reject { |a| a.starts_with?('-') } 

    if remaining.empty?
      STDERR.puts "ERROR: Container name or ID required"
      STDERR.puts parser
      exit(1)
    end

    identifier = remaining[0]
    if remaining.size > 1
      command = remaining[1]
      cmd_args = remaining[2..]
    end

    container = find_container(identifier)
    unless container
      STDERR.puts "Error: No such container: #{identifier}"
      exit(1)
    end

    if container.status != "running"
      STDERR.puts "Error: Container #{container.id[0..11]} is not running (status: #{container.status})"
      exit(1)
    end

    execute_in_container(container, command, cmd_args)
  end

  private def find_container(identifier : String) : Hocker::Runtime::Container?
    dir = Hocker::Runtime::Container::CONTAINER_DIR
    Dir.glob(File.join(dir, "*.json")).each do |file|
      begin
        c = Hocker::Runtime::Container.from_json(File.read(file))
        if c.id == identifier || c.id.starts_with?(identifier) || c.name == identifier
          return c
        end
      rescue
        next
      end
    end
    nil
  end

  private def execute_in_container(container : Hocker::Runtime::Container, cmd : String, args : Array(String))
    pid = container.pid.not_nil! 

    mnt_ns_fd = File.open("/proc/#{pid}/ns/mnt", "r")
    pid_ns_fd = File.open("/proc/#{pid}/ns/pid", "r")

    ret = LibC.syscall(SYS_SETNS, mnt_ns_fd.fd, CLONE_NEWNS)
    if ret != 0
      raise "Failed to setns mount namespace: #{Errno.value}"
    end

    ret = LibC.syscall(SYS_SETNS, pid_ns_fd.fd, CLONE_NEWPID)
    if ret != 0
      raise "Failed to setns PID namespace: #{Errno.value}"
    end

    rootfs = container.rootfs

    if LibC.chroot(rootfs.to_unsafe) != 0
      raise "chroot failed: #{Errno.value}"
    end

    if LibC.chdir("/".to_unsafe) != 0
      raise "chdir to / failed: #{Errno.value}"
    end

    argv = [cmd.to_unsafe]
    args.each { |arg| argv << arg.to_unsafe }
    argv << Pointer(UInt8).null

    envp = [
      "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin".to_unsafe,
      "TERM=xterm-256color".to_unsafe,
      Pointer(UInt8).null,
    ]

    LibC.execve(cmd.to_unsafe, argv.to_unsafe, envp.to_unsafe)

    STDERR.puts "execve failed: #{cmd} - #{Errno.value}"
    exit(127)
  end
end
