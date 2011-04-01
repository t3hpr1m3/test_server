#!/usr/bin/env ruby
#
require 'socket'
require 'thread'
require 'rubygems'
require 'nokogiri'
require 'builder'
require 'logger'
require 'date'

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

class Connection
  attr_accessor :s
  attr_accessor :state

  STATE_CONNECTED = 2
  STATE_SHUTDOWN = 3
  STATE_CLOSED = 4
  VALID_ACCOUNT = 3
  VALID_PIN = "6089a01682dd3b70"
  SESSION_TIMEOUT = 600

  def initialize( serv, sock )
    @s = sock[0]
    @state = STATE_CONNECTED
    @serv = serv
    @buffer = ""
  end

  def handle_data
    @buffer << s.gets()
    unless [ 10, 13 ].index( @buffer[@buffer.length - 1] ).nil?
      @serv.logger.debug "#{s.to_i} R: #{@buffer}"
      parse_and_reply( @buffer )
      @buffer = ""
    end
  end

  def validate_account(acct)
    acct.eql?(VALID_ACCOUNT)
  end

  def validate_pin(pin)
    return true if pin.nil?
    pin.text.eql?(VALID_PIN)
  end

  def send_response( msg )
    s.write( "#{msg.gsub(/[\r\n]/, ' ')}\n" )
    @serv.logger.debug "#{s.to_i} S: #{msg}"
  end

  def handle_admin_login( doc )
    xml_text = ''
    x = Builder::XmlMarkup.new( :target => xml_text )
    x.reply do |v|
      context = rand(999999).to_s
      @serv.contexts[context] = {:last_accessed => Time.now.to_i}
      v.context(context)
      v.systemstate "1"
      v.lastlogindate Time.now.strftime( "%m/%d/%Y" )
      v.postingdate Time.now.strftime( "%m/%d/%Y" )
    end
    send_response( xml_text )
  end

  def handle_validate_member( doc )
    err = doc.root.at_xpath( "error" )
    if err.nil?
      account = doc.root.at_xpath( "account" ).text.to_i
      pin = doc.root.at_xpath("pin")
      xml_text = ""
      x = Builder::XmlMarkup.new( :target => xml_text )
      x.reply do |v|
        if validate_account(account) and validate_pin(pin)
          context = rand( 999999 ).to_s
          @serv.contexts[context] = {:last_accessed => Time.now.to_i}
          v.context(context)
          v.systemstate "1"
          v.lastlogindate Time.now.strftime( "%m/%d/%Y" )
          v.postingdate Time.now.strftime( "%m/%d/%Y" )
        else
          v.error do |e|
            e.code "45"
          end
        end
      end
      send_response( xml_text )
    end
  end

  def handle_suffixes( doc )
    text = File.read( File.dirname( __FILE__) + "/data/suffixes.xml" )
    send_response( text )
  end

  def handle_master( doc )
    text = File.read( File.dirname( __FILE__ ) + "/data/valid_member_info.xml" )
    send_response( text )
  end

  def handle_get_member_info( doc )
    type = doc.root.at_xpath( "infotypes" ).text
    case type
    when "suffixes"
      handle_suffixes( doc )
    when "master"
      handle_master( doc )
    end
  end

  def handle_keepalive( doc )
    send_response( '<reply><postdate>1/1/2009</postdate></reply>' )
  end

  def handle_current_address_email(doc)
    text = File.read(File.dirname(__FILE__) + '/data/valid_current_address_email.xml')
    send_response(text)
  end

  def handle_transfer_get_schedule( doc )
    text = File.read( File.dirname( __FILE__ ) + "/data/scheduled_transfers.xml" )
    send_response( text )
  end

  def handle_alert_get_preferences( doc )
    text = File.read( File.dirname( __FILE__ ) + "/data/alert_preferences.xml" )
    send_response( text )
  end

  def handle_holds( doc )
    text = File.read( File.dirname( __FILE__ ) + "/data/holds.xml" )
    send_response( text )
  end

  def handle_stops(doc)
    text = File.read(File.dirname(__FILE__) + "/data/stops.xml")
    send_response(text)
  end

  def handle_get_phone_numbers(doc)
    text = File.read(File.dirname(__FILE__) + '/data/phone_numbers.xml')
    send_response(text)
  end

  def handle_history( doc )
    account = nil
    suffix_type = nil
    suffix = nil
    start_date = nil
    end_date = nil
    start_draft = nil
    end_draft = nil
    histtype = nil
    order = nil
    limit = nil
    
    root = doc.root
    @serv.logger.debug "root: #{root.inspect}"
    @serv.logger.debug "account: #{root.at_xpath( 'account' )}"
    account = root.at_xpath( 'account' ).text unless root.at_xpath( 'account' ).nil?
    suffix_type = root.at_xpath( 'suffixtype' ).text unless root.at_xpath( 'suffixtype' ).nil?
    suffix = doc.root.at_xpath( 'suffix' ).text unless doc.root.at_xpath( 'suffix' ).nil?
    start_date = doc.root.at_xpath( 'earliest_date' ).text unless doc.root.at_xpath( 'earliest_date' ).nil?
    end_date = doc.root.at_xpath( 'latest_date' ).text unless doc.root.at_xpath( 'latest_date' ).nil?
    histtype = doc.root.at_xpath( 'histtype' ).text unless doc.root.at_xpath( 'histtype' ).nil?
    order = doc.root.at_xpath( 'order' ).text unless doc.root.at_xpath( 'order' ).nil?
    limit = doc.root.at_xpath('maxTrans').text unless doc.root.at_xpath('maxTrans').nil?

    start_date = Date.strptime( start_date, '%m/%d/%Y' ) unless start_date.nil?
    end_date = Date.strptime( end_date, '%m/%d/%Y' ) unless end_date.nil?

    if account.nil? or suffix_type.nil? or suffix.nil?
      send_response( '<reply><error><code>99</code></error></reply' )
      return
    end

    unless account.eql?( '3' ) and suffix_type.eql?( 'S' ) and suffix.eql?( '1' )
      send_response( '<reply />' )
    end

    doc = Nokogiri::XML( File.read( File.dirname( __FILE__ ) + "/data/transactions.xml" ) )
    matched = 0
    items = doc.xpath( '/reply/item' ).select do |i|
      match = true
      unless start_date.nil?
        if Date.strptime( i.at_xpath( 'postdate' ).text, '%m/%d/%Y' ) < start_date
          match = false
        end
      end

      unless end_date.nil?
        if Date.strptime( i.at_xpath( 'postdate' ).text, '%m/%d/%Y' ) > end_date
          match = false
        end
      end

      if limit && matched >= limit.to_i
        match = false
      else
        matched += 1
      end
      match
    end
    if order.eql?( 'R' )
      items.sort!{ |a,b|
        adt = Date.strptime( a.at_xpath( 'postdate' ).text, '%m/%d/%Y' )
        bdt = Date.strptime( b.at_xpath( 'effdate' ).text, '%m/%d/%Y' )
        bdt <=> adt
      }
    end
    xml_text = ''
    x = Builder::XmlMarkup.new( :target => xml_text )
    x.instruct!
    x.reply do
      items.each do |i|
        x.item do |item|
          item.name( i.at_xpath( 'name' ).text )
          item.descr( i.at_xpath( 'descr' ).text )
          item.postdate( i.at_xpath( 'postdate' ).text )
          item.effdate( i.at_xpath( 'effdate' ).text )
          item.balance( i.at_xpath( 'balance' ).text )
          item.amount( i.at_xpath( 'amount' ).text )
          item.id( i.at_xpath( 'id' ).text )
          item.Source( i.at_xpath( 'Source' ).text )
          item.principal( i.at_xpath( 'principal' ).text )
          item.OFXType( i.at_xpath( 'OFXType' ).text )
        end
      end
    end
    send_response( xml_text )
  end

  def check_context(context)
    if @serv.contexts.key?(context)
      puts "Valid context...checking expiration"
      puts "Time.now: #{Time.now.to_i}"
      puts "last:     #{@serv.contexts[context][:last_accessed]}"
      if Time.now.to_i - @serv.contexts[context][:last_accessed] > SESSION_TIMEOUT
        puts "Expired context: #{context}"
        @serv.contexts.delete(context)
        false
      else
        @serv.contexts[context][:last_accessed] = Time.now.to_i
        puts "New last: #{@serv.contexts[context][:last_accessed]}"
        true
      end
    else
      puts "Invalid context: #{context}"
      puts "Valid contexts: #{@serv.contexts.inspect}"
      false
    end
  end

  def parse_and_reply( msg )
    doc = Nokogiri::XML( msg )
    unless %w(validatemember ping adminlogin).include?(doc.root.name)
      if doc.root.at_xpath('context').nil?
        send_response('<reply><error><code>52</code></error></reply>')
        return
      else
        unless check_context(doc.root.at_xpath('context').text)
          send_response('<reply><error><code>52</code></error></reply>')
          return
        end
      end
    end
    case doc.root.name
    when "adminlogin"
      handle_admin_login( doc )
    when "validatemember"
      handle_validate_member( doc )
    when "getmemberinfo"
      handle_get_member_info( doc )
    when 'keepalive'
      handle_keepalive( doc )
    when 'history'
      handle_history( doc )
    when 'holds'
      handle_holds( doc )
    when 'stops'
      handle_stops(doc)
    when 'ping'
      send_response('<pong/>')
    when 'xfer'
      send_response('<reply><confirmation>VALID CONFIRMATION</confirmation></reply>')
    when 'Request'
      case doc.root.at_xpath( 'Function' ).text.downcase
      when 'getcurrentaddressandemail'
        handle_current_address_email(doc)
      when 'transfergetschedule'
        handle_transfer_get_schedule( doc )
      when 'transferadd'
        send_response('<Response><function>TransferAdd</function><ID>1556</ID></Response>')
      when 'alertgetpreferences'
        handle_alert_get_preferences( doc )
      when 'getphonenumbers'
        handle_get_phone_numbers(doc)
      when 'setcurrentemail'
        send_response('<reply/>')
      when 'setcurrentaddress'
        send_response('<reply/>')
      when 'setphonenumbers'
        send_response('<reply/>')
      end
    else
      send_response( '' )
    end
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
