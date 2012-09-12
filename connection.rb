class Connection
  attr_accessor :s
  attr_accessor :state

  STATE_CONNECTED = 2
  STATE_SHUTDOWN = 3
  STATE_CLOSED = 4
  VALID_ACCOUNT = 3
  VALID_PIN = "6089a01682dd3b70"
  VALID_ADMIN_USERNAME = "share1"
  VALID_ADMIN_PASSWORD = "6089a01682dd3b70"
  SESSION_TIMEOUT = 600

  def initialize( serv, sock )
    @s = sock[0]
    @state = STATE_CONNECTED
    @serv = serv
    @buffer = ""
  end

  def handle_data
    puts "handle_data"
    @buffer << s.gets()
    puts "@buffer: #{@buffer}"
    puts "length: #{@buffer.length}"
    puts "last_char: #{@buffer[@buffer.length - 1].to_i}"
    unless ["\n", "\r"].index( @buffer[@buffer.length - 1] ).nil?
      @serv.logger.debug "#{s.to_i} R: #{@buffer}"
      parse_and_reply( @buffer )
      @buffer = ""
    else
      puts "not full message"
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

  def handle_validate_admin(doc)
    username = doc.root.at_xpath("adminuser").text
    password = doc.root.at_xpath("adminpassword").text
    xml_text = ""
    x = Builder::XmlMarkup.new(:target => xml_text)
    x.reply do |v|
      if username.eql?(VALID_ADMIN_USERNAME) && password.eql?(VALID_ADMIN_PASSWORD)
        send_response('<reply />')
      else
        send_response('<reply><error><code>45</code><info>Invalid username/password</info></error></reply>')
      end
    end
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

  def handle_get_member_info( doc )
    type = doc.root.at_xpath( "infotypes" ).text
    case type
    when "suffixes"
      send_file('suffixes.xml')
    when "master"
      send_file('valid_member_info.xml')
    end
  end

  def handle_account_check(doc)
    tax_id = doc.root.at_xpath('LoginTaxID').text.to_s
    birth_date = Date.strptime(doc.root.at_xpath('LoginBirthDate').text.to_s, '%m/%d/%Y')
    account = ''
    if doc.root.at_xpath('LoginAccount')
      account = doc.root.at_xpath('LoginAccount').text.to_s
    end
    member_doc = Nokogiri::XML(read_file('valid_member_info.xml'))
    member_tax_id = member_doc.root.at_xpath('master/ssn').text.to_s.gsub(/[^0-9]/, '')
    member_birth_date = Date.strptime(member_doc.root.at_xpath('master/dob').text.to_s, '%m/%d/%Y')
    member_account = '3'
    code = 0
    demc = ''
    puts "birth_date: #{birth_date}"
    puts "member_birth_date: #{member_birth_date}"
    puts "equal: #{birth_date.eql?(member_birth_date)}"
    puts "tax_id: #{tax_id}"
    puts "member_tax_id: #{member_tax_id}"
    puts "equal: #{tax_id.eql?(member_tax_id)}"
    if account.eql?('')
      if birth_date.eql?(member_birth_date) && tax_id.eql?(member_tax_id)
        code = 101
        desc = 'Need Account Number'
      else
        code = 0
        desc = 'New Member'
      end
    else
      if account.eql?(member_account)
        code = 0
        desc = 'Valid Account'
      else
        code = 102
        desc = 'Invalid Account Number'
      end
    end
    send_response("<Response><function>LoanApp.AccountCheck</function><Error/><Result>#{code}</Result><ResultDesc>#{desc}</ResultDesc></Response>")
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
    histitem = doc.root.at_xpath('histitem').text unless doc.root.at_xpath('histitem').nil?

    puts "start_date: #{start_date}"
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
      unless histitem.nil?
        unless i.at_xpath('id').text.to_i.eql?(histitem.to_i)
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

  def parse_and_reply(msg)
    doc = Nokogiri::XML(msg)
    unless %w(validatemember ping adminlogin validateadmin PrepopApplicant).include?(doc.root.name)
      unless doc.root.name.downcase.eql?('request') && %w(getloantypes accountcheck).include?(doc.root.at_xpath('Function').text.downcase)
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
    end
    case doc.root.name
    when "adminlogin"
      handle_admin_login(doc)
    when "validatemember"
      handle_validate_member(doc)
    when "validateadmin"
      handle_validate_admin(doc)
    when "getmemberinfo"
      handle_get_member_info(doc)
    when 'keepalive'
      send_response('<reply><postdate>1/1/2009</postdate></reply>')
    when 'history'
      handle_history(doc)
    when 'holds'
      send_file('holds.xml')
    when 'stops'
      send_file('stops.xml')
    when 'ping'
      send_response('<pong/>')
    when 'xfer'
      send_response('<reply><confirmation>VALID CONFIRMATION</confirmation></reply>')
    when 'pinChange'
      send_response('<reply />')
    when 'Request'
      case doc.root.at_xpath('Function').text.downcase
      when 'getcurrentaddressandemail'
        send_file('valid_current_address_email.xml')
      when 'transfergetschedule'
        send_file('scheduled_transfers.xml')
      when 'transferadd'
        send_response('<Response><function>TransferAdd</function><ID>1556</ID></Response>')
      when 'alertgetpreferences'
        send_file('alert_preferences.xml')
      when 'getphonenumbers'
        send_file('phone_numbers.xml')
      when 'setcurrentemail'
        send_response('<reply/>')
      when 'setcurrentaddress'
        send_response('<reply/>')
      when 'setphonenumbers'
        send_response('<reply/>')
      when 'getloantypes'
        send_file('loan_types.xml')
      when 'accountcheck'
        handle_account_check(doc)
      when 'statementlist'
        send_file('estatements.xml')
      else
        send_response('<reply><error><code>999</code></error></reply>')
      end
    else
      send_response( '<reply><error><code>999</code></error></reply>' )
    end
  end

  private

  def read_file(filename)
    File.read(File.join(File.dirname(__FILE__), 'data', filename))
  end

  def send_file(filename)
    send_response(read_file(filename))
  end
end
