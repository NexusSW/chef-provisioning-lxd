require 'chef/provisioning/lxd_driver/local_transport'
require 'chef/provisioning/lxd_driver/cli_transport'
require 'chef/provisioning/lxd_driver/hosted_transport'
require 'chef/provisioning/lxd_driver/rest_transport'
require 'chef/provisioning/transport/ssh'
require 'nexussw/lxd/cli_driver'
require 'nexussw/lxd/rest_driver'

class Chef
  module Provisioning
    module LXDDriver
      class TransportStrategy
        def initialize(driver, container_name, global_config)
          @driver = driver
          @driver_url = driver.driver_url
          @config = global_config
          @driver_options = driver.driver_options
          @container_name = container_name
        end

        attr_reader :driver_url, :driver_options, :config, :container_name, :driver

        def hostname
          driver_url.split(':', 3)[1]
        end

        def can_rest?
          _, _, port = driver_url.split ':', 3
          port
        end

        def rest_endpoint
          return nil unless can_rest?
          _, host, port = driver_url.split ':', 3
          "https://#{host}:#{port}"
        end

        # Need to resolve the transports lazily just in case the host isn't provisioned yet

        # Return some transport ready to execute 'lxc' provisioning commands
        def host_transport(chef_server = {})
          return LocalTransport.new if hostname == 'localhost'

          # This will punt to guest_transport on the host's strategy instance if it is a managed lxd host
          # Just take what we're given.  File punting is not an issue in this context
          machine = run_context.chef_provisioning.connect_to_machine(hostname, chef_server) unless hostname == 'localhost'
          return machine.transport if machine

          # And if the host is unmanaged, we can at least attempt an SSH connection
          return ::Chef::Provisioning::Transport::SSH.new(hostname, driver_options[:ssh_user], driver_options[:ssh_options], {}, config) if driver_options[:ssh_options] && driver_options[:ssh_user]
        end

        def host_driver(chef_server = {})
          return ::NexusSW::LXD::CLIDriver.new(LocalTransport.new, driver_options) if hostname == 'localhost'
          return ::NexusSW::LXD::RestDriver.new(rest_endpoint, driver_options) if can_rest?
          ::NexusSW::LXD::CLIDriver.new(host_transport(chef_server), driver_options)
        end

        # Return either a rest transport, or otherwise a CLI transport wrapping some transport ready to execute 'lxc' exec & file commands
        def guest_transport(machine_options = {})
          # try localhost-linked first (most efficient - no punting)
          cli = CLITransport.new(driver, LocalTransport.new, nil, container_name, config)
          return cli if hostname == 'localhost'
          if cli.remote?(hostname)
            cli.container_name = "#{hostname}:#{container_name}"
            return cli
          end
          # next try rest api (always direct, but it serializes files - less efficient especially for large files)
          return RestTransport(rest_endpoint, container_name, config) if can_rest?
          # if we can't rest, then punting is unavoidable and take what we can get, but try to get as close to localhost as possible via cli remotes (links)
          chef_server = machine_options[:convergence_strategy][:chef_server] if machine_options && machine_options[:convergence_strategy]
          machine = run_context.chef_provisioning.connect_to_machine(hostname, chef_server || {})
          return CLITransport.new(driver, machine.transport, hostname, container_name, config) if machine
          # Blind fire an SSH connection to the host on the premise that it may be unmanaged
          hostssh = ::Chef::Provisioning::Transport::SSH.new(hostname, driver_options[:ssh_user], driver_options[:ssh_options], {}, config) if driver_options[:ssh_options] && driver_options[:ssh_user]
          return CLITransport.new(driver, hostssh, hostname, container_name, config) if hostssh
          # And again, if for some reason the above doesn't work, we can at least attempt an SSH connection - user would have to supply a custom image with sshd running
          return ::Chef::Provisioning::Transport::SSH.new(container_name, machine_options[:ssh_user], machine_options[:ssh_options], {}, config) if machine_options[:ssh_options] && machine_options[:ssh_user]
          raise "No path to host!  The Container Host must have either the REST API enabled, or a way to execute the binary 'lxc'."
        end
      end
    end
  end
end
