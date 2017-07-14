require 'hyperkit'

class NexusSW
  module LXD
    class Driver
      def initialize(host_address, options)
        hkoptions = options.clone
        hkoptions[:api_endpoint] = host_address
        hkoptions[:auto_sync] = true
        @lxd = Hyperkit::Client.new(hkoptions)
        @waitlist = []
        @status_map = {
          100	=> 'created', # 'created',
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
      end

      def waitforserver()
        mylist = @waitlist.clone
        @waitlist -= mylist
        mylist.each { |id|
          begin
            @lxd.wait_for_operation(id)
          rescue
            nil
          end
        }
      end

      def waitforstatus(container_id, newstatus)
        loop do
          status = container_status(container_id)
          break if status == newstatus
          sleep 0.5
        end
      end

      # Finish ASAP - just as soon as we can get the id
      def create_container(container_name, container_options)
        # to date, these parameters are formatted and passed through to us by chef provisioning
        # I need to return container_id and i own that value

        # TODO: the rest of my functions take a single container_id.  We should factor out a container class
        # someday - for now, it would over complicate things

        hkoptions = {}
        hkoptions = container_options.clone if container_options
        hkoptions[:sync] = false
        @waitlist << @lxd.create_container(container_name, hkoptions).id
        container_name
      end

      # Quick Blind fire - don't wait -  don't error - success is optional
      def start_container_async(container_id)
        @waitlist << @lxd.start_container(container_id, sync: false).id
      end

      def start_container(container_id)
        waitforserver
        @lxd.start_container(container_id)
        waitforstatus container_id, 'running'
      end

      def stop_container(container_id)
        waitforserver
        @lxd.stop_container(container_id)
        waitforstatus container_id, 'stopped'
      end

      def delete_container(container_id)
        waitforserver
        @lxd.stop_container(container_id, force: true)
        @lxd.delete_container(container_id)
      end

      def container_exists?(container_id)
        true if container_status(container_id)
      rescue
        false
      end

      def container_status(container_id)
        waitforserver
        map_statuscode @lxd.container_state(container_id)['status_code']
      end

      def container_hostname(container_id)
        container_id
      end

      def map_statuscode(status_code)
        # TODO: could break this off into its own class as well
        @status_map[status_code.to_i]
      end
    end
  end
end
