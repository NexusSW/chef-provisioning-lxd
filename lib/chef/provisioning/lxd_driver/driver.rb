require 'chef'
require 'chef/provisioning'
require 'chef/provisioning/driver'
require 'chef/provisioning/convergence_strategy/install_cached'
require 'chef/provisioning/machine/unix_machine'
require 'chef/provisioning/lxd_driver/version'
require 'chef/provisioning/lxd_driver/transport_strategy'

class Chef
  module Provisioning
    module LXDDriver
      class Driver < Chef::Provisioning::Driver
        def self.from_url(url, config)
          Driver.new(url, config)
        end

        # Port is optional and indicates the expected availability of the rest api
        # If port is not specified, the CLI will be used and thus requires a transport if not localhost
        def self.canonicalize_url(driver_url, config)
          _, address, port = driver_url.split(':', 3)
          address ||= 'localhost'
          # port ||= 8443
          retval = "lxd:#{address}"
          retval += ':' + port if port
          [retval, config]
        end

        def initialize(url, config)
          super(url, config)
          @transport_strategy = TransportStrategy.new(self, config)
          @nx_driver = @transport_strategy.host_driver
        end

        attr_reader :nx_driver, :transport_strategy

        def to_hash(mash)
          retval = {}
          mash.each { |k, v| retval[k.to_sym] = v }
          retval
        end

        def allocate_machine(action_handler, machine_spec, machine_options)
          machine_id = nil
          if machine_spec.reference
            machine_id = machine_spec.reference['machine_id']
            unless nx_driver.container_exists?(machine_id)
              # It doesn't really exist
              action_handler.perform_action "Container #{machine_id} does not really exist.  Recreating ..." do
                machine_id = nil
                machine_spec.reference = nil
              end
            end
          end
          return if machine_id
          action_handler.perform_action "Creating container #{machine_spec.name} with options #{machine_options}" do
            raise "Container #{machine_spec.name} already exists" if nx_driver.container_exists?(machine_spec.name)
            machine_id = nx_driver.create_container(machine_spec.name, to_hash(machine_options))
            machine_spec.reference = {
              'driver_url' => driver_url,
              'driver_version' => LXDDriver::VERSION,
              'machine_id' => machine_id,
            }
          end
        end

        def ready_machine(action_handler, machine_spec, machine_options)
          machine_id = machine_spec.reference['machine_id']

          unless nx_driver.container_status(machine_id) == 'running'
            action_handler.perform_action "Starting container #{machine_id}" do
              nx_driver.start_container(machine_id)
            end
          end

          # Return the Machine object
          connect_to_machine(machine_spec, machine_options)
        end

        def connect_to_machine(machine_spec, machine_options)
          machine_id = machine_spec.reference['machine_id']
          transport = @transport_strategy.guest_transport(machine_id, machine_options)
          convergence_strategy = Chef::Provisioning::ConvergenceStrategy::InstallCached.new(machine_options['convergence_options'] || {}, config)
          Chef::Provisioning::Machine::UnixMachine.new(machine_spec, transport, convergence_strategy)
        end

        def destroy_machine(action_handler, machine_spec, _machine_options)
          return unless machine_spec.reference
          machine_id = machine_spec.reference['machine_id']
          action_handler.perform_action "Destroy container #{machine_id}" do
            nx_driver.delete_container(machine_id)
            machine_spec.reference = nil
          end
        end

        def stop_machine(action_handler, machine_spec, _machine_options)
          return unless machine_spec.reference
          machine_id = machine_spec.reference['machine_id']
          action_handler.perform_action "Stopping container #{machine_id}" do
            nx_driver.stop_container(machine_id)
          end
        end
      end
    end
  end
end
