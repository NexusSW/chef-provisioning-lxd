require 'chef/mash'
require 'chef/provisioning/driver'
require 'chef/provisioning/transport/ssh'
require 'chef/provisioning/convergence_strategy/install_cached'
require 'chef/provisioning/machine/unix_machine'
require 'chef/provisioning/lxd_driver/version'
require 'nexussw/lxd/driver'
require 'chef/provisioning/lxd_driver/transport'
require 'pp'

class Chef
  module Provisioning
    module LXDDriver
      class Driver < Chef::Provisioning::Driver
        def self.from_url(url, config)
          Driver.new(url, config)
        end

        def self.canonicalize_url(driver_url, config)
          _, address, port = driver_url.split(':', 3)
          address ||= 'localhost'
          port ||= 8443
          ["lxd:#{address}:#{port}", config]
        end

        def initialize(url, config)
          super(url, config)
          # pp 'Driver Options: ', config
          @lxd = NexusSW::LXD::Driver.new(host_address, clone_mash(driver_options))
        end

        attr_reader :lxd

        def host_address
          _, host, port = driver_url.split(':', 3)
          "https://#{host}:#{port}"
        end

        def host_name
          driver_url.split(':',3)[1]
        end

        def clone_mash(mash)
          retval = {}
          mash.each { |key, val| retval[key.to_sym] = val } if mash
          retval
        end

        def allocate_machine(action_handler, machine_spec, machine_options)
          machine_id = nil
          if machine_spec.reference
            machine_id = machine_spec.reference['machine_id']
            unless @lxd.container_exists?(machine_id)
              # It doesn't really exist
              action_handler.perform_action "Container #{machine_id} does not really exist.  Recreating ..." do
                machine_id = nil
                machine_spec.reference = nil
              end
            end
          end
          unless machine_id
            action_handler.perform_action "Creating container #{machine_spec.name} with options #{machine_options}" do
              raise "Container #{machine_spec.name} already exists" if @lxd.container_exists?(machine_spec.name)
              machine_id = @lxd.create_container(machine_spec.name, clone_mash(machine_options))
              machine_spec.reference = {
                'driver_url' => driver_url,
                'driver_version' => LXDDriver::VERSION,
                'machine_id' => machine_id,
              }
            end
          end
          @lxd.start_container_async machine_id
        end

        def ready_machine(action_handler, machine_spec, machine_options)
          machine_id = machine_spec.reference['machine_id']
          if @lxd.container_status(machine_id) == 'stopped'
            action_handler.perform_action "Starting container #{machine_id}" do
              @lxd.start_container_async(machine_id)
            end
          end

          unless @lxd.container_status(machine_id) == 'running'
            action_handler.perform_action "Waiting for container #{machine_id}" do
              @lxd.start_container(machine_id)
            end
          end

          # Return the Machine object
          machine_for(machine_spec, machine_options)
        end

        # machine_spec = Provisioning.chef_managed_entry_store ***(chef_server)*** .get(:machine, name)
        # returns [remote_id, remote_driver] where the 'remote_transport.execute' is called with:
        #   lxc exec remote_id:machine_id -- blah blah blah
        # if remote_id is specified, then remote_driver is an lxd driver that supports remote_id:machine_id
        # anything returned from here 'might' need files punted to it.
        def remoteinfo
          return nil if host_name == 'localhost'
          myhost_driver_url = run_context.chef_provisioning.chef_managed_entry_store.get(:machine, host_name).driver_url
          # raise 'No path to host!  Invalid root node specified in the recipe' unless myhost_driver_url
          return nil unless myhost_driver_url
          myhost_driver = run_context.chef_provisioning.driver_for myhost_driver_url
          # raise 'No path to host!  Invalid root node specified in the recipe' unless myhost_driver
          return nil unless myhost_driver
          # if we didn't make it this far, and we're not localhost, then likely a new root needs specified in the recipe
          # fallback driver knows how to exec on my lxd host, but could be deeply nested hosted_transports with multiple 'punts'
          retval = [nil, myhost_driver]
          # look deeper for a linked server
          loop do
            # we hit a non-lxd driver - which makes no sense to continue in the 'nesting' context - and transport.remote? is lxd specific
            return retval unless myhost_driver_url.start_with?('lxd:')
            # coup de grâce
            retval = [host_name, myhost_driver] if myhost_driver.transport.remote?(host_name) # keep looking deeper (closer)

            # move next
            myhost_driver_hostname = myhost_driver_url.split(':', 3)[1]
            return retval if myhost_driver_hostname == 'localhost'
            myhost_driver_url = run_context.chef_provisioning.chef_managed_entry_store.get(:machine, myhost_driver_hostname).driver_url
            return retval unless myhost_driver_url
            myhost_driver = run_context.chef_provisioning.driver_for myhost_driver_url
            return retval unless myhost_driver
          end
        end

        def machine_for(machine_spec, machine_options)
          machine_id = machine_spec.reference['machine_id']
          # local transport is the most efficient so try it first, always
          transport = Chef::Provisioning::LXDDriver::LocalTransport.new(@lxd, machine_id, config) if host_name == 'localhost'
          transport ||= Chef::Provisioning::LXDDriver::RemoteTransport.new(@lxd, remote_id, machine_id, config) if @lxd.is_a? ***INSERTDISCRIMINATORHERE***
          # hosted transports 'might' need one or more punts - use as a last resort
          remote_id, remote_transport = remoteinfo(machine_spec, machine_options) unless transport
          transport ||= Chef::Provisioning::LXDDriver::HostedTransport.new(@lxd, remote_transport, remote_id, machine_id, config) if remote_transport

          raise 'No path to host!  Invalid root node specified in the recipe' unless transport

          convergence_strategy = Chef::Provisioning::ConvergenceStrategy::InstallCached.new(machine_options['convergence_options'] || {}, config)
          Chef::Provisioning::Machine::UnixMachine.new(machine_spec, transport, convergence_strategy)
        end

        def destroy_machine(action_handler, machine_spec, _machine_options)
          return unless machine_spec.reference
          machine_id = machine_spec.reference['machine_id']
          action_handler.perform_action "Destroy container #{machine_id}" do
            @lxd.delete_container(machine_id)
            machine_spec.reference = nil
          end
        end

        def stop_machine(action_handler, machine_spec, _machine_options)
          return unless machine_spec.reference
          machine_id = machine_spec.reference['machine_id']
          action_handler.perform_action "Stopping container #{machine_id}" do
            @lxd.stop_container(machine_id)
          end
        end

        def connect_to_machine(machine_spec, machine_options)
          machine_for(machine_spec, machine_options)
        end
      end
    end
  end
end
