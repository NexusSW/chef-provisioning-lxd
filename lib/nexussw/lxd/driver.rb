require 'nexussw/lxd/rest_driver'
require 'nexussw/lxd/cli_driver'

class NexusSW
  module LXD
    class Driver
      def self.new(address, options)
        _, host, port = address.split ':', 3
        return RestDriver.new("https://#{host}:#{port}", options) if port
        CLIDriver.new host, options
      end

      def create_container(_container_name, _container_options)
        raise 'NexusSW::LXD::Driver.create_container not implemented'
      end

      def start_container(_container_id)
        raise 'NexusSW::LXD::Driver.start_container not implemented'
      end

      def stop_container(_container_id)
        raise 'NexusSW::LXD::Driver.stop_container not implemented'
      end

      def delete_container(_container_id)
        raise 'NexusSW::LXD::Driver.delete_container not implemented'
      end

      def container_status(_container_id)
        raise 'NexusSW::LXD::Driver.container_status not implemented'
      end

      def ensure_profiles(_profiles)
        raise 'NexusSW::LXD::Driver.ensure_profiles not implemented'
      end

      def container(_container_id)
        raise 'NexusSW::LXD::Driver.container not implemented'
      end

      def container_exists?(container_id)
        return true if container_status(container_id)
        return false
      rescue
        false
      end

      def container_hostname(container_id)
        container_id
      end
    end
  end
end
