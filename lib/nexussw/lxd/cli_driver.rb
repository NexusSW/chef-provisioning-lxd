require 'nexussw/lxd/driver'
require 'chef/provisioning/transport/ssh'

class NexusSW
  module LXD
    class CLIDriver < Driver
      

      def create_container(container_name, container_options)
        container_id = "#{hostname}:#{container_name}" if @canremote
        container_id ||= container_name
      end

      def start_container(container_id)
        raise 'NexusSW::LXD::Driver.start_container not implemented'
      end

      def stop_container(container_id)
        raise 'NexusSW::LXD::Driver.stop_container not implemented'
      end

      def delete_container(container_id)
        raise 'NexusSW::LXD::Driver.delete_container not implemented'
      end

      def container_status(container_id)
        raise 'NexusSW::LXD::Driver.container_status not implemented'
      end

      def ensure_profiles(profiles = {})
        raise 'NexusSW::LXD::Driver.ensure_profiles not implemented'
      end

      def container(container_id)
        raise 'NexusSW::LXD::Driver.container not implemented'
      end
    end
  end
end