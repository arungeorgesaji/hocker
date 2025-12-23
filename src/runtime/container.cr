require "json"
require "file_utils"
require "random"

class Hocker::Runtime::Container
  include JSON::Serializable

  property id : String
  property pid : Int32
  property image : String
  property cmd : String
  property args : Array(String)
  property status : String
  property created_at : Time
  property network_mode : String = "none"
  property host_if : String?
  property container_if : String?
  property rootfs : String
  property name : String?

  def initialize(
    @image,
    @cmd,
    @args = [] of String,
    @network_mode = "none",
    @name : String? = nil
  )
    @id = generate_id
    @pid = -1
    @status = "created"
    @created_at = Time.utc
    @rootfs = "/tmp/hocker-rootfs-#{@id}"
  end

  private def generate_id : String
    Random::Secure.hex(12)
  end

  def save
    Dir.mkdir_p(CONTAINER_DIR)
    File.write(container_file, self.to_pretty_json) 
  end

  def container_file : String
    File.join(CONTAINER_DIR, "#{@id}.json")
  end

  def delete
    File.delete(container_file) if File.exists?(container_file)
  end

  def update_status(status : String)
    @status = status
    save
  end

  def update_pid(pid : Int32)
    @pid = pid
    save
  end

  def self.name_taken?(name : String) : Bool
    return false if name.empty?

    Dir.glob(File.join(CONTAINER_DIR, "*.json")).any? do |file|
      begin
        container = from_json(File.read(file))
        container.name == name
      rescue
        false
      end
    end
  end

  CONTAINER_DIR = "/var/run/hocker"
end
