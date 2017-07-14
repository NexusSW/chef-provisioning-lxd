require 'chef/provisioning/driver'
require 'chef/provisioning/transport/ssh_transport'
require 'chef/provisioning/convergence_strategy/install_cached'
require 'chef/provisioning/machine/unix_machine'
require 'nexussw/lxd/driver'

class Chef
  module Provisioning
    module LXDDriver
      class Driver < Chef::Provisioning::Driver
        def self.from_url(url, config)
          Driver.new(url, config)
        end

        def initialize(url, config)
          super(url, config)
          @lxd = NexusSW::LXD::Driver.new(host_address, config)
        end

        def host_address
          _, url = driver_url.split(':', 2)
          address, port = url.split(',', 2)
          address = 'localhost' unless address
          port = 8443 unless port
          address = "https://#{address}:#{port}"
          address
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
              machine_id = @lxd.create_container(machine_spec.name, machine_options)
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
          server_id = machine_spec.reference['server_id']
          if @lxd.container_status(server_id) == 'stopped'
            action_handler.perform_action "Starting container #{server_id}" do
              @lxd.start_container_async(server_id)
            end
          end

          unless @lxd.container_status(server_id) == 'running'
            action_handler.perform_action "Waiting for container #{server_id}" do
              @lxd.start_container(server_id)
            end
          end

          # Return the Machine object
          machine_for(machine_spec, machine_options)
        end

        def machine_for(machine_spec, machine_options)
          server_id = machine_spec.reference['server_id']
          username = machine_options['username']
          ssh_options = {
            auth_methods: ['publickey'],
            keys: [get_private_key('bootstrapkey')],
          }
          transport = Chef::Provisioning::Transport::SSH.new(@lxd.container_hostname(server_id), username, ssh_options, {}, config)
          convergence_strategy = Chef::Provisioning::ConvergenceStrategy::InstallCached.new(machine_options[:convergence_options], {})
          Chef::Provisioning::Machine::UnixMachine.new(machine_spec, transport, convergence_strategy)
        end

        def destroy_machine(action_handler, machine_spec, _machine_options)
          return unless machine_spec.reference
          server_id = machine_spec.reference['server_id']
          action_handler.perform_action "Destroy container #{server_id}" do
            @lxd.delete_container(server_id)
            machine_spec.reference = nil
          end
        end

        def stop_machine(action_handler, machine_spec, _machine_options)
          return unless machine_spec.reference
          server_id = machine_spec.reference['server_id']
          action_handler.perform_action "Stopping container #{server_id}" do
            @lxd.stop_container(server_id)
          end
        end

        def connect_to_machine(machine_spec, machine_options)
          machine_for(machine_spec, machine_options)
        end
      end
    end
  end
end
