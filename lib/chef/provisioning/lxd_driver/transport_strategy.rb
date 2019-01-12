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

        # use ssh to the remote host if the options are specified
        def can_rest?
          return false if driver_options[:ssh_options] && driver_options[:ssh_user]

          _, host, port = driver_url.split ":", 3
          host != "localhost" || port.to_i > 0
        end

        def can_cli?
          host == "localhost"
        end

        # Valid URL formats:
        # - "lxd:localhost" => cli
        # - "lxd:localhost:8443" => rest
        # - "lxd:localhost:nested(:nested...)" => cli => cli
        # - "lxd:somewhere" => rest
        # - "lxd:somewhere:8443" => rest
        # - "lxd:somewhere:nested(:nested...)" => rest => cli
        # - "lxd:somewhere:8443:nested(:nested...)" => rest => cli
        def is_nested?
          _, _, port, extra = driver_url.split(":", 4)
          !extra.nil? || (!port.nil? && port.to_i == 0)
        end

        def rest_endpoint
          if can_rest?
            _, host, port = driver_url.split ":", 3
            port = 8443 if port.to_i == 0
            "https://#{host}:#{port}"
          end
        end

        def host_driver
          return nx_driver if nx_driver
          # We're preferring the rest driver due to policy and current/future available provisioning options
          @nx_driver = ::NexusSW::LXD::Driver::Rest.new(rest_endpoint, driver_options) if can_rest?
          @nx_driver ||= ::NexusSW::LXD::Driver::CLI.new(Transport::Local.new, driver_options) if can_cli?
          if !@nx_driver
            # And if the host is remote, we can at least attempt an SSH connection
            transport = ::Chef::Provisioning::Transport::SSH.new(hostname, driver_options[:ssh_user], driver_options[:ssh_options], {}, config) if driver_options[:ssh_options] && driver_options[:ssh_user]
            # TODO: this is wrong - we need an adapter for chefprov-ssh-transport => nexus-lxd-transport
            #   maybe - the nexus side doesn't do type checks and i did model the interface after the chefprov transport
            @nx_driver = ::NexusSW::LXD::Driver::CLI.new(transport) if transport
          end
          if nx_driver && is_nested?
            _, _, nests = driver_url.split(":", 3)
            _, nests = nests.split(":", 2) if nests[0].to_i > 0
            nests.split(":").each { |host| @nx_driver = ::NexusSW::LXD::Driver::CLI.new nx_driver.transport_for(host) }
          end
          raise "No path to host!  The Container Host must have either the REST API enabled, or a way to execute the binary 'lxc'." unless nx_driver
          nx_driver
        end

        def guest_transport(container_name)
          raise "Driver initialization incomplete.  The host driver must be resolved before we can resolve the guest transport." unless host_driver

          Transport.new host_driver, host_driver.transport_for(container_name), config
        end
      end
    end
  end
end
