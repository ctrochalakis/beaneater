require 'yaml'

module Beaneater
  class Connection
    attr_reader :telnet_connection, :address, :host, :port

    DEFAULT_PORT = 11300

    # @beaneater_connection = Beaneater::Connection.new(['localhost:11300'])
    def initialize(address)
      @address = address
      @telnet_connection = establish_connection
      @mutex = Mutex.new
    end

    # transmit("stats", :match => /\n/) { |r| puts r }
    def transmit(command, options={}, &block)
      @mutex.lock
      if telnet_connection
        options.merge!("String" => command, "FailEOF" => true)
        parse_response(command, telnet_connection.cmd(options, &block))
      else # no telnet_connection
        raise NotConnected, "Connection to beanstalk '#{@host}:#{@port}' is closed!" unless telnet_connection
      end
    ensure
      @mutex.unlock
    end

    # Closes the beanstalk connection
    def close
      @telnet_connection.close
      @telnet_connection = nil
    end

    def to_s
      "#<Beaneater::Connection host=#{host.inspect} port=#{port.inspect}>"
    end
    alias :inspect :to_s

    protected

    # Establish a telnet connection based on beanstalk address.
    #
    # @return [Net::Telnet] telnet connection for specified address.
    # @raise [Beanstalk::NotConnected] Could not connect to specified beanstalkd instance.
    # @example
    #  establish_connection('localhost:3005')
    #
    def establish_connection
      @match = address.split(':')
      @host, @port = @match[0], Integer(@match[1] || DEFAULT_PORT)
      Net::Telnet.new('Host' => @host, "Port" => @port, "Prompt" => /\n/)
    rescue Errno::ECONNREFUSED => e
      raise NotConnected, "Could not connect to '#{@host}:#{@port}'"
    rescue Exception => ex
      raise NotConnected, "#{ex.class}: #{ex}"
    end

    # Parses the telnet response and returns the useful beanstalk response.
    #
    # @param [String] cmd Beanstalk command transmitted
    # @param [String] res Telnet command response
    # @return [Hash] Beanstalk command response with `status`, `id`, `body`, and `connection`
    # @raise [Beaneater::UnexpectedResponse] Response from beanstalk command was an error status
    # @example
    #  parse_response("delete 56", "DELETED 56\nFOO")
    #   # => { :body => "FOO", :status => "DELETED", :id => 56, :connection => <Connection>  }
    #
    def parse_response(cmd, res)
      res_lines = res.split(/\r?\n/)
      status = res_lines.first
      status, id = status.scan(/\w+/)
      raise UnexpectedResponse.from_status(status, cmd) if UnexpectedResponse::ERROR_STATES.include?(status)
      response = { :status => status, :body => YAML.load(res_lines[1..-1].join("\n")) }
      response[:id] = id if id
      response[:connection] = self
      response
    end
  end # Connection
end # Beaneater