require 'chef/mash'
require 'chef/provisioning/transport'
require 'open3'
require 'nexussw/lxd/driver'
require 'tempfile'
require 'socket'
require 'stringio'
require 'bundler'
require 'surro-gate/lib/surro-gate/proxy'

class Chef
  module Provisioning
    module LXDDriver
      class LocalTransport < Chef::Provisioning::Transport
        def initialize(driver, container_name)
          @container_name = container_name
          @lxd = driver
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
        def execute(command, options = {})
          stream_options = options.clone
          mycommand = command
          mycommand = command.join(' ') if command.is_a?(Array)
          subcommand = stream_options[:subcommand] || "exec #{@container_name} --"
          mycommand = "lxc #{subcommand} #{mycommand}"
          unless stream_options[:stream]
            stream_options[:stdout] = '' # StringIO.new
            stream_options[:stderr] = '' # StringIO.new
            stream_options[:stream] = lambda do |sout, serr|
              stream_options[:stdout] += sout if sout
              stream_options[:stderr] += serr if serr
            end
          end

          with_execute_timeout(stream_options) do
            Open3.popen3(mycommand) do |_stdin, stdout, stderr, th|
              streams = [stdout, stderr]
              loop do
                begin
                  stdout_chunk = stdout.read_nonblock 1024 unless stdout.eof?
                rescue IO::WaitReadable
                  IO.select streams, nil, streams, 1
                end
                begin
                  stderr_chunk = stderr.read_nonblock 1024 unless stderr.eof?
                rescue IO::WaitReadable
                  IO.select streams, nil, streams, 1 unless stdout_chunk
                end
                stream_chunk stream_options, stdout_chunk, stderr_chunk
                return LXDExecuteResult.new(mycommand, stream_options[:stdout], stream_options[:stderr], th.value.exitstatus) if th.value.exited? && stdout.eof? && stderr.eof?
              end
            end
          end
        end

        def read_file(path)
          tfile = Tempfile.new(@container_name)
          tfile.close
          retval = execute("#{@container_name}#{path} #{tfile.path}", subcommand: 'file pull')
          return '' if retval.exitstatus == 1
          retval.error!
          tfile.open
          content = tfile.read
          tfile.close
          tfile.unlink

          content
        end

        def write_file(path, content)
          tfile = Tempfile.new(@container_name)
          tfile.write content
          tfile.close
          upload_file tfile.path, path
          tfile.unlink
        end

        def download_file(path, local_path)
          execute("#{@container_name}#{path} #{local_path}", subcommand: 'file pull').error!
        end

        def upload_file(local_path, path)
          execute("#{local_path} #{@container_name}#{path}", subcommand: 'file push').error!
        end

        def make_url_available_to_remote(local_url)
          @forwards = [] unless @forwards
          uri = URI(local_url)
          uri_scheme = uri.scheme unless uri.scheme == 'chefzero'
          host = Socket.getaddrinfo(uri.host, uri_scheme, nil, :STREAM)[0][3]
          new_url = local_url

          if host == '127.0.0.1' || host == '::1'
            host_adapters = @lxd.lxd.container(@container_name)[:expanded_devices].select do |_k, v|
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

        def available?
          @lxd.container_status(@container_name) == 'running'
        end

        # Config hash, including :log_level and :logger as keys
        def config
          {}
        end
      end
    end
  end
end
