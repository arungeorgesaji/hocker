require "option_parser"

module Hocker::CLI::Commands::Exec
  extend self

  SETNS = 308

  def run(args : Array(String))
    interactive = false
    tty = false
    command = "/bin/sh"
    cmd_args = [] of String

    parser = OptionParser.new do |p|
      p.banner = "Usage: hocker exec [OPTIONS] CONTAINER [COMMAND [ARG...]]"
      p.on("-i", "--interactive", "Keep STDIN open (interactive)") do
        interactive = true
      end
      p.on("-t", "--tty", "Allocate a pseudo-TTY") do
        tty = true
      end
      p.on("-h", "--help", "Show this help") do
        puts p
        exit
      end
      p.invalid_option do |flag|
        STDERR.puts "ERROR: #{flag} is not a valid option."
        STDERR.puts p
        exit(1)
      end
    end

    parser.parse(args)
    remaining = args

    if remaining.nil? || remaining.empty?
      STDERR.puts "ERROR: Container name or ID required"
      STDERR.puts parser
      exit(1)
    end

    identifier = remaining[0]
    if remaining.size > 1
      command = remaining[1]
      cmd_args = remaining[2..] if remaining.size > 2
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

    if interactive || tty
      enable_raw_mode if tty
    end

    enter_namespaces_and_exec(container.pid, command, cmd_args)
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

  private def enter_namespaces_and_exec(pid : Int32, cmd : String, args : Array(String))
    {% unless flag?(:linux) %}
      raise "hocker exec only works on Linux"
    {% end %}

    namespaces = {
      "pid" => "/proc/#{pid}/ns/pid",
      "mnt" => "/proc/#{pid}/ns/mnt",
      "uts" => "/proc/#{pid}/ns/uts",
      "ipc" => "/proc/#{pid}/ns/ipc",
      "net" => "/proc/#{pid}/ns/net",
    }

    fds = {} of String => Int32

    begin
      namespaces.each do |name, path|
        fd = LibC.open(path, LibC::O_RDONLY)
        if fd == -1
          error = Errno.value
          STDERR.puts "Failed to open #{path}: #{error}"
          raise "Failed to open namespace file: #{path}"
        end
        fds[name] = fd
      end

      ["mnt", "uts", "ipc", "net"].each do |name|
        if LibC.syscall(SETNS, fds[name], 0) != 0
          raise "setns failed for #{name}: #{Errno.value}"
        end
      end

      if LibC.syscall(SETNS, fds["pid"], LibC::CLONE_NEWPID) != 0
        raise "setns failed for pid: #{Errno.value}"
      end

      fork_pid = LibC.fork
      if fork_pid == -1
        raise "fork failed: #{Errno.value}"
      end

      if fork_pid == 0
        exec_command(cmd, args)
        STDERR.puts "exec failed: command not found or permission denied"
        exit(1)
      else
        status = 0
        LibC.waitpid(fork_pid, pointerof(status), 0)
        exit_code = (status >> 8) & 0xFF
        exit(exit_code)
      end

    ensure
      fds.each_value do |fd|
        LibC.close(fd)
      end
    end
  end

  private def exec_command(cmd : String, args : Array(String))
    argv = [cmd.to_unsafe]
    args.each { |a| argv << a.to_unsafe }
    argv << Pointer(UInt8).null

    envp = [
      "TERM=#{ENV["TERM"]? || "xterm"}".to_unsafe,
      "PATH=/bin:/usr/bin:/sbin:/usr/sbin".to_unsafe,
      "HOME=/root".to_unsafe,
      Pointer(UInt8).null
    ]

    LibC.execve(cmd.to_unsafe, argv.to_unsafe, envp.to_unsafe)
  end

  private def enable_raw_mode
    return unless STDIN.tty?
    old_state = `stty -g`.chomp
    `stty raw -echo opost isig 2>/dev/null`
    at_exit do
      `stty #{old_state} 2>/dev/null`
    end
  end
end
