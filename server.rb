#!/usr/bin/env ruby
#
require 'socket'
require 'thread'
require 'rubygems'
require 'nokogiri'
require 'builder'
require 'logger'
require 'date'
require 'connection'

class CustomLoggerFormatter < Logger::Formatter
  def call( severity, time, program_name, message )
    dt = Time.now.strftime( "%m/%d/%Y %H:%M:%S" )
    "%19s :: %-5s %s\n" % [ dt, severity, message ]
  end
end

class ServSock
  attr_accessor :s

  def initialize( host, port )
    @s = Socket.new( Socket::Constants::AF_INET, Socket::Constants::SOCK_STREAM, 0 )
    sockaddr = Socket.pack_sockaddr_in( port, host )
    @s.setsockopt( Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true )
    @s.bind( sockaddr )
    @s.listen( 5 )
  end
end


class EftServer
  attr_accessor :logger
  attr_accessor :contexts

  def initialize( host, port )
    @host = host
    @port = port
    @shutdown = false
    @serv_sock = nil
    @conn_lock = Mutex.new
    @conns = []
    @select_thread = nil
    @logger = Logger.new( STDOUT )
    @logger.formatter = CustomLoggerFormatter.new
    @logger.level = Logger::DEBUG
    @contexts = {}
  end

  def shutdown
    logger.debug "Shutting down server"
    @shutdown = true
    @serv_sock.s.shutdown
  end

  def run
    @serv_sock = ServSock.new( @host, @port )
    @conns << @serv_sock
    #while not @shutdown do
    while @conns.length > 0
      if @shutdown
        # shutdown all sockets
        @conns.each do |c|
          unless c.eql?( @serv_sock )
            unless c.state.eql?( Connection::STATE_SHUTDOWN )
              logger.debug( "Shutting down #{c.s.to_i}" )
              c.state = Connection::STATE_SHUTDOWN
              c.s.shutdown( 2 )
              c.s.close
              @conns.delete( c )
            end
          end
        end
        next
      end
      read_fds = []
      write_fds = []
      excp_fds = []
      @conns.each do |c|
        read_fds << c.s
      end

      res = IO.select( read_fds, write_fds, excp_fds, 5 )
      if not res.nil?

        res[0].each do |s|
          conn = nil
          @conns.each do |c|
            if s == c.s
              conn = c
              break
            end
          end
          if not conn.nil?
            if conn.eql?( @serv_sock )
              ##
              ## Server
              ##
              if @shutdown
                logger.debug 'Shutdown triggered'
                @serv_sock.s.close
                @conns.delete( @serv_sock )
              else
                @conns << Connection.new( self, @serv_sock.s.accept )
                logger.debug 'accepted a connection'
              end
            else
              ##
              ## Clients
              ##
              if s.eof?
                if conn.state.eql?( Connection::STATE_SHUTDOWN )
                  logger.debug( "Connection #{s.to_i} fully closed" )
                  s.close
                  @conns.delete( conn )
                else
                  logger.debug( "Connection #{s.to_i} wants shutdown" )
                  conn.state = Connection::STATE_SHUTDOWN
                  s.shutdown( 1 )
                end
              else
                conn.handle_data
              end
            end
          end
        end
      end
    end
  end
end

trap( "INT" ) { $serv.shutdown }
$serv = EftServer.new( 'localhost', 5025 )
$serv.run

puts "Shutting down"
