require "chef"
require "chef/provisioning"
require "chef/provisioning/lxd_driver/transport/local"
require "chef/provisioning/lxd_driver/transport/cli"
require "chef/provisioning/lxd_driver/transport/rest"
require "chef/provisioning/transport/ssh"
require "nexussw/lxd/driver/cli"
require "nexussw/lxd/driver/rest"

class Chef
  module Provisioning
    module LXDDriver
      class TransportStrategy
        def initialize(driver, global_config)
          @driver_url = driver.driver_url
          @config = global_config
          @driver_options = driver.driver_options
        end

        attr_reader :driver_url, :driver_options, :config, :nx_driver

        def hostname
          driver_url.split(":", 3)[1]
        end

        def can_rest?
          _, _, port = driver_url.split ":", 3
          port && !driver_options[:disable_rest]
        end

        def can_cli?
          !driver_options[:disable_cli]
        end

        def rest_endpoint
          return nil unless can_rest?
          _, host, port = driver_url.split ":", 3
          "https://#{host}:#{port}"
        end

        # Need to resolve the transports lazily just in case the host isn't provisioned yet

        def host_driver(chef_server = nil)
          return nx_driver if nx_driver
          # We're preferring the rest driver due to policy and current/future available provisioning options
          @nx_driver = ::NexusSW::LXD::Driver::Rest.new(rest_endpoint, driver_options) if can_rest?
          # I'd let this one be covered by the below logic, but 'localhost' is not likely managed
          @nx_driver ||= ::NexusSW::LXD::Driver::CLI.new(Transport::Local.new, driver_options) if hostname == "localhost" && can_cli?
          return nx_driver if nx_driver

          # This will call guest_transport on the host's:host's strategy instance if it is a managed lxd host
          # if it is a managed non-lxd host, this will return whatever transport the other driver deems appropriate
          chef_server ||= ::Chef.run_context.cheffish.current_chef_server
          machine = ::Chef.run_context.chef_provisioning.connect_to_machine(hostname, chef_server || {})
          transport = machine.transport if machine

          # And if the host is unmanaged, we can at least attempt an SSH connection
          transport ||= ::Chef::Provisioning::Transport::SSH.new(hostname, driver_options[:ssh_user], driver_options[:ssh_options], {}, config) if driver_options[:ssh_options] && driver_options[:ssh_user]
          @nx_driver = ::NexusSW::LXD::Driver::CLI.new(transport, driver_options) if transport && can_cli?
          raise "No path to host!  The Container Host must have either the REST API enabled, or a way to execute the binary 'lxc'." unless @nx_driver
          @nx_driver
        end

        def guest_transport(container_name, container_options = {})
          chef_server = container_options["convergence_options"][:chef_server] if container_options && container_options["convergence_options"]
          # Should never get this unless we're mis-coded
          raise "Driver initialization incomplete.  The host driver must be resolved before we can resolve the guest transport." unless nx_driver || host_driver(chef_server)
          # try localhost:linked first (most efficient - no punting)
          # preferring CLI in this context due to performance with nesting and that there's no difference in available options
          if can_cli?
            cli = Transport::CLI.new(nx_driver, Transport::Local.new, container_name, config)
            return cli if hostname == "localhost"
            # localhost might not have lxd installed, nor be involved in provisioning (unmanaged).  But if it has a functioning lxd, use the remote, if available
            begin
              return cli.linked_transport(hostname) if cli.remote?(hostname)
            rescue
              nil # stuff it rubocop - i'll code an exact exception eventually.  Cases: 1) lxc responds but is unconfigured, or 2) lxc is not installed
            end
          end
          # next try rest api (always direct, but it serializes files - less efficient for larger files)
          # nx_driver MUST be Driver::Rest.  Right now it deterministically is, if can_rest?, but if the strategy changes, we'll have to force it
          return Transport::Rest.new(nx_driver, container_name, config) if can_rest?
          # if we can't rest, then punting is unavoidable and take what we can get, but try to get as close to localhost as possible via cli remotes (links)
          # remoting requires machine.transport.is_a? Transport::CLI.  If it comes up as rest, or from some other driver, we're already as good as it gets so don't force it
          if can_cli?
            machine = ::Chef.run_context.chef_provisioning.connect_to_machine(hostname, chef_server)
            transport = Transport::CLI.new(nx_driver, machine.transport, container_name, config) if machine && machine.transport
            linked = transport.linked_transport(hostname) if transport
            return linked || transport if linked || transport
            # Blind fire an SSH connection to the host on the premise that it may be unmanaged
            hostssh = ::Chef::Provisioning::Transport::SSH.new(hostname, driver_options[:ssh_user], driver_options[:ssh_options], {}, config) if driver_options[:ssh_options] && driver_options[:ssh_user]
            return Transport::CLI.new(nx_driver, hostssh, container_name, config) if hostssh
          end
          # And again, if for some reason the above doesn't work, we can at least attempt a direct SSH connection - user would have to supply a custom image with sshd running
          return ::Chef::Provisioning::Transport::SSH.new(container_name, container_options[:ssh_user], container_options[:ssh_options], {}, config) if container_options[:ssh_options] && container_options[:ssh_user]
          raise "No path to host!  The Container Host must have either the REST API enabled, or a way to execute the binary 'lxc'."
        end
      end
    end
  end
end
