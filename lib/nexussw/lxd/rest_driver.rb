require 'hyperkit'
require 'nexussw/lxd/driver'

class NexusSW
  module LXD
    class RestDriver < Driver
      def initialize(host_address, options = {})
        hkoptions = {}
        hkoptions = options.clone if options
        hkoptions[:api_endpoint] = host_address
        hkoptions[:auto_sync] = true
        @hk = Hyperkit::Client.new(hkoptions)
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

      def waitforserver(container_name)
        mylist = @waitlist.clone
        @waitlist -= mylist
        mylist.each { |v|
          begin
            @hk.wait_for_operation(v[:id]) if v[:id]
            if v[:name] == container_name && v[:wait]
              waitforstatus v[:name], v[:wait]
            elsif v[:name] && v[:wait]
              v.delete :id
              @waitlist << v
            end
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
        # hkoptions[:sync] = false    # I finally hit the race condition after a couple of days
        #@waitlist << { id: @hk.create_container(container_name, hkoptions).id }
        @hk.create_container(container_name, hkoptions)
        start_container_async container_name
        container_name
      end

      # Quick Blind fire - don't wait -  don't error - success is optional
      def start_container_async(container_id)
        @waitlist << { id: @hk.start_container(container_id, sync: false).id, name: container_id, wait: 'running' }
      end

      def start_container(container_id)
        waitforserver container_id
        @hk.start_container(container_id)
        waitforstatus container_id, 'running'
      end

      def stop_container(container_id)
        waitforserver container_id
        @hk.stop_container(container_id)
        waitforstatus container_id, 'stopped'
      end

      def delete_container(container_id)
        waitforserver container_id
        @hk.stop_container(container_id, force: true)
        waitforstatus container_id, 'stopped'
        @hk.delete_container(container_id)
      end

      def container_status(container_id)
        waitforserver container_id
        map_statuscode @hk.container_state(container_id)['status_code']
      end

      def map_statuscode(status_code)
        # TODO: could break this off into its own class as well
        @status_map[status_code.to_i]
      end

      def ensure_profiles(profiles = {})
        return unless profiles
        profile_list = @hk.profiles
        profiles.each do |name, profile|
          @hk.create_profile name, profile unless profile_list.index name
        end
      end

      def container(container_id)
        @hk.container container_id
      end
    end
  end
end
