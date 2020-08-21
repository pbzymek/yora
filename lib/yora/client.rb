require 'thread'
require 'socket'

require_relative 'message'

module Yora
  MAX_RESPONSE_LEN = 65535
  TIME_OUT = 0.5

  class Client
    include Message

    def initialize(nodes)
      @sockets = {}
      nodes.each do |addr|
        @sockets[addr] = UDPSocket.new
      end
    end

    def leader
      request = serialize(message_type: :query, query: 'leader')

      @sockets.each do |addr, socket|
        $stderr.puts "sending #{request} to #{addr}"
        host, port = addr.split(':')
        len = socket.send(request, 0, host, port.to_i)
        $stderr.puts "#{len} bytes sent"
      end

      readable, _, _ = IO.select(@sockets.values, nil, nil, TIME_OUT)

      unless readable
        $stderr.puts "got nothing after #{TIME_OUT} secs"
        return
      end

      response = nil
      readable.each do |socket|
        response, _ = socket.recvfrom(MAX_RESPONSE_LEN)
        break
      end

      msg = deserialize(response)

      $stderr.puts "got #{msg}"

      [msg[:leader_id], msg[:leader_addr]]
    end

    def command(cmd, opts = {})
      $stderr.puts 'query leader'
      leader_id, leader_addr = leader

      if leader_id.nil? || leader_addr.nil?
        $stderr.puts 'unable to determine leader'
        return
      end

      send_request(leader_addr, { message_type: :command, command: cmd }.merge(opts))
    end

    def query(query)
      $stderr.puts 'query leader'
      _, leader_addr = leader
      send_request(leader_addr, message_type: :query, query: query) if leader_addr
    end

    def send_request(addr, request)
      $stderr.puts "sending #{request} to #{addr}"
      host, port = addr.split(':')
      socket = UDPSocket.new

      len = socket.send(serialize(request), 0, host, port.to_i)
      $stderr.puts "#{len} bytes sent, waiting for reply"

      readable, _, _ = IO.select([socket], nil, nil, TIME_OUT)

      unless readable
        $stderr.puts "got nothing after #{TIME_OUT} secs"
        return
      end

      response, _ = socket.recvfrom(MAX_RESPONSE_LEN)

      $stderr.puts "got '#{response}'"

      deserialize(response)
    end
  end
end
