require 'hyperkit'

class NexusSW
  module LXD
    class Driver
      def initialize(host_address, options)
        hkoptions = options.clone
        hkoptions.api_endpoint = host_address
        @lxd = Hyperkit::Client.new(hkoptions)
      end

      # Finish ASAP - just as soon as we can get the id
      def create_container(container_name, container_options)
        # to date, these parameters are formatted and passed through to us by chef provisioning
        # I need to return container_id and i own that value

        # TODO: the rest of my functions take a single container_id.  We should factor out a container class
        # someday - for now, it would over complicate things

        hkoptions = container_options.clone
        hkoptions.sync = false
        @lxd.create_container(container_name, hkoptions)
        container_name
      end

      # Quick Blind fire - don't wait -  don't error - success is optional
      def start_container_async(container_id)
        @lxd.start_container(container_id, sync: false)
      end

      def start_container(container_id)
        @lxd.start_container(container_id)
      end

      def stop_container(container_id)
        @lxd.stop_container(container_id)
      end

      def delete_container(container_id)
        @lxd.stop_container(container_id, force: true)
        @lxd.delete_container(container_id)
      end

      def container_exists?(container_id)
        container_status(container_id)
      rescue
        nil
      end

      def container_status(container_id)
        map_statuscode @lxd.container_state(container_id).metadata.status_code
      end

      def container_hostname(container_id)
        container_id
      end

      @status_map = {
        100	=> 'stopped', # 'created',
        101	=> 'started',
        102	=> 'stopped',
        103	=> 'running',
        104	=> 'cancelling',
        105	=> 'pending',
        106	=> 'starting',
        107	=> 'stopping',
        108	=> 'aborting',
        109	=> 'freezing',
        110	=> 'frozen',
        111	=> 'thawed',
        200	=> 'success',
        400	=> 'failure',
        401	=> 'cancelled',
      }.freeze
      def map_statuscode(status_code)
        # TODO: could break this off into its own class as well
        @status_map[status_code]
      end
    end
  end
end
