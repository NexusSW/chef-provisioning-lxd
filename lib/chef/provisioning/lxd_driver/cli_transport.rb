require 'chef/provisioning/lxd_driver/lxd_transport'
require 'chef/provisioning/lxd_dringer/local_transport'

class Chef
  module Provisioning
    module LXDDriver
      class CLITransport < LXDTransport
        def initialize(driver, remote_transport, remote_id, machine_id, config = {})
          super(driver, remote_id ? "#{remote_id}:#{machine_id}" : machine_id, config)
          @inner_transport = remote_transport
          @punt = false

          # if remote_id then it will be lxdtransport, but not necessarily localtransport
          # but if localtransport, just tweak the machine_id
          # else remote_transport is of unknown type and files will need punted
          # and if remote_id but not localtransport, then also, files will need punted

          if remote_id && inner_transport.is_a?(Chef::Provisioning::LXDDriver::LocalTransport)
            inner_transport.container_name = container_name
          else
            @punt = true
          end
        end
        attr_reader :inner_transport, :punt

        def execute(command, options = {})
          return inner_transport.execute command, options unless punt
          mycommand = command
          mycommand = command.join(' ') if command.is_a?(Array)
          subcommand = options[:subcommand] || "exec #{@container_name} --"
          mycommand = "lxc #{subcommand} #{mycommand}"
          myoptions = options.clone
          myoptions.remove subcommand
          inner_transport.execute mycommand, myoptions
        end

        def read_file(path)
          return inner_transport.read_file path unless punt
          # omg why isn't mktmp installed in my test container?  or on my dev station?  wow
          # this is just for filename generation....  it's local so 'hopefully' it doesn't conflict remotely
          tfile = Tempfile.new(@container_name, '/tmp/lxd')
          retval = execute("#{@container_name}#{path} #{tfile.path}", subcommand: 'file pull')
          return '' if retval.exitstatus == 1
          retval.error!
          return inner_transport.read_file tfile.path
        ensure
          if tfile
            begin
              inner_transport.execute "rm -rf #{tfile.path}"
            ensure
              tfile.unlink
            end
          end
        end

        def write_file(path, content)
          return inner_transport.write_file path, content unless punt
          tfile = Tempfile.new(@container_name, '/tmp/lxd')
          inner_transport.write_file tfile.path, content
          execute("#{tfile.path} #{container_name}#{path}", subcommand: 'file push').error!
        ensure
          if tfile
            begin
              inner_transport.execute "rm -rf #{tfile.path}"
            ensure
              tfile.unlink
            end
          end
        end

        def download_file(path, local_path)
          return inner_transport.download_file path, local_path unless punt
          tfile = Tempfile.new(@container_name, '/tmp/lxd')
          execute("#{container_name}#{path} #{tfile.path}", subcommand: 'file pull').error!
          inner_transport.download_file tfile.path, local_path
        ensure
          if tfile
            begin
              inner_transport.execute "rm -rf #{tfile.path}"
            ensure
              tfile.unlink
            end
          end
        end

        def upload_file(local_path, path)
          return inner_transport.upload_file local_path, path unless punt
          tfile = Tempfile.new(@container_name, '/tmp/lxd')
          inner_transport.upload_file local_path, tfile.path
          execute("#{tfile.path} #{container_name}#{path}", subcommand: 'file push').error!
        ensure
          if tfile
            begin
              inner_transport.execute "rm -rf #{tfile.path}"
            ensure
              tfile.unlink
            end
          end
        end

        def add_remote(host_name)
          execute("add #{host_name} --accept-certificate", subcommand: 'remote').error! unless remote? host_name
        end

        def remote?(host_name)
          result = execute 'list', subcommand: 'remote'
          result.error!
          result.stdout.each_line do |line|
            return true if line.start_with? "| #{host_name} "
          end
          false
        end
      end
    end
  end
end
