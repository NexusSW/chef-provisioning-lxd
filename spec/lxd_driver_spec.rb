require 'spec_helper'

# Prerequisites: 
#   - LXD must be installed locally and listening on the default port
#   - must have cert and key installed in .config/lxd/ by default,
#       or otherwise specified in this constructor

describe 'Chef Provisioning LXD Driver' do
  let(:test_name) { 'lxd-chef-driver-test' }
  let(:lxd) { NexusSW::LXD::Driver.new 'https://localhost:8443', verify_ssl: false }
  context 'Core Implementation' do
    it 'has a version number' do
      expect(NexusSW::LXD::VERSION).not_to be nil
    end

    it 'detects a missing container' do
      expect(lxd.container_exists?('idontexist')).not_to be true
    end

    it 'creates a container' do
      expect(lxd.create_container(test_name, alias: 'ubuntu-14.04')).to be test_name
    end

    it 'detects an existing container' do
      expect(lxd.container_exists?(test_name)).to be true
    end

    it 'can start a container asyncronously' do
      expect(lxd.start_container_async(test_name))
    end

    it 'can stop a container that is not yet running' do
      lxd.stop_container test_name
      expect(lxd.container_status(test_name)).to eq 'stopped'
    end

    it 'can start a container normally' do
      lxd.start_container test_name
      expect(lxd.container_status(test_name)).to eq 'running'
    end

    it 'can delete a running container' do
      lxd.delete_container test_name
      expect(lxd.container_exists?(test_name)).to be false
    end
  end
end
