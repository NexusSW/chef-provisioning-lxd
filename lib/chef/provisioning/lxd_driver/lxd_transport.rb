require 'chef/provisioning/transport'

class Chef
  module Provisioning
    module LXDDriver
      class LXDTransport < Chef::Provisioning::Transport
        def initialize(driver, container_name, config = {})
          @lxd = driver
          @container_name = container_name
          @config = config
        end

        attr_reader :lxd, :container_name, :config

        def execute(_command, _options = {})
          raise 'LXDTransport.execute not overidden'
        end

        def remote?(host_name)
          result = execute 'list', subcommand: 'remote'
          result.error!
          result.stdout.each_line do |line|
            return true if line.start_with? "| #{host_name} "
          end
          false
        end

        def add_remote(host_name)
          execute("add #{host_name} --accept-certificate", subcommand: 'remote').error! unless remote? host_name
        end

        class LXDExecuteResult
          def initialize(command, stdout, stderr, exitstatus)
            @command = command
            @stdout = stdout
            @stderr = stderr
            @exitstatus = exitstatus
          end

          attr_reader :exitstatus, :stdout, :stderr

          def error!
            raise "Error: '#{@command}' failed with exit code #{@exitstatus}.\nSTDOUT:#{@stdout}\nSTDERR:#{@stderr}" if @exitstatus != 0
          end
        end

        def make_url_available_to_remote(local_url)
          @forwards = [] unless @forwards
          uri = URI(local_url)
          uri_scheme = uri.scheme unless uri.scheme == 'chefzero'
          host = Socket.getaddrinfo(uri.host, uri_scheme, nil, :STREAM)[0][3]
          new_url = local_url

          if host == '127.0.0.1' || host == '::1'
            host_adapters = lxd.container(container_name)[:expanded_devices].select do |_k, v|
              v[:type] == 'nic'
            end
            raise 'Unable to determine which Host Adapter #{container_name} is connected to' if host_adapters.empty?
            host_adapters = host_adapters.map { |_k, v| v[:parent] }
            raise 'Unable to determine which Host Adapter #{container_name} is connected to' unless host_adapters.any?
            ifaddrs = Socket.getifaddrs.select do |iface|
              host_adapters.index(iface.name) && iface.addr.ip?
            end
            raise "Unable to get the IP address of any connected Host Adapter: #{host_adapters}" if ifaddrs.empty?
            uri.host = ifaddrs.first.addr.ip_address

            return uri.to_s if @forwards[uri.port]

            logger = Logger.new(STDERR)
            logger.level = Logger::ERROR
            @forwards[uri.port] = Thread.start do
              Thread.current.abort_on_exception = true
              server = TCPServer.new uri.host, uri.port
              proxy = SurroGate::Proxy.new logger
              loop do
                container_conn = server.accept
                server_conn = TCPSocket.new '127.0.0.1', uri.port
                proxy.push container_conn, server_conn
              end
              @forwards.delete[uri.port]
            end
            new_url = uri.to_s
          end

          new_url
        end

        def disconnect
          # puts 'should disconnect now...'
        end
      end
    end
  end
end
