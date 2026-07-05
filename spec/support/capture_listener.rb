# frozen_string_literal: true

require "socket"

module SpecSupport
  # A minimal, dependency-free HTTP listener on 127.0.0.1 that captures one
  # webhook delivery (request line + headers + Content-Length body). Used only
  # by the local webhook round-trip in the integration suite.
  class CaptureListener
    def initialize
      @server = TCPServer.new("127.0.0.1", 0)
      @deliveries = Queue.new
      @thread = Thread.new { accept_loop }
    end

    def url
      "http://127.0.0.1:#{@server.addr[1]}/hooks"
    end

    def wait_for_delivery(timeout:)
      deadline = Time.now + timeout
      loop do
        return @deliveries.pop(true) if @deliveries.length.positive?
        return nil if Time.now >= deadline

        sleep 0.1
      end
    rescue ThreadError
      nil
    end

    def close
      @thread&.kill
      @server.close unless @server.closed?
    end

    private

    def accept_loop
      loop do
        socket = @server.accept
        @deliveries << read_request(socket)
        socket.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
        socket.close
      end
    rescue IOError, Errno::EBADF
      # server closed
    end

    def read_request(socket)
      headers = {}
      socket.gets # request line
      while (line = socket.gets) && line != "\r\n"
        name, value = line.chomp.split(": ", 2)
        headers[name.downcase] = value if value
      end
      length = headers["content-length"].to_i
      body = length.positive? ? socket.read(length) : ""
      { headers: headers, body: body }
    end
  end
end
