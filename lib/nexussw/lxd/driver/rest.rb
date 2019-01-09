require "nexussw/lxd/driver"
require "hyperkit"

class NexusSW
  module LXD
    class Driver
      class Rest < Driver
        def initialize(rest_endpoint, driver_options)
          hkoptions = {}
          hkoptions = driver_options.clone if driver_options
          hkoptions[:api_endpoint] = rest_endpoint
          hkoptions[:auto_sync] = true
          @hk = Hyperkit::Client.new(hkoptions)
          @waitlist = []
        end

        attr_reader :hk

        def waitforserver(container_name)
          mylist = @waitlist.clone
          @waitlist -= mylist
          mylist.each do |v|
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
          end
        end

        def waitforstatus(container_id, newstatus)
          loop do
            status = container_status(container_id)
            break if status == newstatus
            sleep 0.5
          end
        end

        # TODO: that's the last of the async code - we can factor out the rest of the sync junk above.  nice try
        def create_container(container_name, container_options = {})
          return if container_exists?(container_name)
          @hk.create_container(container_name, container_options)
          # start_container_async container_name
          container_name
        end

        def start_container_async(container_id)
          @waitlist << { id: @hk.start_container(container_id, sync: false).id, name: container_id, wait: "running" }
        end

        def start_container(container_id)
          waitforserver container_id
          return if container_status(container_id) == "running"
          @hk.start_container(container_id)
          waitforstatus container_id, "running"
        end

        def stop_container(container_id)
          waitforserver container_id
          return if container_status(container_id) == "stopped"
          @hk.stop_container(container_id)
          waitforstatus container_id, "stopped"
        end

        def delete_container(container_id)
          waitforserver container_id
          return unless container_exists? container_id
          @hk.stop_container(container_id, force: true)
          waitforstatus container_id, "stopped"
          @hk.delete_container(container_id)
        end

        def container_status(container_id)
          waitforserver container_id
          STATUS_CODES[@hk.container_state(container_id)["status_code"].to_i]
        end

        def ensure_profiles(profiles = {})
          return unless profiles
          profile_list = @hk.profiles
          profiles.each do |name, profile|
            @hk.create_profile name, profile unless profile_list.index name
          end
        end

        def container(container_id)
          waitforserver container_id
          @hk.container container_id
        end
      end
    end
  end
end
