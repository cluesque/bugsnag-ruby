require "set"
require "socket"
require "logger"
require "bugsnag/middleware_stack"
require "bugsnag/middleware/callbacks"
require "bugsnag/middleware/exception_meta_data"
require "bugsnag/middleware/ignore_error_class"
require "bugsnag/middleware/suggestion_data"
require "bugsnag/middleware/classify_error"
require "bugsnag/middleware/session_data"

module Bugsnag
  class Configuration
    attr_accessor :api_key
    attr_accessor :release_stage
    attr_accessor :notify_release_stages
    attr_accessor :auto_notify
    attr_accessor :ca_file
    attr_accessor :send_environment
    attr_accessor :send_code
    attr_accessor :project_root
    attr_accessor :app_version
    attr_accessor :app_type
    attr_accessor :meta_data_filters
    attr_accessor :endpoint
    attr_accessor :logger
    attr_accessor :middleware
    attr_accessor :internal_middleware
    attr_accessor :proxy_host
    attr_accessor :proxy_port
    attr_accessor :proxy_user
    attr_accessor :proxy_password
    attr_accessor :timeout
    attr_accessor :hostname
    attr_accessor :ignore_classes
    attr_accessor :auto_capture_sessions
    attr_accessor :track_sessions
    attr_accessor :session_endpoint

    API_KEY_REGEX = /[0-9a-f]{32}/i
    THREAD_LOCAL_NAME = "bugsnag_req_data"
    DEFAULT_ENDPOINT = "https://notify.bugsnag.com"
    DEFAULT_SESSION_ENDPOINT = "https://sessions.bugsnag.com"

    DEFAULT_META_DATA_FILTERS = [
      /authorization/i,
      /cookie/i,
      /password/i,
      /secret/i,
      "rack.request.form_vars"
    ].freeze

    alias :track_sessions :auto_capture_sessions
    alias :track_sessions= :auto_capture_sessions=

    def initialize
      @mutex = Mutex.new

      # Set up the defaults
      self.auto_notify = true
      self.send_environment = false
      self.send_code = true
      self.meta_data_filters = Set.new(DEFAULT_META_DATA_FILTERS)
      self.endpoint = DEFAULT_ENDPOINT
      self.hostname = default_hostname
      self.timeout = 15
      self.notify_release_stages = nil
      self.auto_capture_sessions = false
      self.session_endpoint = DEFAULT_SESSION_ENDPOINT

      # SystemExit and Interrupt are common Exception types seen with successful
      # exits and are not automatically reported to Bugsnag
      self.ignore_classes = Set.new([SystemExit, Interrupt])

      # Read the API key from the environment
      self.api_key = ENV["BUGSNAG_API_KEY"]

      # Read NET::HTTP proxy environment variable
      self.proxy_host = ENV["http_proxy"]

      # Set up logging
      self.logger = Logger.new(STDOUT)
      self.logger.level = Logger::INFO
      self.logger.formatter = proc do |severity, datetime, progname, msg|
        "** [Bugsnag] #{datetime}: #{msg}\n"
      end

      # Configure the bugsnag middleware stack
      self.internal_middleware = Bugsnag::MiddlewareStack.new
      self.internal_middleware.use Bugsnag::Middleware::ExceptionMetaData
      self.internal_middleware.use Bugsnag::Middleware::IgnoreErrorClass
      self.internal_middleware.use Bugsnag::Middleware::SuggestionData
      self.internal_middleware.use Bugsnag::Middleware::ClassifyError
      self.internal_middleware.use Bugsnag::Middleware::SessionData

      self.middleware = Bugsnag::MiddlewareStack.new
      self.middleware.use Bugsnag::Middleware::Callbacks
    end

    ##
    # Gets the delivery_method that Bugsnag will use to communicate with the
    # notification endpoint.
    #
    def delivery_method
      @delivery_method || @default_delivery_method || :thread_queue
    end

    ##
    # Sets the delivery_method that Bugsnag will use to communicate with the
    # notification endpoint.
    #
    def delivery_method=(delivery_method)
      @delivery_method = delivery_method
    end

    ##
    # Used to set a new default delivery method that will be used if one is not
    # set with #delivery_method.
    #
    def default_delivery_method=(delivery_method)
      @default_delivery_method = delivery_method
    end

    def should_notify_release_stage?
      @release_stage.nil? || @notify_release_stages.nil? || @notify_release_stages.include?(@release_stage)
    end

    def valid_api_key?
      !api_key.nil? && api_key =~ API_KEY_REGEX
    end

    def request_data
      Thread.current[THREAD_LOCAL_NAME] ||= {}
    end

    def set_request_data(key, value)
      self.request_data[key] = value
    end

    def unset_request_data(key, value)
      self.request_data.delete(key)
    end

    def clear_request_data
      Thread.current[THREAD_LOCAL_NAME] = nil
    end

    def info(message)
      logger.info(message)
    end

    # Warning logger
    def warn(message)
      logger.warn(message)
    end

    # Debug logger
    def debug(message)
      logger.debug(message)
    end

    private

    def default_hostname
      # Send the heroku dyno name instead of hostname if available
      ENV["DYNO"] || Socket.gethostname;
    end
  end
end
