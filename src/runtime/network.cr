require "lib_c"
require "process"

module Hocker::Runtime::Network
  extend self
  
  lib LibC
    CLONE_NEWNET = 0x40000000
    
    IFF_UP = 0x1
    
    struct Ifreq
      ifr_name : StaticArray(Char, 16)
      ifr_flags : Int16
    end
    
    fun ioctl(fd : Int32, request : UInt64, ...) : Int32
  end
  
  def create_bridge(name : String = "hocker0", subnet : String = "172.17.0.0/16")
    puts "[Network] Creating bridge: #{name} with subnet #{subnet}"
    
    if interface_exists?(name)
      puts "[Network] Bridge #{name} already exists, reusing it"
      return name
    end
    
    run_command(["ip", "link", "add", name, "type", "bridge"])
    run_command(["ip", "addr", "add", "#{subnet.split('/')[0]}/16", "dev", name])
    run_command(["ip", "link", "set", name, "up"])
    
    enable_nat(name)
    
    puts "[Network] Bridge #{name} created"
    return name
  end
  
  def setup_container_network(container_pid : Int32, container_id : String)
    puts "[Network] Setting up network for container #{container_id} (PID: #{container_pid})"
    
    max_retries = 10
    retries = 0
    while retries < max_retries
      if File.exists?("/proc/#{container_pid}/ns/net")
        puts "[Network] Network namespace found for PID #{container_pid}"
        break
      end
      retries += 1
      sleep(0.1.seconds)
    end
    
    unless File.exists?("/proc/#{container_pid}/ns/net")
      raise "Network namespace not found for PID #{container_pid}"
    end
    
    host_if = "veth#{container_id[0..7]}"
    container_if_temp = "veth#{container_id[8..15]}"
    container_if = "eth0"
    
    puts "[Network] Cleaning up old interfaces..."
    cleanup_interface(host_if)
    cleanup_interface(container_if_temp)
    
    puts "[Network] Creating veth pair: #{host_if} <-> #{container_if_temp}"
    run_command(["ip", "link", "add", host_if, "type", "veth", "peer", "name", container_if_temp])
    
    puts "[Network] Moving #{container_if_temp} to container namespace (PID: #{container_pid})"
    run_command(["ip", "link", "set", container_if_temp, "netns", container_pid.to_s])
    
    puts "[Network] Bringing up host interface and connecting to bridge"
    run_command(["ip", "link", "set", host_if, "up"])
    run_command(["ip", "link", "set", host_if, "master", "hocker0"])
    
    puts "[Network] Configuring container interface..."
    configure_container_interface(container_pid, container_if_temp, container_if, container_id)
    
    puts "[Network] Container network setup complete"
    return {host_if, container_if}
  end
  
  def configure_container_interface(pid : Int64, temp_name : String, final_name : String, container_id : String)
    ns_prefix = "nsenter -t #{pid} -n"
    
    run_command(["sh", "-c", "#{ns_prefix} ip link set lo up"])
    
    run_command(["sh", "-c", "#{ns_prefix} ip link set #{temp_name} name #{final_name}"])
    
    run_command(["sh", "-c", "#{ns_prefix} ip link set #{final_name} up"])
    
    ip_num = 2 + container_id.hash.abs % 253  
    ip_addr = "172.17.0.#{ip_num}/16"
    run_command(["sh", "-c", "#{ns_prefix} ip addr add #{ip_addr} dev #{final_name}"])
    
    run_command(["sh", "-c", "#{ns_prefix} ip route add default via 172.17.0.1"])
    
    puts "[Network] Container IP: #{ip_addr}"
    
    create_resolv_conf(pid)
  end
  
  def create_resolv_conf(pid : Int64)
    ns_prefix = "nsenter -t #{pid} -m"
    
    resolv_conf = <<-CONF
    nameserver 8.8.8.8
    nameserver 8.8.4.4
    CONF
    
    run_command(["sh", "-c", "#{ns_prefix} mkdir -p /etc"])
    
    temp_file = "/tmp/resolv-#{pid}.conf"
    File.write(temp_file, resolv_conf)
    run_command(["sh", "-c", "#{ns_prefix} cp #{temp_file} /etc/resolv.conf"])
    File.delete(temp_file) rescue nil
  end
  
  private def enable_nat(bridge : String)
    File.write("/proc/sys/net/ipv4/ip_forward", "1")
    
    existing_nat_rules = run_command(["iptables", "-t", "nat", "-S", "POSTROUTING"], allow_failure: true)
    
    unless existing_nat_rules.includes?("-s 172.17.0.0/16") && existing_nat_rules.includes?("MASQUERADE")
      run_command(["iptables", "-t", "nat", "-A", "POSTROUTING", 
                   "-s", "172.17.0.0/16", "!", "-o", bridge, 
                   "-j", "MASQUERADE"])
      puts "[Network] Added NAT MASQUERADE rule"
    else
      puts "[Network] NAT MASQUERADE rule already exists"
    end
    
    existing_forward_rules = run_command(["iptables", "-S", "FORWARD"], allow_failure: true)
    
    rule1 = "-A FORWARD -i #{bridge} ! -o #{bridge} -j ACCEPT"
    unless existing_forward_rules.includes?(rule1)
      run_command(["iptables", "-A", "FORWARD", 
                   "-i", bridge, "!", "-o", bridge, 
                   "-j", "ACCEPT"], allow_failure: true)
      puts "[Network] Added FORWARD rule: bridge to external"
    end
    
    rule2 = "-A FORWARD -i #{bridge} -o #{bridge} -j ACCEPT"
    unless existing_forward_rules.includes?(rule2)
      run_command(["iptables", "-A", "FORWARD", 
                   "-i", bridge, "-o", bridge, 
                   "-j", "ACCEPT"], allow_failure: true)
      puts "[Network] Added FORWARD rule: bridge to bridge"
    end
    
    puts "[Network] NAT enabled for bridge #{bridge}"
  end
  
  private def interface_exists?(name : String) : Bool
    process = Process.new("ip", ["link", "show", name],
      output: Process::Redirect::Pipe,
      error: Process::Redirect::Pipe
    )
    status = process.wait
    status.success?
  end
  
  def cleanup_interface(name : String)
    if interface_exists?(name)
      puts "[Network] Cleaning up existing interface: #{name}"
      run_command(["ip", "link", "delete", name], allow_failure: true)
    end
  end
  
  def run_command(cmd : Array(String), allow_failure : Bool = false)
    puts "  Executing: #{cmd.join(" ")}" if ENV["HOCKER_DEBUG"]?
    
    process = Process.new(cmd[0], cmd[1..], 
      output: Process::Redirect::Pipe,
      error: Process::Redirect::Pipe
    )
    
    output = process.output.gets_to_end
    error = process.error.gets_to_end
    status = process.wait
    
    if !status.success? && !allow_failure
      STDERR.puts "Command failed: #{cmd.join(" ")}"
      STDERR.puts "Error: #{error}" unless error.empty?
      raise "Network command failed"
    end
    
    output
  end
  
  def cleanup(container_id : String, host_if : String)
    puts "[Network] Cleaning up network for #{container_id}"
    
    cleanup_interface(host_if)
    
    puts "[Network] Cleanup complete"
  end
  
  def cleanup_all
    puts "[Network] Cleaning up all hocker interfaces"
    
    output = run_command(["ip", "link", "show"], allow_failure: true)
    output.scan(/veth[a-f0-9]+/) do |match|
      cleanup_interface(match[0])
    end
    
    puts "[Network] Full cleanup complete"
  end
  
  def cleanup_iptables
    puts "[Network] Cleaning up iptables rules"
    
    run_command(["iptables", "-t", "nat", "-D", "POSTROUTING",
                 "-s", "172.17.0.0/16", "!", "-o", "hocker0",
                 "-j", "MASQUERADE"], allow_failure: true)
    
    run_command(["iptables", "-D", "FORWARD",
                 "-i", "hocker0", "!", "-o", "hocker0",
                 "-j", "ACCEPT"], allow_failure: true)
    
    run_command(["iptables", "-D", "FORWARD",
                 "-i", "hocker0", "-o", "hocker0",
                 "-j", "ACCEPT"], allow_failure: true)
    
    puts "[Network] iptables cleanup complete"
  end
end
