require 'chef/provisioning/transport'
require 'surro-gate/lib/surro-gate/proxy'
require 'socket'

class Chef
  module Provisioning
    module LXDDriver
      class Transport < Chef::Provisioning::Transport
        def initialize(driver, container_name, config = {})
          @lxd = driver
          @container_name = container_name
          @config = config
        end

        attr_reader :lxd, :container_name, :config

        class LXDExecuteResult
          def initialize(command, stream_options, exitstatus)
            @command = command
            @stream_options = stream_options
            @exitstatus = exitstatus
          end

          attr_reader :exitstatus, :stream_options

          def stdout
            stream_options[:stream_stdout] || stream_options[:stdout]
          end

          def stderr
            stream_options[:stream_stderr] || stream_options[:stderr]
          end

          def error!
            raise "Error: '#{@command}' failed with exit code #{@exitstatus}.\nSTDOUT:#{@stdout}\nSTDERR:#{@stderr}" if @exitstatus != 0
          end
        end

        # Execute a program on the remote host.
        #
        # == Arguments
        # command: command to run.  May be a shell-escaped string or a pre-split
        #          array containing [PROGRAM, ARG1, ARG2, ...].
        # options: hash of options, including but not limited to:
        #          :timeout => NUM_SECONDS - time to wait before program finishes
        #                      (throws an exception otherwise).  Set to nil or 0 to
        #                      run with no timeout.  Defaults to 15 minutes.
        #          :stream => BOOLEAN - true to stream stdout and stderr to the console.
        #          :stream => BLOCK - block to stream stdout and stderr to
        #                     (block.call(stdout_chunk, stderr_chunk))
        #          :stream_stdout => FD - FD to stream stdout to (defaults to IO.stdout)
        #          :stream_stderr => FD - FD to stream stderr to (defaults to IO.stderr)
        #          :read_only => BOOLEAN - true if command is guaranteed not to
        #                        change system state (useful for Docker)
        def with_streamoptions(options = {}, &_)
          stream_options = options.clone || {}
          unless (stream_options[:stream_stdout] && stream_options[:stream_stderr]) || stream_options[:stream]
            stream_options[:stdout] = '' # StringIO.new
            stream_options[:stderr] = '' # StringIO.new
            stream_options[:stream] = lambda do |sout, serr|
              stream_options[:stdout] += sout if sout
              stream_options[:stderr] += serr if serr
            end
          end

          with_execute_timeout(stream_options) do
            yield(stream_options)
          end
        end

        def linked_transport(_host_name)
          nil
        end

        def remote?(_host_name)
          false
        end

        def available?
          lxd.container_status(container_name) == 'running'
        end

        def make_url_available_to_remote(local_url)
          @forwards = {} unless @forwards
          uri = URI(local_url)
          uri_scheme = uri.scheme unless uri.scheme == 'chefzero'
          host = Socket.getaddrinfo(uri.host, uri_scheme, nil, :STREAM)[0][3]
          new_uri = uri

          if host == '127.0.0.1' || host == '::1'

            new_uri.host = host_ip

            return new_uri.to_s if @forwards[new_uri.to_s]

            begin
              server = TCPServer.new new_uri.host, new_uri.port
            rescue
              server = TCPServer.new new_uri.host, 0
              new_uri.port = server.local_address.ip_port
            end

            @forwards[new_uri.to_s] = Thread.start do
              begin
                Thread.current.abort_on_exception = true
                proxy = SurroGate::Proxy.new config[:logger]
                loop do
                  container_conn = server.accept
                  server_conn = TCPSocket.new host, uri.port
                  proxy.push container_conn, server_conn
                end
              ensure
                @forwards.delete[new_uri.to_s]
              end
            end
          end

          new_uri.to_s
        end

        def disconnect
          @forwards.each do |_url, th|
            th.kill
          end
          @forwards = {}
        end

        protected

        def host_ip
          host_adapters = lxd.container(container_name)[:expanded_devices].select do |_k, v|
            v[:type] == 'nic'
          end
          raise "Unable to determine which Host Adapter #{container_name} is connected to" if host_adapters.empty?
          host_adapters = host_adapters.map { |_k, v| v[:parent] }
          raise "Unable to determine which Host Adapter #{container_name} is connected to" unless host_adapters.any?
          ifaddrs = Socket.getifaddrs.select do |iface|
            host_adapters.index(iface.name) && iface.addr.ip?
          end
          raise "Unable to get the IP address of any connected Host Adapter: #{host_adapters}" if ifaddrs.empty?
          ifaddrs.first.addr.ip_address
        end
      end
    end
  end
end
