Hyperkit: Module or Instance level default options
    Hyperkit.api_endpoint = 'https://localhost:8443'
        overridable by ENV["ENV['HYPERKIT_API_ENDPOINT']
    Hyperkit.verify_ssl   = true
    Hyperkit.client_cert  = '~/.config/lxc/client.crt'
        overridable by ENV['HYPERKIT_CLIENT_CERT']
    Hyperkit.client_key   = '~/.config/lxc/client.key'
        overridable by ENV['HYPERKIT_KEY']
    Hyperkit.auto_sync    = true
        overridable by ENV['HYPERKIT_AUTO_SYNC']
    there are other overridables, but they are internal to HK

Settings Precedence:
    cookbook > chef > Driver > HK Instance > HK Module > Env > Default

LXD Driver
    - uses Hyperkit::Client instances and NOT HK Module calls
    - supplies and overrides api_endpoint as derived from the driver name
        format: 'lxd:localhost,8443' => 'https://localhost:8443'
    - accepts driver_options :verify_ssl, :client_cert, :client_key and passes them straight
        through to Hyperkit
    - will not pass through the unspecified HK configs
    - forces and manages auto_sync on it's own (no other settings will take hold)

---------------------
From http://www.rubydoc.info/github/jeffshantz/hyperkit/master/Hyperkit%2FClient%2FContainers:create_container

Machine Options:

:alias (String) — Alias of the source image. Either :alias, :fingerprint, :properties, or empty: true must be specified.
:architecture (String) — Architecture of the container (e.g. x86_64). By default, this will be obtained from the image metadata
:certificate (String) — PEM certificate to use to authenticate with the remote server. If not specified, and the source image is private, the target LXD server's certificate is used for authentication. This option is valid only when transferring an image from a remote server using the :server option.
:config (Hash) — Container configuration
:ephemeral (Boolean) — Whether to make the container ephemeral (i.e. delete it when it is stopped; default: false)
:empty (Boolean) — Whether to make an empty container (i.e. not from an image). Specifying true will cause LXD to create a container with no rootfs. That is, /var/lib/lxd/<container-name> will simply be an empty directly. One can then create a rootfs directory within this directory and populate it manually. This is useful when migrating LXC containers to LXD.
:fingerprint (String) — SHA-256 fingerprint of the source image. This can be a prefix of a fingerprint, as long as it is unambiguous. Either :alias, :fingerprint, :properties, or empty: true must be specified.
:profiles (Array) — List of profiles to be applied to the container (default: [])
:properties (String) — Properties of the source image. Either :alias, :fingerprint, :properties, or empty: true must be specified.
:protocol (String) — Protocol to use in transferring the image (lxd or simplestreams; defaults to lxd). This option is valid only when transferring an image from a remote server using the :server option.
:secret (String) — Secret to use to retrieve the image. This option is valid only when transferring an image from a remote server using the :server option.
:server (String) — URL of remote server from which to obtain image. By default, the image will be obtained from the client's api_endpoint.
:sync (Boolean) — If false, returns an asynchronous operation that must be passed to Operations#wait_for_operation. If true, automatically waits and returns the result of the operation. Defaults to value of Hyperkit::Configurable#auto_sync.

LXD Status Codes
from https://github.com/lxc/lxd/blob/master/doc/rest-api.md

100	Operation created
101	Started
102	Stopped
103	Running
104	Cancelling
105	Pending
106	Starting
107	Stopping
108	Aborting
109	Freezing
110	Frozen
111	Thawed
200	Success
400	Failure
401	Cancelled