require 'socket'
require 'json'

require_relative 'client'
require_relative 'message'

module Yora
  class Transmitter
    attr_reader :server

    def initialize(server)
      @server = server
    end

    def send_message(send_to, message_type, opts)
      opts[:send_to] = send_to
      opts[:peer] = @server.node.node_id
      opts[:message_type] = message_type

      if opts[:send_to] == @server.node.node_id

        $stderr.puts "send #{opts[:message_type]}, #{opts[:success]} to local"

        @server.in_queue << opts
      else
        $stderr.puts "send #{opts[:message_type]}, #{opts[:success]}, "\
          "prev index = #{opts[:prev_log_index]}, " \
          "prev term = #{opts[:prev_log_term]} to #{opts[:send_to]}"
        @server.out_queue << opts
      end
    end
  end

  class Timer
    def initialize(min, max)
      @min, @max = min, max
    end

    def next
      Time.now.to_f + @min + Random.rand(@max - @min)
    end
  end

  class Server
    include Message

    attr_reader :node, :in_queue, :out_queue, :sigterm
    attr_writer :debug

    CLIENT_MESSAGE_TYPE = %w(command heartbeat query)
    HEARTBEAT_TTL = Yora::TIME_OUT

    def initialize(node_id, node_address, handler, peers, second_per_tick = 2)
      @host, @port = node_address.split(':')
      @port = @port.to_i

      @peers = peers

      @second_per_tick = second_per_tick.to_f
      @in_queue = Queue.new
      @out_queue = Queue.new

      @transmitter = Transmitter.new(self)

      @persistence = Persistence::SimpleFile.new(node_id, node_address)

      snapshot = @persistence.read_snapshot

      @handler = handler

      @handler.restore(snapshot[:data])

      @timer = Timer.new(2 * @second_per_tick, 5 * @second_per_tick)

      @node = Node.new(node_id, @transmitter, @handler, @timer, @persistence, @second_per_tick)

      @node.cluster = peers.merge(@node.cluster)
    end

    def join
      client = Client.new(@peers.values)
      response = client.command(:join, peer: @node.node_id, peer_address: "#{@host}:#{@port}")
      $stderr.puts "-- got #{response}"

      if response
        node.cluster = response[:cluster]
        bootstrap
      else
        $stderr.puts 'unable to join existing cluster'
      end
    end

    def leave
      node.role.leave

      @sigterm = true
    end

    def bootstrap
      timer = Thread.new do
        timer_loop
      end

      receiver = Thread.new do
        receiver_loop
      end

      sender = Thread.new do
        sender_loop
      end

      heartbeat = Thread.new do
        heartbeat_loop
      end

      processor_loop

      [timer, receiver, sender, heartbeat].each(&:join)
    end

    def timer_loop
      loop do
        sleep @second_per_tick

        @in_queue << { message_type: :tick }
      end
    end

    def receiver_loop
      Socket.udp_server_loop(@host, @port) do |raw, socket|
        msg = deserialize(raw)

        if CLIENT_MESSAGE_TYPE.include?(msg[:message_type])
          addr = socket.remote_address
          msg[:client] = "#{addr.ip_address}:#{addr.ip_port}"
        end

        @in_queue << msg
      end
    rescue => ex
      $stderr.puts "error #{ex} in receiver thread"
      $stderr.puts ex.backtrace.join("\n")
      exit(2)
    end

    def sender_loop
      loop do
        while(msg = @out_queue.pop) do
          socket = UDPSocket.new
          raw = serialize(msg)

          addr = msg[:send_to]
          if addr
            host, port = addr.split(':')
            _ = socket.send(raw, 0, host, port.to_i)
          else
            $stderr.puts "quietly drop #{msg[:message_type]} unknown destination"
          end
        end
      end
    rescue => ex
      $stderr.puts "error #{ex} in sender thread"
      $stderr.puts ex.backtrace.join("\n")
      exit(2)
    end

    def heartbeat_loop
      loop do
        @in_queue << { message_type: :broadcast_heartbeat }
        sleep HEARTBEAT_TTL
      end
    end

    def processor_loop
      loop do
        while msg = @in_queue.pop
          $stderr.puts "processing #{msg[:message_type]}, #{msg[:success]} "\
            "term = #{msg[:term]}, match index = #{msg[:match_index]}  " \
            "from #{msg[:client] || msg[:peer]}"

          @node.dispatch(msg)

          expiry = (@node.seconds_until_timeout / @second_per_tick).to_f
          $stderr.puts "#{node.role.class}, term = #{node.current_term}, " \
            "cluster = #{node.cluster}, commit = #{node.last_commit}, " \
            "expires in #{expiry} ticks"
        end

        break if sigterm
      end
    rescue => ex
      $stderr.puts "error #{ex} in processor_loop"
      $stderr.puts ex.backtrace.join("\n")
      exit(2)
    end
  end
end
