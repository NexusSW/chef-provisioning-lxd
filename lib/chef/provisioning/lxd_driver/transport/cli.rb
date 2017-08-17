require 'chef/provisioning/lxd_driver/transport'
require 'chef/provisioning/lxd_driver/transport/local'
require 'tempfile'

class Chef
  module Provisioning
    module LXDDriver
      class Transport
        class CLI < Transport
          def initialize(driver, remote_transport, container_name, config = {})
            super(driver, container_name, config)
            @inner_transport = remote_transport
            @punt = !inner_transport.is_a?(::Chef::Provisioning::LXDDriver::Transport::Local)
          end
          attr_reader :inner_transport, :punt

          def execute(command, options = {})
            mycommand = command.is_a?(Array) ? command.join(' ') : command
            subcommand = options[:subcommand] || "exec #{container_name} --"
            mycommand = "lxc #{subcommand} #{mycommand}"
            myoptions = options.clone
            myoptions.remove subcommand
            with_streamoptions(myoptions) do |newoptions|
              inner_transport.execute mycommand, newoptions
            end
          end

          def read_file(path)
            tfile = Tempfile.new(container_name)
            tfile.close
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
            tfile = Tempfile.new(container_name)
            tfile.close
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
            tfile = Tempfile.new(container_name) if punt
            tfile.close if tfile
            localname = tfile ? tfile.path : local_path
            execute("#{container_name}#{path} #{localname}", subcommand: 'file pull').error!
            inner_transport.download_file tfile.path, local_path if tfile
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
            tfile = Tempfile.new(container_name) if punt
            tfile.close if tfile
            localname = tfile ? tfile.path : local_path
            inner_transport.upload_file local_path, tfile.path if tfile
            execute("#{localname} #{container_name}#{path}", subcommand: 'file push').error!
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

          def linked_transport(host_name)
            linked = inner_transport.linked_transport(host_name) if inner_transport.is_a?(::Chef::Provisioning::LXDDriver::Transport)
            return linked if linked
            return nil unless remote?(host_name)
            new(driver, inner_transport, "#{host_name}:#{container_name}", config)
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
end
