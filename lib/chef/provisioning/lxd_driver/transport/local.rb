require 'chef/provisioning/lxd_driver/transport'
require 'open3'

class Chef
  module Provisioning
    module LXDDriver
      class Transport
        class Local < Transport
          def initialize(config = {})
            super self, 'local:', config
          end

          def execute(command, options = {})
            with_streamoptions(options) do |stream_options|
              Open3.popen3(command) do |_stdin, stdout, stderr, th|
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
                  return LXDExecuteResult.new(command, stream_options, th.value.exitstatus) if th.value.exited? && stdout.eof? && stderr.eof?
                end
              end
            end
          end

          def read_file(path)
            File.open path, &:read
          end

          def write_file(path, content)
            File.open path, 'w' do |f|
              f.write content
            end
          end

          def make_url_available_to_remote(local_url)
            local_url
          end
        end
      end
    end
  end
end
