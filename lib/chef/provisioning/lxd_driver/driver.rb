require 'chef/provisioning/driver'
require 'chef/provisioning/transport/ssh'
require 'chef/provisioning/convergence_strategy/install_cached'
require 'chef/provisioning/machine/unix_machine'
require 'chef/provisioning/lxd_driver/version'
require 'nexussw/lxd/driver'

class Chef
  module Provisioning
    module LXDDriver
      class Driver < Chef::Provisioning::Driver
        def self.from_url(url, config)
          Driver.new(url, config)
        end

        def self.canonicalize_url(driver_url, config)
          _, url = driver_url.split(':', 2)
          address, port = url.split(',', 2) if url
          address = 'localhost' unless address
          port = 8443 unless port
          address = "https://#{address}:#{port}"
          ["lxd:#{address}", config]
        end

        def initialize(url, config)
          super(url, config)
          @lxd = NexusSW::LXD::Driver.new(host_address, clone_mash(driver_options['driver_options']))
        end

        def host_address()
          _, address = driver_url.split(':', 2)
          address
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

        def machine_for(machine_spec, machine_options)
          machine_id = machine_spec.reference['machine_id']
          transport = if host_address.start_with?('https://localhost:')
                        Chef::Provisioning::LXDDriver::LocalTransport.new(@lxd, machine_id)
                      else
                        username = machine_options['username']
                        ssh_options = {
                          auth_methods: ['publickey'],
                          keys: [get_private_key('bootstrapkey')],
                        }
                        Chef::Provisioning::Transport::SSH.new(@lxd.container_hostname(machine_id), username, ssh_options, {}, config)
                      end
          convergence_strategy = Chef::Provisioning::ConvergenceStrategy::InstallCached.new(machine_options['convergence_options'], {})
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
