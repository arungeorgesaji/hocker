lib LibC
  fun unshare(flags : Int32) : Int32
  fun setns(fd : Int32, nstype : Int32) : Int32
  fun waitpid(pid : Int32, status : Int32*, options : Int32) : Int32
  fun fork : Int32
  fun execvp(file : UInt8*, argv : UInt8**) : Int32
  fun _exit(status : Int32) : NoReturn
end

module Hocker::Runtime::Namespace
  extend self

  CLONE_NEWPID = 0x20000000

  def create_pid_namespace(cmd : String, args : Array(String))
    if LibC.unshare(CLONE_NEWPID) != 0
      raise "Failed to unshare PID namespace: #{Errno.value}"
    end

    pid = LibC.fork

    if pid == 0
      argv = Array(Pointer(UInt8)).new
      argv << cmd.to_unsafe
      args.each { |a| argv << a.to_unsafe }
      argv << Pointer(UInt8).null

      LibC.execvp(cmd.to_unsafe, argv.to_unsafe)
      LibC._exit(1) 
    elsif pid > 0
      status = 0
      LibC.waitpid(pid, pointerof(status), 0)
      exit (status >> 8) & 0xff
    else
      raise "fork failed: #{Errno.value}"
    end
  end
end
